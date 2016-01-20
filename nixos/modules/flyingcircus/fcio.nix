{ config, lib, pkgs, ... }:
# Configuration for running on FCIO infrastructure (i.e. not on vagrant)

with lib;

{
  imports = [
      ../profiles/qemu-guest.nix
      ./base.nix
  ];

  boot.blacklistedKernelModules = [ "bochs_drm" ];
  boot.initrd.supportedFilesystems = [ "xfs" ];
  boot.kernelParams = [ "panic=1" "boot.panic_on_fail" "console=ttyS0" "nosetmode" ];
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.fsIdentifier = "provided";
  boot.loader.grub.gfxmodeBios = "text";
  boot.loader.grub.timeout = 3;
  boot.loader.grub.version = 2;
  boot.supportedFilesystems = [ "xfs" ];
  boot.vesa = false;

  networking.useDHCP = true;

  services.openssh.enable = true;
  services.openssh.permitRootLogin = "without-password";


  fileSystems."/".device = "/dev/disk/by-label/root";
  fileSystems."/tmp".device = "/dev/disk/by-label/tmp";

  swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];

  users.extraUsers.root.initialHashedPassword = "";

  networking.firewall.allowPing = true;
  networking.firewall.rejectPackets = true;

}
