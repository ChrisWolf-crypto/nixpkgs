{ pkgs }:

rec {

  boost159 = pkgs.callPackage ./boost/1.59.nix { };
  boost160 = pkgs.callPackage ./boost/1.60.nix { };

  cron = pkgs.callPackage ./cron.nix { };
  collectd = pkgs.callPackage ./collectd.nix { };

  dnsmasq = pkgs.callPackage ./dnsmasq.nix { };

  easyrsa3 = pkgs.callPackage ./easyrsa { openssl = pkgs.openssl_1_0_2; };

  fcmaintenance = pkgs.callPackage ./fcmaintenance { };
  fcmanage = pkgs.callPackage ./fcmanage { };
  fcsensuplugins = pkgs.callPackage ./fcsensuplugins { };

  innotop = pkgs.callPackage ./percona/innotop.nix { };

  linux_4_4 = pkgs.callPackage ./kernel/linux-4.4.nix {
    kernelPatches = [ pkgs.kernelPatches.bridge_stp_helper ];
  };
  linuxPackages_4_4 = pkgs.recurseIntoAttrs
    (pkgs.linuxPackagesFor linux_4_4 linuxPackages_4_4);

  mc = pkgs.callPackage ./mc.nix { };
  mailx = pkgs.callPackage ./mailx.nix { };
  mongodb = pkgs.callPackage ./mongodb { sasl = pkgs.cyrus_sasl; };

  nagiosPluginsOfficial = pkgs.callPackage ./nagios-plugins-official-2.x.nix {};

  osm2pgsql = pkgs.callPackage ./osm2pgsql.nix { };

  percona = percona57;
  percona57 = pkgs.callPackage ./percona/5.7.nix { boost = boost159; };
  percona56 = pkgs.callPackage ./percona/5.6.nix { boost = boost159; };
  postfix = pkgs.callPackage ./postfix/3.0.nix { };
  powerdns = pkgs.callPackage ./powerdns.nix { };

  qemu = pkgs.callPackage ./qemu-2.5.nix {
    inherit (pkgs.darwin.apple_sdk.frameworks) CoreServices Cocoa;
    x86Only = true;
  };
  qpress = pkgs.callPackage ./percona/qpress.nix { };

  rabbitmq_delayed_message_exchange =
    pkgs.callPackage ./rabbitmq_delayed_message_exchange.nix { };

  sensu = pkgs.callPackage ./sensu { };

  uchiwa = pkgs.callPackage ./uchiwa { };

  varnish =
    (pkgs.callPackage ../../../../pkgs/servers/varnish { }).overrideDerivation
    (old: {
      buildFlags = "localstatedir=/var/spool";
    });
  vulnix = pkgs.callPackage ./vulnix { };

  xtrabackup = pkgs.callPackage ./percona/xtrabackup.nix { };

}
