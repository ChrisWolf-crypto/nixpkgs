{ lib, stdenv, glibc, fetchurl, zlib, readline, libossp_uuid, openssl, makeWrapper }:

let

  common = { version, sha256, psqlSchema } @ args:
   let atLeast = lib.versionAtLeast version; in stdenv.mkDerivation (rec {
    name = "postgresql-${version}";

    src = fetchurl {
      url = "mirror://postgresql/source/v${version}/${name}.tar.bz2";
      inherit sha256;
    };

    outputs = [ "out" "doc" ];

    buildInputs =
      [ zlib readline openssl makeWrapper ]
      ++ lib.optionals (!stdenv.isDarwin) [ libossp_uuid ];

    enableParallelBuilding = true;

    makeFlags = [ "world" ];

    configureFlags = [
      "--with-openssl"
      "--sysconfdir=/etc"
    ]
      ++ lib.optional (stdenv.isDarwin)  "--with-uuid=e2fs"
      ++ lib.optional (!stdenv.isDarwin) "--with-ossp-uuid";

    patches =
      [ (if atLeast "9.4" then ./disable-resolve_symlinks-94.patch else ./disable-resolve_symlinks.patch)
        (if atLeast "9.6" then ./less-is-more-96.patch             else ./less-is-more.patch)
        (if atLeast "9.6" then ./hardcode-pgxs-path-96.patch       else ./hardcode-pgxs-path.patch)
        ./specify_pkglibdir_at_runtime.patch
      ];

    installTargets = [ "install-world" ];

    LC_ALL = "C";

    postConfigure =
      let path = if atLeast "9.6" then "src/common/config_info.c" else "src/bin/pg_config/pg_config.c"; in
        ''
          # Hardcode the path to pgxs so pg_config returns the path in $out
          substituteInPlace "${path}" --replace HARDCODED_PGXS_PATH $out/lib
        '';

    postInstall =
      ''
        # Prevent a retained dependency on gcc-wrapper.
        substituteInPlace "$out/lib/pgxs/src/Makefile.global" --replace ${stdenv.cc}/bin/ld ld
      '';

    postFixup =
      ''
        # initdb needs access to "locale" command from glibc.
        wrapProgram $out/bin/initdb --prefix PATH ":" ${glibc}/bin
      '';

    disallowedReferences = [ stdenv.cc ];

    passthru = {
      inherit readline psqlSchema;
    };

    meta = with lib; {
      homepage = http://www.postgresql.org/;
      description = "A powerful, open source object-relational database system";
      license = licenses.postgresql;
      maintainers = [ maintainers.ocharles ];
      platforms = platforms.unix;
      hydraPlatforms = platforms.linux;
    };
  });

in {

  postgresql90 = common {
    version = "9.0.23";
    psqlSchema = "9.0";
    sha256 = "1pnpni95r0ry112z6ycrqk5m6iw0vd4npg789czrl4qlr0cvxg1x";
  };

  postgresql91 = common {
    version = "9.1.20";
    psqlSchema = "9.1";
    sha256 = "0dr9hz1a0ax30f6jvnv2rck0zzxgk9x7nh4n1xgshrf26i1nq7kd";
  };

  postgresql92 = common {
    version = "9.2.15";
    psqlSchema = "9.2";
    sha256 = "0q1yahkfys78crf59avp02ibd0lp3z7h626xchyfi6cqb03livbw";
  };

  postgresql93 = common {
    version = "9.3.18";
    psqlSchema = "9.3";
    sha256 = "1q1gzxk46x65abz2jlg4fhzrvx7g8dzbhhacj3szdl1xb8md2q5d";
  };

  postgresql94 = common {
    version = "9.4.13";
    psqlSchema = "9.4";
    sha256 = "1azjqz5avp52rns6l3minbr8y97q8cs1barddawyhk8rcmfzb000";
  };

  postgresql95 = common {
    version = "9.5.8";
    psqlSchema = "9.5";
    sha256 = "00kjsfggfcii850qf2gqf9jxkaw5j7viwglmz886gwrly5l71rdd";
  };

  postgresql96 = common {
    version = "9.6.4";
    psqlSchema = "9.6";
    sha256 = "04yffrrmn85k25n3nq389aa9c1j8mkimrf889kayl772h9nv2fib";
  };

}
