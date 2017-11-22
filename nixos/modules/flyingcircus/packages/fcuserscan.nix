{ pkgs, stdenv, fetchFromGitHub, rustPlatform }:

with rustPlatform;

buildRustPackage rec {
  name = "fc-userscan-${version}";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "userscan";
    rev = version;
    sha256 = "0l3xka41s83y7411nhfqbaxxc3z576sg184w5kqfmh3wfnl62p41";
  };

  cargoDepsSha256 = "17s38fsk9hynv3qx0lkz4lyq233d4bpsjgh9cbylm3q14m4s7mxx";
  nativeBuildInputs = with pkgs; [ git docutils ];
  propagatedBuildInputs = with pkgs; [ lzo ];
  doCheck = true;

  postBuild = ''
    substituteAll $src/userscan.1.rst $TMP/userscan.1.rst
    rst2man.py $TMP/userscan.1.rst > $TMP/userscan.1
  '';
  postInstall = ''
    install -D $TMP/userscan.1 $out/share/man/man1/fc-userscan.1
  '';

  meta = with stdenv.lib; {
    description = "Scan and register Nix store references from arbitrary files";
    homepage = https://github.com/flyingcircusio/userscan;
    license = with licenses; [ bsd3 ];
    platforms = platforms.all;
  };
}
