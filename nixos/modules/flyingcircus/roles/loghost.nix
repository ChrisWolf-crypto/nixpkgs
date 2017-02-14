{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus.roles.loghost;
  fclib = import ../lib;

  listenOn = head (fclib.listenAddresses config "ethsrv");
  serviceUser = "graylog";

  loghostService = findFirst
    (s: s.service == "loghost-server")
    null
    config.flyingcircus.enc_services;

  # -- files --
  rootPasswordFile = "/etc/local/graylog/password";
  passwordSecretFile = "/etc/local/graylog/password_secret";
  # -- passwords --
  generatedRootPassword = mkPassword "graylog.rootPassword";
  generatedPasswordSecret = mkPassword "graylog.passwordSecret";

  rootPassword = removeSuffix "\n"
    (if cfg.rootPassword  == null
    then (fclib.configFromFile
            rootPasswordFile
            generatedRootPassword)
    else cfg.rootPassword);

  rootPasswordSha2 = mkSha2 rootPassword;

  passwordSecret =
    if cfg.passwordSecret == null
    then (fclib.configFromFile
            passwordSecretFile
            generatedPasswordSecret)
    else cfg.passwordSecret;


  port = 9000;
  webListenUri = "http://${listenOn}:${toString port}/tools/${config.flyingcircus.enc.name}/graylog";
  restListenUri = "http://${listenOn}:${toString port}/tools/${config.flyingcircus.enc.name}/graylog/api";

  # -- helper functions --
  passwordActivation = file: password: user:
    let script = ''
     install -d -o ${toString config.ids.uids."${user}"} -g service -m 02775 \
        $(dirname ${file})
      if [[ ! -e ${file} ]]; then
        ( umask 007;
          echo ${password} > ${file}
          chown ${user}:service ${file}
        )
      fi
      chmod 0660 ${file}
    '';
    in script;

  mkPassword = identifier:
    removeSuffix "\n" (readFile
      (pkgs.runCommand identifier {}
        "${pkgs.apg}/bin/apg -a 1 -M lnc -n 1 -m 32 > $out")
      );

  mkSha2 = text:
    removeSuffix "\n" (readFile
      (pkgs.runCommand "dummy" { inherit text; }
        "echo -n $text | sha256sum | cut -f1 -d \" \" > $out")
      );

  logstashSSLHelper = pkgs.writeScriptBin "logstash_ssl_import" ''
    #!${pkgs.bash}/bin/bash
    set -e

    puppet="puppet.$FCIO_LOCATION.gocept.net"
    hostname="$(hostname)"
    pw=$(pwgen -1 18)

    scp -q $puppet:/var/lib/puppet/lumberjack/keys/$hostname.{crt,key} /var/lib/graylog/
    (cd /var/lib/graylog/
     openssl pkcs12 -export -in $hostname.crt \
                 -inkey $hostname.key \
                 -out $hostname.p12 \
                 -name $hostname \
                 -passin pass:$pw \
                 -passout pass:$pw
     rm -f $hostname.jks
     keytool -importkeystore -srckeystore $hostname.p12 \
                 -srcstoretype PKCS12\
                 -srcstorepass $pw \
                 -alias $hostname \
                 -deststorepass $pw \
                 -destkeypass $pw \
                 -destkeystore $hostname.jks
                 )
    echo "keystore: /var/lib/graylog/$hostname.jks"
    echo "password: $pw"
    '';

  syslogPort = 5140;

in
{

  options = {

    flyingcircus.roles.loghost = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable the Flying Circus graylog server role.";
      };

      rootPassword = mkOption {
        type = types.nullOr types.string;
        default = null;
        description = ''
          The password for of your graylogs's webui root user. If null, a random password will be generated.
        '';
      };

      passwordSecret = mkOption {
        type = types.nullOr types.string;
        default = null;
        description = ''
          A password secret for graylog. Use the same password secret fo the whole graylog
          cluster. If null, a random password will be generated.
        '';
      };
    };

  };

  config = mkMerge [
    (mkIf cfg.enable {

      environment.systemPackages = [ logstashSSLHelper ];

      # XXX Access should *only* be allowed from directory and same-rg.
      networking.firewall.allowedTCPPorts = [ port ];

      system.activationScripts.fcio-loghost =
        stringAfter
          [ ]
          (passwordActivation rootPasswordFile rootPassword serviceUser +
           passwordActivation passwordSecretFile passwordSecret serviceUser);

      services.graylog = {
        enable = true;
        elasticsearchClusterName = "graylog";
        inherit passwordSecret rootPasswordSha2 webListenUri restListenUri;
        elasticsearchDiscoveryZenPingUnicastHosts =
          "${config.networking.hostName}.${config.networking.domain}:9300";
        # ipv6 would be nice too
        extraConfig = ''
          trusted_proxies 195.62.125.243/32, 195.62.125.11/32, 172.22.49.56/32
        '';
      };

      flyingcircus.roles.mongodb.enable = true;
      flyingcircus.roles.elasticsearch = {
        enable = true;
        dataDir = "/var/lib/elasticsearch";
        clusterName = "graylog";
        heapDivisor = 3;
        esNodes = ["${config.networking.hostName}.${config.networking.domain}:9350"];
      };

      systemd.services.configure-inputs-for-graylog = {
         description = "Enable Inputs for Graylog";
         requires = [ "graylog.service" ];
         after = [ "graylog.service" ];
         serviceConfig = {
           Type = "oneshot";
           User = "graylog";
         };
         script = let
           api = restListenUri;
           user = "admin";
           pw = rootPassword;

           input_body = {
             configuration = {
               bind_address = "0.0.0.0";
               expand_structured_data = false;
               force_rdns = false;
               recv_buffer_size = 262144;
               store_full_message =  false;
               allow_override_date =  true;
               port = syslogPort;
             };
             title = "Syslog UDP"; # be careful changing it, it's used as
                                   # a primary key for identifying the config
                                   # object
             type = "org.graylog2.inputs.syslog.udp.SyslogUDPInput";
             global = false;
           };
          sso_body = {
            default_group = "Admin";
            auto_create_user = true;
            username_header = "Remote-User";
            require_trusted_proxies = true;
            trusted_proxies = "95.62.125.11/32, 195.62.125.243/32, 172.22.49.56/32";
          };
        in
          ''${pkgs.fcmanage}/bin/fc-graylog \
          -u '${user}' \
          -p '${removeSuffix "\n" pw}' \
          '${api}' \
          '${builtins.toJSON input_body}' \
          '${builtins.toJSON sso_body}'
          '' ;
      };

      systemd.services.graylog-update-geolite = {
        description = "Update geolite db for graylog";
        restartIfChanged = false;
        after = [ "network.target" ];
        serviceConfig = {
          User = config.services.graylog.user;
          Type = "oneshot";
        };

        script = ''
          cd /var/lib/graylog
          ${pkgs.curl}/bin/curl -O http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz
          ${pkgs.gzip}/bin/gunzip -f GeoLite2-City.mmdb.gz
        '';
      };

      systemd.timers.graylog-update-geolite = {
        description = "Timer for updading the geolite db for graylog";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          Unit = "graylog-update-geolite.service";
          OnStartupSec = "10m";
          OnUnitActiveSec = "30d";
          # Not yet supported by our systemd version.
          # RandomSec = "3m";
        };
      };

      services.collectd.extraConfig = ''
        LoadPlugin curl_json
        <Plugin curl_json>
          <URL "${restListenUri}/system/journal">
            User "admin"
            Password "${rootPassword}"
            Header "Accept: application/json"
            Instance "graylog"
            <Key "uncommitted_journal_entries">
              Type "gauge"
            </Key>
            <Key "append_events_per_second">
              Type "gauge"
            </Key>
            <Key "read_events_per_second">
              Type "gauge"
            </Key>
          </URL>
          <URL "${restListenUri}/system/throughput">
            User "admin"
            Password "${rootPassword}"
            Header "Accept: application/json"
            Instance "graylog"
            <Key "throughput">
              Type "gauge"
            </Key>
        </URL>
        </Plugin>
      '';

    flyingcircus.services.sensu-client.checks = {
      graylog_ui = {
        notification = "Graylog UI alive";
        command = ''
          check_http -H ${listenOn} -p ${toString port} \
            -u /tools/${config.networking.hostName}/graylog/
        '';
      };
    };

    })
    # This configuration part defines loghosts clients as loghosts which happen to be their own clients as well
    (mkIf (loghostService != null) {
      services.rsyslogd.extraConfig = ''
        *.* @${loghostService.address}:${toString syslogPort};RSYSLOG_SyslogProtocol23Format
      '';
    }
    )];
  }
