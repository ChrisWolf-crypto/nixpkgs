{ config, lib, pkgs, ... }: with lib;

let
  cfg = config.flyingcircus;
  fclib = import ../lib;

  haproxyCfg = fclib.configFromFile /etc/local/haproxy/haproxy.cfg example;
  statsSocket = "/run/haproxy_admin.sock";

  example = ''
    # haproxy configuration example - copy to haproxy.cfg and adapt.

    global
        daemon
        chroot /var/empty
        user haproxy
        group haproxy
        maxconn 4096
        log localhost local2
        stats socket ${statsSocket} mode 660 group nogroup level operator

    defaults
        mode http
        log global
        option httplog
        option dontlognull
        option http-server-close
        timeout connect 5s
        timeout client 30s    # should be equal to server timeout
        timeout server 30s    # should be equal to client timeout
        timeout queue 25s     # discard requests sitting too long in the queue

    listen http-in
        bind 127.0.0.1:8002
        bind ::1:8002
        default_backend be

    backend be
        server localhost localhost:8080
    '';

in
{

  options = {

    flyingcircus.roles.haproxy = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable the Flying Circus haproxy server role.";
      };

    };

  };

  config = mkMerge [

  (mkIf config.flyingcircus.roles.haproxy.enable {

    services.haproxy.enable = true;
    services.haproxy.config = haproxyCfg;
    system.activationScripts.haproxy = ''
      install -d -o ${toString config.ids.uids.haproxy} -g service -m 02775 \
        /etc/local/haproxy
    '';

    environment.etc = {
      "local/haproxy/README.txt".text = ''
        HAProxy is enabled on this machine.

        Put your haproxy configuration here as `haproxy.cfg`. There is also
        an example configuration here.
      '';
      "local/haproxy/haproxy.cfg.example".text = example;
      "haproxy.cfg" = {
        source = /etc/local/haproxy/haproxy.cfg;
        enable = cfg.compat.gentoo.enable;
      };
      "haproxy" = {
        source = /etc/local/haproxy;
        enable = cfg.compat.gentoo.enable;
      };
    };

    flyingcircus.syslog.separateFacilities = {
      local2 = "/var/log/haproxy.log";
    };

    systemd.services.prometheus-haproxy-exporter = {
      description = "Prometheus exporter for haproxy metrics";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.haproxy ];
      script = ''
        exec ${pkgs.prometheus-haproxy-exporter}/bin/haproxy_exporter \
          --web.listen-address localhost:9127 \
          --haproxy.scrape-uri=unix:${statsSocket}
      '';
      serviceConfig = {
        User = "nobody";
        Restart = "always";
        PrivateTmp = true;
        WorkingDirectory = /tmp;
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      };
    };

    services.telegraf.inputs = {
      prometheus  = [{
        urls = ["http://localhost:9127/metrics"];
      }];
    };
  })

 {
    flyingcircus.roles.statshost.prometheusMetricRelabel = [
      # Remove _counter and _gauge postfixes which telegraf adds. See
      # https://github.com/influxdata/telegraf/issues/2950
      { source_labels = ["__name__"];
       regex = "haproxy_(.+)_(counter|gauge)";
       replacement = "haproxy_\${1}";
       target_label = "__name__";
      }
    ];
  }

  ];
}
