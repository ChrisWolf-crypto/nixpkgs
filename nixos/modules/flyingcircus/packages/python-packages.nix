# Collection of local Python libraries, similar to upstream python-packages.nix.
# Packages defined here will be part of pkgs.python27Packages,
# pkgs.python34Packages and so on. Restrict Python compatibility through meta
# attributes if necessary.
# Python _applications_ which should get built only against a specific Python
# version are better off in all-packages.nix.
{ pkgs, stdenv, python, self, buildPythonPackage }:

rec {

  fcutil = buildPythonPackage rec {
    name = "fc-util-${version}";
    version = "1.0";
    src = ./fcutil;
    doCheck = false;
  };

  freezegun = buildPythonPackage rec {
    name = "freezegun-${version}";
    version = "0.3.6";
    src = pkgs.fetchurl {
      url = https://pypi.python.org/packages/source/f/freezegun/freezegun-0.3.6.tar.gz;
      md5 = "c321cf7392343f91e524eec0b601e8ec";
    };
    propagatedBuildInputs = with self; [ dateutil ];
    dontStrip = true;
    doCheck = false;
  };

  nagiosplugin = buildPythonPackage rec {
    name = "nagiosplugin-${version}";
    version = "1.2.4";
    src = pkgs.fetchurl {
      url = "https://pypi.python.org/packages/f0/82/4c54ab5ee763c452350d65ce9203fb33335ae5f4efbe266aaa201c9f30ad/nagiosplugin-1.2.4.tar.gz";
      md5 = "f22ee91fc89d0c442803bdf27fab8c99";
    };
    doCheck = false;  # "cannot determine number of users (who failed)"
    dontStrip = true;
  };

  pytestcatchlog = buildPythonPackage rec {
    name = "pytest-catchlog-${version}";
    version = "1.2.2";
    src = pkgs.fetchurl {
      url = https://pypi.python.org/packages/source/p/pytest-catchlog/pytest-catchlog-1.2.2.zip;
      md5 = "09d890c54c7456c818102b7ff8c182c8";
    };
    propagatedBuildInputs = with self; [ pytest ];
    dontStrip = true;
  };

  setuptools_scm = buildPythonPackage rec {
    name = "setuptools_scm-${version}";
    version = "1.11.1";
    src = pkgs.fetchurl {
      url = "https://pypi.python.org/packages/84/aa/c693b5d41da513fed3f0ee27f1bf02a303caa75bbdfa5c8cc233a1d778c4/setuptools_scm-1.11.1.tar.gz";
      md5 = "4d19b2bc9580016d991f665ac20e2e8f";
    };
    buildInputs = with self; [ pip ];
    dontStrip = true;
    preBuild = ''
      ${python.interpreter} setup.py egg_info
    '';
    meta = with pkgs.lib; {
      homepage = https://bitbucket.org/pypa/setuptools_scm/;
      description = "Handles managing your python package versions in scm metadata";
      license = licenses.mit;
      maintainers = with maintainers; [ jgeerds ];
    };
  };

}
