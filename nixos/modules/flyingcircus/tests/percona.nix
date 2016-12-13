import ../../../tests/make-test.nix ({ pkgs, lib, percona, ... }:
{
  name = "percona";

  nodes = {
    master =
      { pkgs, config, ... }:
      {
        virtualisation.memorySize = 2048;

        imports = [
          ./setup.nix
          ../static/default.nix
          ../roles/default.nix
          ../services/default.nix
          ../platform/default.nix
        ];

        flyingcircus.ssl.generate_dhparams = false;
        flyingcircus.roles.mysql.enable = true;
        flyingcircus.roles.mysql.package = percona;

        # Tune those arguments as we'd like to run this on Hydra
        # in a rather small VM.
        flyingcircus.roles.mysql.extraConfig = ''
            [mysqld]
            innodb-buffer-pool-size         = 10M
            innodb_log_file_size            = 10M
        '';

      };
  };

  testScript = ''
    startAll;

    $master->waitForUnit("mysql");
    $master->sleep(1);
    $master->succeed("mysqladmin ping");
    $master->succeed("mysql mysql -e 'select * from user' > /dev/null");
  '';
})
