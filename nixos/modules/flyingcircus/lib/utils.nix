{ lib, fclib, ... }:
with lib;
rec {

  # get the DN of this node for LDAP logins.
  getLdapNodeDN = config:
    "cn=${config.networking.hostName},ou=Nodes,dc=gocept,dc=com";

  # Compute LDAP password for this node.
  getLdapNodePassword = config:
    builtins.hashString "sha256" (concatStringsSep "/" [
      "ldap"
      config.flyingcircus.enc.parameters.directory_password
      config.networking.hostName
    ]);

  mkPlatform = lib.mkOverride 900;

  coalesce = list: findFirst (el: el != null) null list;

  servicePassword =
    { pkgs        # XXX Is there a way to get pkgs here w/o passing?
    , file
    , user ? "root"
    , mode ? "0660"
    , token ? ""  # personalize derivation to prevent Nix hash collisions
    }:
    let
      name = builtins.replaceStrings ["/"] ["-"] file;
      generatePasswordCommand =
        "${pkgs.apg}/bin/apg -a 1 -M lnc -n 1 -m 32 -d -c \"${token}\"";
      generatedPassword =
        readFile (
          pkgs.runCommand name { preferLocalBuild = true; }
          "${generatePasswordCommand} > $out");

      # Only install directory if not there, otherwise, permissions might
      # change.
      generatorShellScript = how: ''
        install -d $(dirname ${file})
        if [[ ! -e ${file} ]]; then
          ( umask 007;
            ${how} > ${file}
            chown ${user}:service ${file}
          )
        fi
        chmod ${mode} ${file}
        '';

    in rec {
      inherit file;

      # Generate in activation, with usable password.value, but with password
      # in nix store.
      activation = generatorShellScript "echo -n ${generatedPassword}";

      # Generate in preStart of service. password.value is *not* usable, but
      # no password is being stored in nix store.
      generate = generatorShellScript generatePasswordCommand;

      # Password value for nix configuration. Accessing makes the password
      # to be stored in nix store. A warning is issued.
      value = removeSuffix "\n" (fclib.configFromFile file generatedPassword);
    };

}
