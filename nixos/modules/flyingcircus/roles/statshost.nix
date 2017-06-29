# statshost: an InfluxDB/Grafana server. Accepts incoming graphite traffic,
# stores it and renders graphs.
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus.roles.statshost;
  cfg_proxy = config.flyingcircus.roles.statshostproxy;

  # can be replaced with pkgs.influxdb once InfluxDB 0.11 is present in upstream
  # nixpkgs.
  influxdb = (pkgs.callPackage ../packages/influxdb.nix { }).bin //
    { outputs = [ "bin" ]; };

  statshost_service = lib.findFirst
    (s: s.service == "statshost-collector")
    null
    config.flyingcircus.enc_services;

in
{
  options = {
    flyingcircus.roles.statshost = {
      enable = mkEnableOption "Grafana/InfluxDB stats host";

      useSSL = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enables SSL in the virtual host.

          Expects the SSL certificates and keys to be placed in
          /etc/local/nginx/stats.crt and /etc/local/nginx/stats.key
        '';
      };

      hostName = mkOption {
        type = types.str;
        default = "stats.flyingcircus.io";
        description = "HTTP host name for the stats frontend. Must be set.";
        example = "stats.example.com";
      };
    };

    flyingcircus.roles.statshostproxy = {
      enable = mkEnableOption "Enable stats proxy.";
    };

  };

  config = mkMerge [
    (mkIf cfg.enable {

      # make the 'influx' command line tool accessible
      environment.systemPackages = [ influxdb ];

      services.influxdb011.enable = true;
      services.influxdb011.dataDir = "/srv/influxdb";
      services.influxdb011.package = influxdb;

      services.influxdb011.extraConfig = {
        http.enabled = true;
        http.auth-enabled = false;

        graphite = [
          { enabled = true;
            protocol = "udp";
            udp-read-buffer = 8388608;
            templates = [
              # new hierarchy
              "fcio.*.*.*.*.*.ceph .location.resourcegroup.machine.profile.host.measurement.instance..field"
              "fcio.*.*.*.*.*.cpu  .location.resourcegroup.machine.profile.host.measurement.instance..field"
              "fcio.*.*.*.*.*.load .location.resourcegroup.machine.profile.host.measurement..field"
              "fcio.*.*.*.*.*.netlink .location.resourcegroup.machine.profile.host.measurement.instance.field*"
              "fcio.*.*.*.*.*.entropy .location.resourcegroup.machine.profile.host.measurement.field"
              "fcio.*.*.*.*.*.swap .location.resourcegroup.machine.profile.host.measurement..field"
              "fcio.*.*.*.*.*.uptime .location.resourcegroup.machine.profile.host.measurement.field"
              "fcio.*.*.*.*.*.processes .location.resourcegroup.machine.profile.host.measurement.field*"
              "fcio.*.*.*.*.*.users .location.resourcegroup.machine.profile.host.measurement.field"
              "fcio.*.*.*.*.*.vmem .location.resourcegroup.machine.profile.host.measurement..field"
              "fcio.*.*.*.*.*.disk .location.resourcegroup.machine.profile.host.measurement.instance.field*"
              "fcio.*.*.*.*.*.interface .location.resourcegroup.machine.profile.host.measurement.instance.field*"
              "fcio.*.*.*.*.*.postgresql .location.resourcegroup.machine.profile.host.measurement.instance.field*"
              "fcio.*.*.*.*.*.*.memory .location.resourcegroup.machine.profile.host.measurement..field*"
              "fcio.*.*.*.*.*.curl_json.*.*.* .location.resourcegroup.machine.profile.host..measurement..field*"
              "fcio.*.*.*.*.*.df.*.df_complex.* .location.resourcegroup.machine.profile.host.measurement.instance..field"
              "fcio.*.*.*.*.*.conntrack.* .location.resourcegroup.machine.profile.host.measurement.field*"

              # Generic collectd plugin: measurement/instance/field (i.e. load/loadl/longtermn)
              "fcio.* .location.resourcegroup.machine.profile.host.measurement.field*"

              # old hierarchy
              "fcio.*.*.*.ceph .location.resourcegroup.host.measurement.instance..field"
              "fcio.*.*.*.cpu  .location.resourcegroup.host.measurement.instance..field"
              "fcio.*.*.*.load .location.resourcegroup.host.measurement..field"
              "fcio.*.*.*.netlink .location.resourcegroup.host.measurement.instance.field*"
              "fcio.*.*.*.entropy .location.resourcegroup.host.measurement.field"
              "fcio.*.*.*.swap .location.resourcegroup.host.measurement..field"
              "fcio.*.*.*.uptime .location.resourcegroup.host.measurement.field"
              "fcio.*.*.*.processes .location.resourcegroup.host.measurement.field*"
              "fcio.*.*.*.users .location.resourcegroup.host.measurement.field"
              "fcio.*.*.*.vmem .location.resourcegroup.host.measurement..field"
              "fcio.*.*.*.disk .location.resourcegroup.host.measurement.instance.field*"
              "fcio.*.*.*.interface .location.resourcegroup.host.measurement.instance.field*"
            ];
          }
        ];
      };

      boot.kernel.sysctl."net.core.rmem_max" = 8388608;

      services.grafana = {
        enable = true;
        port = 3001;
        addr = "127.0.0.1";
        rootUrl = "http://${cfg.hostName}/grafana";
      };

      services.collectdproxy.statshost.enable = true;
      services.collectdproxy.statshost.send_to = "${cfg.hostName}:2003";

      flyingcircus.roles.nginx.enable = true;

      flyingcircus.roles.nginx.httpConfig =
        let
          httpHost = cfg.hostName;
          common = ''
            server_name ${httpHost};

            location /.well-known {
              root /tmp/letsencrypt;
            }

            location / {
                rewrite . /grafana/ redirect;
            }

            location /grafana/ {
                proxy_pass http://localhost:3001/;
            }

            location /grafana/public {
                alias ${config.services.grafana.staticRootPath};
            }
          '';
        in
        if cfg.useSSL then ''
          server {
              listen *:80;
              listen [::]:80;
              server_name ${httpHost};
              rewrite . https://$server_name$request_uri redirect;
          }

          server {
              listen *:443 ssl;
              listen [::]:443 ssl;
              ${common}

              ssl_certificate ${/etc/local/nginx/stats.crt};
              ssl_certificate_key ${/etc/local/nginx/stats.key};
              # add_header Strict-Transport-Security "max-age=31536000";
          }
        ''
        else
        ''
          server {
              listen *:80;
              listen [::]:80;
              ${common}
          }
        '';

      networking.firewall.allowedTCPPorts = [ 80 443 2004 ];
      networking.firewall.allowedUDPPorts = [ 2003 ];
    })

    (mkIf (cfg_proxy.enable && statshost_service != null) {
      services.collectdproxy.location.enable = true;
      services.collectdproxy.location.statshost = cfg.hostName;
      services.collectdproxy.location.listen_addr = config.networking.hostName;
      networking.firewall.allowedUDPPorts = [ 2003 ];

    })
  ];
}

# vim: set sw=2 et:
