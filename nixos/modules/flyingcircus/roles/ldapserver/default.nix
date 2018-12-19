# NOTES:
# * monitoring?
# * metrics

{ config, lib, pkgs, ... }:
with lib;
let
  fclib = import ../../lib;

  cfg = config.flyingcircus.roles.ldap;
  dataDir = config.services.openldap.dataDir;

  suffixFile = "/etc/local/ldap/suffix";
  suffix = fclib.coalesce [
     cfg.suffix
     (removeSuffix "\n" (fclib.configFromFile suffixFile ""))
  ];

  o = builtins.readFile
    (pkgs.runCommand
      "ldapserver-o" { preferLocalBuild = true; }
      "echo -n '${suffix}' | sed -e 's/dc=\\([^,]*\\),.*/\\1/' > $out");

  readerPassword = fclib.servicePassword {
    inherit pkgs;
    file = "/etc/local/ldap/password.reader";
    mode = "0640";  # Only set once via bootstrapLdiff
    token = config.networking.hostName;
  };
  managerPassword = fclib.servicePassword {
    inherit pkgs;
    file = "/etc/local/ldap/password.manager";
    token = config.networking.hostName;
  };

  bootstrapLdiff = pkgs.writeText "bootstrap.ldiff" ''
    dn: ${suffix}
    objectClass: dcObject
    objectClass: organization
    dc: ${o}
    o: ${o}

    dn: cn=Manager,${suffix}
    objectClass: organizationalRole
    cn: Manager
    description: root account

    dn: cn=Reader,${suffix}
    objectClass: organizationalRole
    objectClass: simpleSecurityObject
    cn: Reader
    description: low-security account for read-only access
  '';

  dbConfig = builtins.readFile ./DB_CONFIG;

  extraLdapConf = fclib.configFromFile "/etc/local/ldap/slapd.conf" "";
  ldapConf = ''
    # ACL for auth and monitoring access
    access to dn.base="" by * read
    access to dn.base="cn=Subschema" by * read
    access to attrs="userPassword"
        by anonymous auth
        by self write
        by * none
    access to *
        by self write
        by users read
        by anonymous auth

    # Basic configuration

    include ${pkgs.openldap}/etc/openldap/schema/core.schema
    include ${pkgs.openldap}/etc/openldap/schema/cosine.schema
    include ${pkgs.openldap}/etc/openldap/schema/inetorgperson.schema
    include ${pkgs.openldap}/etc/openldap/schema/nis.schema

    idletimeout 600
    timelimit 60
    loglevel  none

    # Load dynamic backend modules:
    modulepath  ${pkgs.openldap}/lib
    moduleload  back_monitor.so

    TLSCiphersuite SECURE256:-VERS-SSL3.0:+VERS-TLS1.2:+VERS-TLS1.0:+VERS-TLS1.1

    # backend configuration
    database  hdb
    suffix    "${suffix}"
    checkpoint  1024  10
    cachesize 1200
    idlcachesize  3600
    rootdn    "cn=Manager,${suffix}"
    include /run/slapd/managerPassword

    # The database directory MUST exist prior to running slapd AND
    # should only be accessible by the slapd and slap tools.
    # Mode 700 recommended.
    directory ${dataDir}

    # Standard indices to maintain
    index cn pres,eq,sub
    index mail pres,eq,sub
    index memberUid pres,eq
    index objectClass pres,eq
    index uid pres,eq,sub
    index uidNumber pres,eq
    index uniqueMember pres,eq

    # ldap monitor configuration
    database  monitor
    access to dn.subtree="cn=Monitor"
            by dn.exact="cn=Manager,${suffix}" read
            by dn.exact="cn=Reader,${suffix}" read
            by * none

    ${extraLdapConf}
  '';

  parseListenUrls = pkgs.writeScript "parseListenUrls" ''
    #!${pkgs.gawk}/bin/awk -f
    # This script gets all ldap{,s,i} URLs from a configuration file and prints the
    # valid ones. This is needed to make slapd's listen ports configurable but
    # prevent privilege escalation.

    BEGIN {
      FS="\n"
    }

    /^\s*#/ { next }

    /./ {
      if (match($0, /^ldap[is]?:\/\/[[:alnum:]/?:;@&=+,_.!~*()%\[\]-]+$/)) {
        print $0
      } else {
        print "error: line contains invalid characters: " $0 > "/dev/stderr"
        exit 1
      }
    }
  '';
  listenUrlsPath = "/etc/local/ldap/listen_urls";
  listenUrls =
    let contents = fclib.configFromFile listenUrlsPath "";
    in
    [ "ldap://localhost"
      "ldapi://%2fvar%2frun%2fslapd%2fslapd.sock" ]
    ++
    (map
      (addr: "ldap://${addr}")
      (fclib.listenAddressesQuotedV6 config "ethsrv"))
    ++
    (splitString "\n"
      (removeSuffix "\n"
        (builtins.readFile
          (pkgs.runCommand "parsedListenUrls" { preferLocalBuild = true; } ''
            cat << __EOF__  | ${parseListenUrls} > $out
            ${contents}
            __EOF__
          ''))));
