{ stdenv, fetchurl, pkgconfig, gnused_422, perl, python2, zip, libffi, readline, icu, zlib, nspr
, libobjc }:

stdenv.mkDerivation rec {
  version = "38.8.0";
  name = "spidermonkey-${version}";

  src = fetchurl {
    url = "mirror://mozilla/firefox/releases/${version}esr/source/firefox-${version}esr.source.tar.bz2";
    sha256 = "10lrync6cxnjlnadc0j3vg8r2dq9b3wwanw8qj1h6ncxwb7asxcl";
  };

  buildInputs = [ libffi readline icu zlib nspr ]
               ++ stdenv.lib.optional stdenv.isDarwin libobjc;
  nativeBuildInputs = [ pkgconfig perl python2 zip gnused_422 ];

  postUnpack = "sourceRoot=\${sourceRoot}/js/src";

  preConfigure = ''
    export CXXFLAGS="-fpermissive"
    export LIBXUL_DIST=$out
    export PYTHON="${python2.interpreter}"
  '';

  configureFlags = [
    "--enable-threadsafe"
    "--with-system-ffi"
    "--with-system-nspr"
    "--with-system-zlib"
    "--with-system-icu"
    "--enable-readline"

    # enabling these because they're wanted by 0ad. They may or may
    # not be good defaults for other uses.
    "--enable-gcgenerational"
    "--enable-shared-js"
  ];

  # This addresses some build system bug. It's quite likely to be safe
  # to re-enable parallel builds if the source revision changes.
  enableParallelBuilding = true;

  postFixup = ''
    # The headers are symlinks to a directory that doesn't get put
    # into $out, so they end up broken. Fix that by just resolving the
    # symlinks.
    for i in $(find $out -type l); do
      cp --remove-destination "$(readlink "$i")" "$i";
    done
  '';

  meta = with stdenv.lib; {
    description = "Mozilla's JavaScript engine written in C/C++";
    homepage = https://developer.mozilla.org/en/SpiderMonkey;
    # TODO: MPL/GPL/LGPL tri-license.

    maintainers = [ maintainers.abbradar ];
    platforms = platforms.unix;
  };
}
