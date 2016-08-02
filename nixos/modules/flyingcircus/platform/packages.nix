{ pkgs, ... }:

{
  config = {

    environment.systemPackages = with pkgs; [
        apacheHttpd
        atop
        bc
        bind
        bundler
        curl
        cyrus_sasl
        db
        dstat
        fcmaintenance
        file
        fio
        gcc
        gdbm
        git
        gnupg
        go
        gptfdisk
        graphviz
        imagemagick
        iotop
        kerberos
        libjpeg
        libmemcached
        libxml2
        libxslt
        links
        lsof
        lynx
        mercurial
        mmv
        nano
        nc6
        ncdu
        netcat
        ngrep
        nmap
        nodejs
        openldap
        openssl
        php
        postgresql
        protobuf
        psmisc
        pv
        python2Full
        pythonPackages.virtualenv
        python34
        screen
        strace
        subversion
        sysstat
        tcpdump
        telnet
        traceroute
        tree
        unzip
        vim
        xfsprogs
        zlib
    ];

    nixpkgs.config.packageOverrides = pkgs: {
      linux_4_3 = pkgs.linux_4_3.override {
        extraConfig = ''
          DEBUG_INFO y
          IP_MULTIPLE_TABLES y
          IPV6_MULTIPLE_TABLES y
          LATENCYTOP y
          SCHEDSTATS y
        '';
      };

      nagiosPluginsOfficial =
        pkgs.nagiosPluginsOfficial.overrideDerivation (oldAttrs: {
          buildInputs = [ pkgs.openssh pkgs.openssl ];
          preConfigure= "
            configureFlagsArray=(
              --with-openssl=${pkgs.openssl}
              --with-ping-command='/var/setuid-wrappers/ping -n -w %d -c %d %s'
              --with-ping6-command='/var/setuid-wrappers/ping6 -n -w %d -c %d %s'
            )
          ";
        });
    };

  };
}
