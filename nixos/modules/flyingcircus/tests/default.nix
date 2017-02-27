{ pkgs, lib, system, hydraJob }:

{
  elasticsearch = hydraJob (import ./elasticsearch.nix { inherit system; });

  memcached = hydraJob (import ./memcached.nix { inherit system; }) ;

  login = hydraJob (import ./login.nix { inherit system; }) ;

  mongodb = hydraJob (import ./mongodb { inherit system; }) ;

  mysql_5_5 = hydraJob
    (import ./percona.nix {
      inherit system;
      percona = pkgs.mysql55;
    });

  nodejs6 = hydraJob
    (import ./nodejs6.nix {
      inherit system;
    });

  percona_5_7 = hydraJob
    (import ./percona.nix {
      inherit system;
      percona = pkgs.percona56;
    });
  percona_5_6 = hydraJob
    (import ./percona.nix {
      inherit system;
      percona = pkgs.percona57;
    });

  postgresql_9_3 = hydraJob
    (import ./postgresql.nix { rolename = "postgresql93"; });
  postgresql_9_4 = hydraJob
    (import ./postgresql.nix { rolename = "postgresql94"; });
  postgresql_9_5 = hydraJob
    (import ./postgresql.nix { rolename = "postgresql95"; });
  postgresql_9_6 = hydraJob
    (import ./postgresql.nix { rolename = "postgresql96"; });

  rabbitmq = hydraJob (import ./rabbitmq.nix { inherit system; });

  sensuserver = hydraJob (import ./sensu.nix { inherit system; });

  users = hydraJob (import ./users { inherit system; });
}
