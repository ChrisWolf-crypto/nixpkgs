# Backported from 16.03

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.graylog;

  dataDir = "/var/lib/graylog";
  pluginDir = "${dataDir}/plugins";
  pidFile = "/run/graylog/graylog.pid";
  configBool = b: if b then "true" else "false";

  confFile = pkgs.writeText "graylog.conf" ''
    is_master = ${configBool cfg.isMaster}
    node_id_file = ${cfg.nodeIdFile}
    password_secret = ${cfg.passwordSecret}
    root_username = ${cfg.rootUsername}
    root_password_sha2 = ${cfg.rootPasswordSha2}
    elasticsearch_hosts = ${concatStringsSep "," cfg.elasticsearchHosts}
    elasticsearch_discovery_enabled = ${if cfg.elasticSearchDiscoveryEnabled then "true" else "false"}
    message_journal_dir = ${cfg.messageJournalDir}
    mongodb_uri = ${cfg.mongodbUri}
    web_listen_uri = ${cfg.webListenUri}
    timezone=${config.time.timeZone}
    rest_listen_uri = ${cfg.restListenUri}
    plugin_dir = ${pluginDir}
    ${cfg.extraConfig}
  '';

  glPlugins = pkgs.buildEnv {
    name = "graylog-plugins";
    paths = cfg.plugins;
  };

in

{
  ###### interface

  options = {

    services.graylog = {

      enable = mkEnableOption "Graylog";

      package = mkOption {
        type = types.package;
        default = pkgs.graylog;
        defaultText = "pkgs.graylog";
        example = literalExample "pkgs.graylog";
        description = "Graylog package to use.";
      };

      user = mkOption {
        type = types.str;
        default = "graylog";
        example = literalExample "graylog";
        description = "User account under which graylog runs";
      };

      isMaster = mkOption {
        type = types.bool;
        default = true;
        description = "Whether this is the master instance of your Graylog cluster";
      };

      nodeIdFile = mkOption {
        type = types.str;
        default = "${dataDir}/server/node-id";
        description = "Path of the file containing the graylog node-id";
      };

      passwordSecret = mkOption {
        type = types.str;
        description = ''
          You MUST set a secret to secure/pepper the stored user passwords here. Use at least 64 characters.
          Generate one by using for example: pwgen -N 1 -s 96
        '';
      };

      rootUsername = mkOption {
        type = types.str;
        default = "admin";
        description = "Name of the default administrator user";
      };

      rootPasswordSha2 = mkOption {
        type = types.str;
        example = "e3c652f0ba0b4801205814f8b6bc49672c4c74e25b497770bb89b22cdeb4e952";
        description = ''
          You MUST specify a hash password for the root user (which you only need to initially set up the
          system and in case you lose connectivity to your authentication backend)
          This password cannot be changed using the API or via the web interface. If you need to change it,
          modify it here.
          Create one by using for example: echo -n yourpassword | shasum -a 256
          and use the resulting hash value as string for the option
        '';
      };

      elasticsearchHosts = mkOption {
        type = types.listOf types.string;
        default = ["http://127.0.0.1:9200"];
        description = ''
          URIs of Elasticsearch hosts.
        '';
      };

      elasticSearchDiscoveryEnabled = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable automatic detection of ES nodes. You still need to configure
          at least one in `elasticsearchHosts`.
        '';
      };

      messageJournalDir = mkOption {
        type = types.str;
        default = "${dataDir}/data/journal";
        description = ''
          The directory which will be used to store the message journal. The
          directory must be exclusively used by Graylog and must not contain any
          other files than the ones created by Graylog itself.
        '';
      };

      mongodbUri = mkOption {
        type = types.str;
        default = "mongodb://localhost/graylog";
        description = ''
          MongoDB connection string. See
          http://docs.mongodb.org/manual/reference/connection-string/ for
          details.
        '';
      };

      restListenUri = mkOption {
        type = types.str;
        default = "http://127.0.0.1:9000/api";
        description = "The URI to Graylogs API server";
      };

      webListenUri = mkOption {
        type = types.str;
        default = "http://127.0.0.1:9000";
        description = "The URI to Graylogs WebUI";
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Any other configuration options you might want to add";
      };

      javaHeap = mkOption {
        type = types.str;
        default="1g";
        description = "Max Java heap (-Xms/-Xmx)";
      };

      plugins = mkOption {
        description = "Extra graylog plugins";
        default = [ ];
        type = types.listOf types.package;
      };

    };
  };


  ###### implementation

  config = mkIf cfg.enable {

    users.extraUsers = mkIf (cfg.user == "graylog") {
      graylog = {
        uid = config.ids.uids.graylog;
        description = "Graylog server daemon user";
      };
    };

    systemd.services.graylog = with pkgs; {
      description = "Graylog Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "mongodb.service" ];
      wants = [ "mongodb.service"];
      environment = {
        JAVA_HOME = jre;
        GRAYLOG_CONF = "${confFile}";
        GRAYLOG_PID = pidFile;
        JAVA_OPTS = "-Djava.library.path=${cfg.package}/lib/sigar -Xms${cfg.javaHeap} -Xmx${cfg.javaHeap} -XX:NewRatio=1 -server -XX:+ResizeTLAB -XX:+UseConcMarkSweepGC -XX:+CMSConcurrentMTEnabled -XX:+CMSClassUnloadingEnabled -XX:+UseParNewGC -XX:-OmitStackTraceInFastThrow";
      };
      path = with pkgs; [ openjdk8 which procps which ];
      serviceConfig = {
        # Run everything except ExecStart as root since we need root permissions
        # for the preStart script
        PermissionsStartOnly = true;
        User="${cfg.user}";
        ExecStart = "${cfg.package}/bin/graylogctl run";
        TimeoutStartSec = "5m";
        ExecStop = "${cfg.package}/bin/graylogctl stop";
        TimeoutStopSec = "3m";
      };
      preStart = ''
        install -d -o ${cfg.user} -m 755 \
          ${dataDir} ${cfg.messageJournalDir} /run/graylog
        if [[ -e ${pidFile} ]]; then
          kill -0 $(< ${pidFile} ) || rm -f ${pidFile}
        fi

        rm -rf ${pluginDir} || true
        mkdir -p ${pluginDir} -m 755
        for declarativeplugin in `ls ${glPlugins}/bin/`; do
          ln -sf ${glPlugins}/bin/$declarativeplugin ${pluginDir}/$declarativeplugin
        done
        for includedplugin in `ls ${cfg.package}/plugin/`; do
          ln -s ${cfg.package}/plugin/$includedplugin ${pluginDir}/$includedplugin || true
        done
      '';
      postStart = ''
        # Wait until GL is available for use
        for count in {0..120}; do
            ${pkgs.curl}/bin/curl -s ${cfg.webListenUri} && exit
            echo "Trying to connect to ${cfg.webListenUri} for ''${count}s"
            sleep 1
        done
        echo "No connection to ${cfg.webListenUri} for 120s, giving up"
        exit 1
      '';
    };
  };
}
