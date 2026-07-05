{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/packages.nix
  ];

  networking.hostName = "nixos";

  # Current machine's laptop/power behavior.
  services.tlp.enable = true;
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    # Let logind own lid sleep. Niri should not also trigger a sleep command on
    # lid-close, otherwise resume can immediately race into a second suspend.
    HandleLidSwitch = "suspend-then-hibernate";
  };

  # Keep suspend-then-hibernate, but avoid firmware/platform S4 on this laptop:
  # write the hibernation image, then fully power off. Resume still restores from
  # swap on the next power button/lid boot, but skips a buggy ACPI S4 wake path.
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "45m";
    HibernateMode = "shutdown";
  };

  # Tell the kernel where to resume from hibernation.
  boot.resumeDevice = "/dev/disk/by-uuid/48995cae-2c41-4c73-b12c-16125c0c1c4d";

  # The Realtek 8922AE Wi-Fi path logs ACPI/rtw89 errors around suspend on this
  # machine. Disable the fragile PCIe low-power handshakes and reload the driver
  # around sleep so it cannot wedge resume or prevent s2idle from reaching a sane
  # state.
  boot.extraModprobeConfig = ''
    options rtw89_pci disable_aspm_l1ss=y disable_clkreq=y
  '';

  environment.etc."systemd/system-sleep/rtw89-reset".source = pkgs.writeShellScript "rtw89-reset" ''
    case "$1" in
      pre)
        ${pkgs.kmod}/bin/modprobe -r rtw89_8922ae rtw89_pci rtw89_core 2>/dev/null || true
        ;;
      post)
        ${pkgs.kmod}/bin/modprobe rtw89_8922ae 2>/dev/null || true
        ;;
    esac
  '';
}
