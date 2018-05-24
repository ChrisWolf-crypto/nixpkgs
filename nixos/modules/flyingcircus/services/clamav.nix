# taken from nixos upstream master
{ config, lib, pkgs, ... }:
with lib;
let
  clamavUser = "clamav";
  stateDir = "/var/lib/clamav";
  runDir = "/run/clamav";
  clamavGroup = clamavUser;
  cfg = config.flyingcircus.services.clamav;
  pkg = pkgs.clamav;
  nagiosPlugins = pkgs.nagiosPluginsOfficial;

  clamdConfigFile = pkgs.writeText "clamd.conf" ''
    DatabaseDirectory ${stateDir}
    LocalSocket ${runDir}/clamd.ctl
    PidFile ${runDir}/clamd.pid
    TemporaryDirectory /tmp
    User clamav
    Foreground yes
    TCPSocket 3310
    TCPAddr localhost

    ${cfg.daemon.extraConfig}
  '';

  freshclamConfigFile = pkgs.writeText "freshclam.conf" ''
    DatabaseDirectory ${stateDir}
    Foreground yes
    Checks ${toString cfg.updater.frequency}

    ${cfg.updater.extraConfig}

    DatabaseMirror database.clamav.net
  '';
in
{
  options = {
    flyingcircus.services.clamav.daemon = {
      enable = mkEnableOption "ClamAV clamd daemon";

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra configuration for clamd. Contents will be added verbatim to the
          configuration file.
        '';
      };
    };

    flyingcircus.services.clamav.updater = {
      enable = mkEnableOption "ClamAV freshclam updater";

      frequency = mkOption {
        type = types.int;
        default = 12;
        description = ''
          Number of database checks per day.
        '';
      };

      interval = mkOption {
        type = types.str;
        default = "hourly";
        description = ''
          How often freshclam is invoked. See systemd.time(7) for more
          information about the format.
        '';
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra configuration for freshclam. Contents will be added verbatim to
          the configuration file.
        '';
      };
    };
  };

  config = mkMerge [
    (mkIf (cfg.daemon.enable or cfg.updater.enable) {
      environment.systemPackages = [ pkg ];
      users.extraUsers = singleton {
        name = clamavUser;
        uid = config.ids.uids.clamav;
        group = clamavGroup;
        description = "ClamAV daemon user";
        home = stateDir;
        isSystemUser = true;
      };

      users.extraGroups = singleton {
        name = clamavGroup;
        gid = config.ids.gids.clamav;
      };
    })

    (mkIf cfg.daemon.enable {
      environment.etc."clamav/clamd.conf".source = clamdConfigFile;

      systemd.services.clamav-daemon = mkIf cfg.daemon.enable {
        description = "ClamAV daemon (clamd)";
        after = mkIf cfg.updater.enable [ "clamav-freshclam.service" ];
        requires = mkIf cfg.updater.enable [ "clamav-freshclam.service" ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ clamdConfigFile ];

        preStart = ''
          install -d -o ${clamavUser} -g ${clamavGroup} -m 0755 \
            ${runDir} ${stateDir}
        '';

        serviceConfig = {
          ExecStart = "${pkg}/bin/clamd";
          ExecReload = "${pkgs.coreutils}/bin/kill -USR2 $MAINPID";
        };
      };

      flyingcircus.services.sensu-client.checks = {
        clamav-daemon = {
          notification = "clamd process running";
          command = "${nagiosPlugins}/bin/check_clamd -v";
        };
      };
    })

    (mkIf cfg.updater.enable {
      environment.etc."clamav/freshclam.conf".source = freshclamConfigFile;

      systemd.timers.clamav-freshclam = mkIf cfg.updater.enable {
        description = "Timer for ClamAV virus database updater (freshclam)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.updater.interval;
          Unit = "clamav-freshclam.service";
        };
      };

      systemd.services.clamav-freshclam = mkIf cfg.updater.enable {
        description = "ClamAV virus database updater (freshclam)";
        restartTriggers = [ freshclamConfigFile ];

        requires = [ "network.target" ];
        after = [ "network.target" ];

        preStart = ''
          install -d -o ${clamavUser} -g ${clamavGroup} -m 0755 \
            ${runDir} ${stateDir}
        '';

        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkg}/bin/freshclam";
          PrivateTmp = "yes";
          # We monitor systemd process status for alerting, but this really
          # isn't critical to wake up people. We'll catch errors when the
          # file age check for the database update goes critical.
          # The list is taken from the freshclam manpage.
          SuccessExitStatus = [ 40 50 51 52 53 54 55 56 57 58 59 60 61 62 ];
        };
      };

      flyingcircus.services.sensu-client.checks = {
        clamav-updater = {
          notification = "ClamAV virus database up-to-date";
          command = ''
            ${nagiosPlugins}/bin/check_file_age -w 86400 -c 172800 \
              ${stateDir}/mirrors.dat
          '';
        };
      };
    })
  ];
}
