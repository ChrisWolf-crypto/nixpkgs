{ pkgs ? import <nixpkgs> { }
, stdenv ? pkgs.stdenv
, lib ? pkgs.lib
, fetchurl ? pkgs.fetchurl
}:


stdenv.mkDerivation rec {
  name = "mailx-${version}";
  version = "12.5";

  src = fetchurl {
    url = "http://ftp.debian.org/debian/pool/main/h/heirloom-mailx/heirloom-mailx_${version}.orig.tar.gz";
    md5 = "29a6033ef1412824d02eb9d9213cb1f2";
  };

  propagatedBuildInputs = [
    pkgs.openssl
  ];

  buildInputs = [
  ];

  preBuild = ''
    makeFlagsArray=(
    MANDIR=$out/share/man1
    PREFIX=$out
    SENDMAIL=/run/current-system/sw/bin/sendmail
    SYSCONFDIR=$out/etc
    UCBINSTALL=${pkgs.coreutils}/bin/install
    BINDIR=$out/bin
  )
  '';

  meta = {
    homepage = http://heirloom.sourceforge.net;
    description = ''
      Mailx is an intelligent mail processing system, which has
      a command syntax reminiscent of ed(1) with lines replaced by messages.
    '';
  };
}
