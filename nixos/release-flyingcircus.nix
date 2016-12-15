# This jobset is used to generate a NixOS channel that contains a
# small subset of Nixpkgs, mostly useful for servers that need fast
# security updates.

{ nixpkgs ? { outPath = ./..; revCount = 56789; shortRev = "gfedcba"; }
, stableBranch ? false
, supportedSystems ? [ "x86_64-linux" ] # no i686-linux
, buildImage ? true
, buildInstaller ? true
}:

with import ../lib;

let

  nixpkgsSrc = nixpkgs; # urgh

  pkgs = import ./.. {};

  system = "x86_64-linux";

  lib = pkgs.lib;

  nixos' = import ./release.nix {
    inherit stableBranch supportedSystems;
    nixpkgs = nixpkgsSrc;
  };

  nixpkgs' = builtins.removeAttrs (import ../pkgs/top-level/release.nix {
    inherit supportedSystems;
    nixpkgs = nixpkgsSrc;
  }) [ "unstable" ];

  forAllSystems = lib.genAttrs supportedSystems;

  versionModule =
    { system.nixosVersionSuffix = versionSuffix;
      system.nixosRevision = nixpkgs.rev or nixpkgs.shortRev;
    };

  version = builtins.readFile ../.version;
  versionSuffix =
    (if stableBranch then "." else "pre") + "${toString (nixpkgs.revCount - 67824)}.${nixpkgs.shortRev}";

  # A bootable Flying Circus disk image (raw) that can be extracted onto
  # Ceph RBD volume.
  flyingcircus_vm_image =
    with import nixpkgsSrc { inherit system; };
    with lib;
    let
      config = (import lib/eval-config.nix {
        inherit system;
        modules = [ versionModule
                   ./modules/flyingcircus
                   ./modules/flyingcircus/imaging/vm.nix ];
      }).config;
    in
      # Declare the image as a build product so that it shows up in Hydra.
      hydraJob (runCommand "nixos-flyingcircus-vm-${config.system.nixosVersion}-${system}"
        { meta = {
            description = "NixOS Flying Circus VM bootstrap image (${system})";
            maintainers = maintainers.theuni;
          };
          image = config.system.build.flyingcircusVMImage;
        }
        ''
          mkdir -p $out/nix-support
          echo "file raw $image/image.qcow2.bz2" >> $out/nix-support/hydra-build-products
          ln -s $image/image.qcow2.bz2 $out/
        '');

  flyingcircus_vm_image_build =
    if buildImage
    then { flyingcircus_vm_image = flyingcircus_vm_image; }
    else {};

  # List of package names for Python packages defined in modules/flyingcircus
  ownPythonPackages = builtins.attrNames
    (import modules/flyingcircus/packages/python-packages.nix {
      inherit pkgs stdenv;
      python = null; self = null; buildPythonPackage = a: {};
    });

  # pull only those derivations which are mentioned in pkgList
  filterPkgs = pkgList: pkgs:
    let
      # select relevant packages from pkgsList parameter
      p = lib.attrVals pkgList pkgs;
    in
    # assemble attrset
    builtins.listToAttrs
      (lib.zipListsWith (fst: snd: lib.nameValuePair fst snd) pkgList p);

in rec {
  nixos = {
    inherit (nixos')
      channel
      dummy;
    tests = {
      inherit (nixos'.tests)
        containers
        firewall
        ipv6
        login
        misc
        nat
        nfs4

        postgresql
        openssh
        proxy
        simple;

      flyingcircus = {
        elasticsearch = hydraJob
        (import modules/flyingcircus/tests/elasticsearch.nix {
          inherit system;
        });
        percona_5_7 = hydraJob
          (import modules/flyingcircus/tests/percona.nix {
            inherit system;
            percona = pkgs.percona56;
          });
        percona_5_6 = hydraJob
          (import modules/flyingcircus/tests/percona.nix {
            inherit system;
            percona = pkgs.percona57;
          });
        mysql_5_5 = hydraJob
          (import modules/flyingcircus/tests/percona.nix {
            inherit system;
            percona = pkgs.mysql55;
          });
        sensuserver = hydraJob
          (import modules/flyingcircus/tests/sensu.nix { inherit system; });
      };

      networking.scripted = {
        inherit (nixos'.tests.networking.scripted)
          static
          dhcpSimple
          dhcpOneIf
          sit
          vlan;
      };
    };
  };

  nixpkgs =
    builtins.removeAttrs
      (import modules/flyingcircus/packages/all-packages.nix { inherit pkgs; })
      [ "linuxPackages" "linuxPackages_4_4" ]
    // {
      python27Packages =
        filterPkgs ownPythonPackages nixpkgs'.python27Packages;
      python34Packages =
        filterPkgs ownPythonPackages nixpkgs'.python34Packages;
    };

  tested = lib.hydraJob (pkgs.releaseTools.aggregate {
    name = "nixos-${nixos.channel.version}";
    meta = {
      description = "Release-critical builds for the NixOS channel";
      maintainers = [ lib.maintainers.theuni ];
    };
    constituents =
      (lib.collect lib.isDerivation nixpkgs)
      ++ (lib.collect lib.isDerivation nixos)
      ++ (if buildImage then [flyingcircus_vm_image] else []);
  });

}
// flyingcircus_vm_image_build