in
{

  options = {
    flyingcircus.roles.ldap = {
      enable = lib.mkEnableOption "LDAPServer role";

      suffix = mkOption {
        type = types.nullOr types.string;
        default = null;
        description = "Suffix override (mainly for testing).";
      };
    };
  };

  config = mkMerge [
    (mkIf (cfg.enable && suffix != "") {
      services.openldap = {
        enable = true;
        extraConfig = ldapConf;
        urlList = listenUrls;
      };

      systemd.services.openldap.preStart =
        let
          cfg = config.services.openldap;
          openldap = pkgs.openldap.out;
        in ''
          set -e

          ${readerPassword.generate}

          ${managerPassword.generate}
          ( echo -n 'rootpw '
            ${pkgs.openldap}/bin/slappasswd -s $(<${managerPassword.file})
          ) > /run/slapd/managerPassword

          mkdir -p "${cfg.dataDir}"
          cat <<EOF > ${dataDir}/DB_CONFIG
          ${dbConfig}
          EOF

          if ! ${openldap}/bin/slapcat $openldap_config_opts | fgrep "${suffix}" >/dev/null; then
              ( cat ${bootstrapLdiff}
                echo -n 'userPassword: '
                ${pkgs.openldap}/bin/slappasswd -s $(<${readerPassword.file})
              ) | ${openldap}/bin/slapadd $openldap_config_opts
          fi

          ${openldap}/bin/slapindex $openldap_config_opts
          ${openldap}/bin/slaptest $openldap_config_opts
          chown -R "${cfg.user}:${cfg.group}" "${cfg.dataDir}"
        '';

      flyingcircus.services.sensu-client.checks =
        let
          fqdn = "${config.networking.hostName}.${config.networking.domain}";
          ldapCheck = ''
            check_ldap -3 -H ${fqdn} -w 2 -c 4 -b '${suffix}' \
              -D 'cn=Reader,${suffix}' \
              -P $(<${readerPassword.file}) \
          '';
        in {
          slapd_ipv4 = {
            command = "${ldapCheck} -4";
            notification = "slapd IPv4 alive";
          };
          slapd_ipv6 = {
            command = "${ldapCheck} -6";
            notification = "slapd IPv6 alive";
          };
        };
    })
    (mkIf cfg.enable {

      environment.etc = {
        "local/ldap/README.txt".text = ''
          The LDAPServer role is enabled on this machine.
          ${optionalString (suffix == "") ''
          OpenLDAP has not been started, yet. Configure the global suffix in the
          ${builtins.baseNameOf suffixFile} file.''}
          ${optionalString (suffix != "") ''
          OpenLDAP is running with the suffix `${suffix}`.''}

          Use the file `${builtins.baseNameOf listenUrlsPath}` to configure which ports OpenLDAP opens for
          ldap, ldaps, or ldapi. Note, that the firewall is *not* automatically configured.

          Put additional configuration for slapd into `slapd.conf` (like SSL configuration).
        '';
      };

      system.activationScripts.fcio-ldap-init =
        stringAfter [ "users" "groups" ] ''
          install -d /etc/local/ldap
          chown openldap:service /etc/local/ldap
          chmod 2775 /etc/local/ldap
          test -e ${listenUrlsPath} || (
            cat <<__EOF__ >${listenUrlsPath}
          # LDAP listen urls, one per line
          # The default URLs (srv network) are always added to ensure that monitoring
          # checks don't break.
          # Please note that you should not duplicate the default URLs since slapd will
          # refuse to start if given duplicated addresses.
          # Example:
          # ldap://ldap.domain.tld
          __EOF__
            chmod 664 ${listenUrlsPath}
          )
        '';
    })
  ];
}
