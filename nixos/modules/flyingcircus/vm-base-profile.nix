{ config, lib, pkgs, ... }:

with lib;

let
    flavor_files =
        if builtins.pathExists (builtins.toPath /etc/nixos/vagrant.nix)
        then [./vagrant.nix]
        else [./fcio.nix];

    enc =
        if builtins.pathExists (builtins.toPath /etc/nixos/enc.json)
        then builtins.fromJSON /etc/nixos/enc.json
        else {};
in
{
  imports =
    flavor_files ++
    [./roles/default.nix];

  environment.noXlibs = true;
  sound.enable = false;

  environment.systemPackages = [
      pkgs.cyrus_sasl
      pkgs.db
      pkgs.dstat
      pkgs.gcc
      pkgs.git
      pkgs.libxml2
      pkgs.libxslt
      pkgs.mercurial
      pkgs.openldap
      pkgs.openssl
      pkgs.python27Full
      pkgs.python27Packages.virtualenv
      pkgs.vim
      pkgs.zlib
  ];

  environment.pathsToLink = [ "/include" ];
  environment.shellInit = ''
   # help pip to find libz.so when building lxml
   export LIBRARY_PATH=/var/run/current-system/sw/lib
   # help dynamic loading like python-magic to find it's libraries
   export LD_LIBRARY_PATH=$LIBRARY_PATH
   # ditto for header files, e.g. sqlite
   export C_INCLUDE_PATH=/var/run/current-system/sw/include:/var/run/current-system/sw/include/sasl
  '';


  security.sudo.extraConfig =
      ''
      Defaults lecture = never
      root   ALL=(ALL) SETENV: ALL
      %wheel ALL=(ALL) NOPASSWD: ALL, SETENV: ALL
      '';
}
