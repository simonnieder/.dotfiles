{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common.nix
    ../../modules/packages.nix
  ];

  networking.hostName = "nixos";

  # Current machine's laptop/power behavior.
  services.tlp = {
    enable = true;
    settings = {
      PLATFORM_PROFILE_ON_AC = "balanced";
      PLATFORM_PROFILE_ON_BAT = "balanced";
      PLATFORM_PROFILE_ON_SAV = "balanced";
      STOP_CHARGE_THRESH_BAT0 = 1;
    };
  };
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    # Let logind own lid sleep. The compositor must not trigger another sleep
    # on lid-close, or resume can immediately race into a second suspend.
    HandleLidSwitch = "suspend-then-hibernate";
  };

  # A full shutdown makes this firmware alternate between two E820 memory maps.
  # Linux then rejects the hibernation image as unsafe on the next cold boot.
  # Keep the firmware in ACPI S4 so the memory map remains stable for resume.
  systemd.sleep.settings.Sleep = {
    HibernateDelaySec = "20m";
    HibernateMode = "platform";
  };

  # Tell the kernel where to resume from hibernation.
  boot.resumeDevice = "/dev/disk/by-uuid/48995cae-2c41-4c73-b12c-16125c0c1c4d";

  # The Realtek 8922AE Wi-Fi path logs ACPI/rtw89 errors around suspend and
  # loses beacons while connected. Disable its fragile PCIe handshakes and Wi-Fi
  # power saving, then reload the driver around sleep so it cannot wedge resume
  # or repeatedly drop the connection.
  boot.extraModprobeConfig = ''
    options rtw89_core disable_ps_mode=y
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
