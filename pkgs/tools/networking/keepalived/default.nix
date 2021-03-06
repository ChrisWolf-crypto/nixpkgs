{ stdenv, fetchFromGitHub, fetchpatch, libnfnetlink, libnl, net_snmp, openssl, pkgconfig }:

stdenv.mkDerivation rec {
  name = "keepalived-${version}";
  version = "1.4.2";

  src = fetchFromGitHub {
    owner = "acassen";
    repo = "keepalived";
    rev = "v${version}";
    sha256 = "154yxs6kwpi9yc4pa45ba3z3bfwzgmmmja5nk3d9mxq6w6s1swcy";
  };

  patches = [
    (fetchpatch {
      name = "CVE-2018-19115.patch";
      url = "https://github.com/acassen/keepalived/pull/961/commits/f28015671a4b04785859d1b4b1327b367b6a10e9.patch";
      sha256 = "1jnwk7x4qdgv7fb4jzw6sihv62n8wv04myhgwm2vxn8nfkcgd1mm";
    })
  ];

  buildInputs = [
    libnfnetlink
    libnl
    net_snmp
    openssl
  ];

  nativeBuildInputs = [ pkgconfig ];

  configureFlags = [
    "--enable-sha1"
    "--enable-snmp"
 ];

  meta = with stdenv.lib; {
    homepage = http://keepalived.org;
    description = "Routing software written in C";
    license = licenses.gpl2;
    platforms = platforms.linux;
  };
}
