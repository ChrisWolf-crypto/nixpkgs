{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.rabbitmq;

  plugins = pkgs.stdenv.mkDerivation {
    name = "rabbitmq_server_plugins";
    builder = builtins.toFile "makePlugins.sh" ''
      source $stdenv/setup
      mkdir -p $out
      ln -s $server/plugins/* $out
      for package in $packages
      do
        ln -s $package/* $out
      done
    '';
    server = cfg.package;
    packages = cfg.pluginPackages;
    preferLocalBuild = true;
    allowSubstitutes = false;
  };

in {
  options = {
    services.rabbitmq.pluginPackages = mkOption {
      default = [];
      type = types.listOf types.package;
      description = "Packages to add as plugin.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.rabbitmq = {
      environment.RABBITMQ_PLUGINS_DIR = plugins;
      serviceConfig = {
        LimitNOFILE = 65536;
        Restart = "always";
      };
    };
    systemd.services.rabbitmq.path = [ pkgs.glibc ];
  };
}
