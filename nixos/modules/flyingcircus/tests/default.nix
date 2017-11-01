{ pkgs, lib, system, hydraJob }:

{
  elasticsearch = hydraJob (import ./elasticsearch.nix { inherit system; });

  haproxy = hydraJob (import ./haproxy.nix { inherit system; }) ;

  login = hydraJob (import ./login.nix { inherit system; }) ;

  mariadb = hydraJob (import ./mariadb.nix { inherit system; });

  memcached = hydraJob (import ./memcached.nix { inherit system; }) ;

  mongodb = hydraJob (import ./mongodb { inherit system; }) ;

  inherit (import ./nodejs.nix { inherit system hydraJob; })
    nodejs_4 nodejs_6 nodejs_7;

  inherit (import ./mysql.nix { inherit system hydraJob; })
    mysql_5_5 mysql_5_6 mysql_5_7;

  no_systemd_cycles = hydraJob (import ./no_systemd_cycles.nix { inherit system; }) ;

  oraclejava = hydraJob (import ./oraclejava.nix { inherit system; });

  pdftk = hydraJob (import ./pdftk.nix { inherit system; });

  postgresql_9_3 = hydraJob
    (import ./postgresql.nix { rolename = "postgresql93"; });
  postgresql_9_4 = hydraJob
    (import ./postgresql.nix { rolename = "postgresql94"; });
  postgresql_9_5 = hydraJob
    (import ./postgresql.nix { rolename = "postgresql95"; });
  postgresql_9_6 = hydraJob
    (import ./postgresql.nix { rolename = "postgresql96"; });

  prometheus = hydraJob (import ./prometheus.nix { inherit system; });

  rabbitmq = hydraJob (import ./rabbitmq.nix { inherit system; });

  sensuserver = hydraJob (import ./sensu.nix { inherit system; });

  users = hydraJob (import ./users { inherit system; });
}
