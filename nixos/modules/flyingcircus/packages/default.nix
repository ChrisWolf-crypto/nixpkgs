{ ... }:

{
  nixpkgs.config.packageOverrides = pkgs: rec {

    boost159 = pkgs.callPackage ./boost-1.59.nix { };

    fcmaintenance = pkgs.callPackage ./fcmaintenance { };
    fcmanage = pkgs.callPackage ./fcmanage { };
    fcutil = pkgs.callPackage ./fcutil { };

    nagiosplugin = pkgs.callPackage ./nagiosplugin.nix { };

    powerdns = pkgs.callPackage ./powerdns.nix { };

    percona = pkgs.callPackage ./percona.nix { boost = boost159; };

    xtrabackup = pkgs.callPackage ./xtrabackup.nix { };
    qpress = pkgs.callPackage ./qpress.nix { };

    qemu = pkgs.callPackage ./qemu-2.5.nix {
      inherit (pkgs.darwin.apple_sdk.frameworks) CoreServices Cocoa;
      x86Only = true;
    };

    sensu = pkgs.callPackage ./sensu { };
    uchiwa = pkgs.callPackage ./uchiwa { };

  };
}
