import ../../../tests/make-test.nix ({ pkgs, ... }:
let
  agent_updates_channel_with_maintenance = pkgs.writeScript "agent-updates-channel-with-maintenance" ''
      #!/bin/sh
      set -x
      x=$(grep ExecStart /etc/systemd/system/fc-manage.service)
      x=''${x/ExecStart=/}
      cat $x
      grep 'channel-with-maintenance' $x
      '';
in
  {
  name = "fc-manage";
  nodes = {
    prod =
      { config, lib, ... }:
      {
        imports = [
          ./setup.nix
          ../platform
          ../roles
          ../services
          ../static
        ];
        config.flyingcircus.agent.enable = lib.mkForce true;
        config.flyingcircus.enc.parameters.production = true;
      };

    nonprod =
      { config, lib, ... }:
      {
        imports = [
          ./setup.nix
          ../platform
          ../roles
          ../services
          ../static
        ];
        config.flyingcircus.agent.enable = lib.mkForce true;
        config.flyingcircus.enc.parameters.production = false;
      };

  };
  testScript = ''
    $nonprod->waitForUnit('multi-user.target');
    $nonprod->fail('${agent_updates_channel_with_maintenance}');

    $prod->waitForUnit('multi-user.target');
    $prod->succeed('${agent_updates_channel_with_maintenance}');
  '';
})

