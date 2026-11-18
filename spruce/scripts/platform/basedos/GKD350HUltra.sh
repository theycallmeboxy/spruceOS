#!/bin/sh
# GKD 350H Ultra on BasedOS. dArkMossCommon.sh carries what this board shares with the dArkMoss
# RK3566 units (input discovery, the MainUI alias, backlight, ALSA volume, battery, RetroArch
# setup). BasedOS is BusyBox init with no systemd, NetworkManager or udev, so the functions below
# replace dArkMossCommon's systemd and nmcli ones. Bluetooth is not brought up on BasedOS yet.

. "/mnt/SDCARD/spruce/scripts/platform/darkmoss/dArkMossCommon.sh"
. "/mnt/SDCARD/spruce/scripts/platform/utils/baseos_session_shield.sh"
. "/mnt/SDCARD/spruce/scripts/platform/utils/spruce_system_user.sh"

device_init() {
    resolve_pad_node
    log_message "$PLATFORM: card is ${SD_DEV:-<unresolved>} at $SD_MOUNTPOINT ($(sed -n 's/^BASEOS_BUILD=//p' /etc/baseos-release 2>/dev/null))"
    resolve_key_event_node
    setup_mainui_alias
    if [ ! -f "$SYSTEM_JSON" ] && [ -f "$SYSTEM_JSON_DEFAULT" ]; then
        cp "$SYSTEM_JSON_DEFAULT" "$SYSTEM_JSON"
    fi
    set_backlight "$(get_backlight_level)"
    # dArkMoss writes ~/.asoundrc through bluetooth.sh boot; BasedOS has no Bluetooth yet,
    # so write it here (runtime.sh removed the old one before device_init).
    /mnt/SDCARD/spruce/scripts/asound-setup.sh "$HOME"
    # As on the H700 BaseOS: the spruce login for dropbear and Samba, and keep BasedOS's
    # respawned session from remounting the card while save_poweroff shuts down.
    add_spruce_system_user
    shield_baseos_session /sbin/frontend-session
}

  ###################
#####   AUDIO   #####
  ###################

# dArkMossCommon's file with its softvol "Master" left out: the DAC's "Digital" control is the
# volume here (VOLUME_CONTROL), so a software stage in front of it would only cost headroom.
# spruce_speaker is the name asound-setup.sh routes to; dmix still lets sounds overlap.
device_write_default_asound_rc() {
    cat > "$ASOUND_CONF" <<ASOUND
pcm.spruce_speaker {
    type        plug
    slave.pcm   "ddmix"
}

ctl.!default {
    type        hw
    card        0
}

pcm.ddmix {
    ipc_key     1024
    type        dmix
    slave {
        pcm         "hw:0,0"
        period_time 0
        period_size 1024
        buffer_size 4096
        rate        44100
    }
}
ASOUND
}

# spruce's own dropbear owns port 22, as on the H700 BaseOS: with SSH on it stops BasedOS's
# sshd and starts its own, with SSH off it stops both (sshFunctions.sh). dArkMossCommon names
# systemd's "ssh" unit, and BasedOS has no systemctl, so this goes back to the common64bit name.
get_ssh_service_name() {
    echo "dropbearmulti"
}

  ##################
#####   WIFI   #####
  ##################

# BasedOS associates and runs DHCP itself before spruce starts (wpa_supplicant on wlan0 with
# /data/wpa_supplicant.conf, udhcpc). A second supplicant on wlan0 would fight it, so spruce
# leaves Wi-Fi to the base for now.
device_manages_own_wifi() {
    return 0
}

# The radio stays BasedOS's; spruce's Wi-Fi switch takes the link up or down.
device_wifi_power_on() {
    ip link set wlan0 up 2>/dev/null
}

device_wifi_power_off() {
    ip link set wlan0 down 2>/dev/null
}

device_start_dhcp_client() {
    :
}

device_stop_dhcp_client() {
    :
}

# Saved to the card like on every other device (so it follows the card), but BasedOS still
# associates from its own /data/wpa_supplicant.conf, so the new network isn't joined yet.
device_wifi_connect() {
    wpa_conf_save_network "$1" "$2"
    log_message "$PLATFORM: saved $1 to the card; BasedOS joins networks from /data/wpa_supplicant.conf"
    return 1
}

  #######################
#####   BLUETOOTH   #####
  #######################

device_bluetooth_up() {
    log_message "$PLATFORM: Bluetooth is not brought up on BasedOS yet"
    return 1
}

device_bluetooth_down() {
    :
}

  ###################
#####   SLEEP   #####
  ###################

# The kernel offers deep sleep (mem_sleep = s2idle [deep]); no systemd to ask. BasedOS's
# basedos-suspend does it and then its own wake fixes (the DAC's volume, which the stock kernel
# loses), as dArkMoss's system-sleep hook does behind systemd; it returns after resume. A BasedOS
# without it gets the plain write. The RTC (hym8563, on always-on GPIO0) wakes the board.
trigger_device_sleep() {
    if [ -x /usr/sbin/basedos-suspend ]; then
        /usr/sbin/basedos-suspend || { log_message "$PLATFORM: the kernel refused to suspend"; return 1; }
        return 0
    fi
    sync
    if ! echo mem > /sys/power/state 2>/dev/null; then
        log_message "$PLATFORM: the kernel refused to suspend"
        return 1
    fi
}

# Idle shutdown watches the pad's js node (js0 under event3), as on the H700 BaseOS.
set_event_arg_for_idlemon() {
    set_idlemon_to_pad
}


  ###################
#####   POWER   #####
  ###################

# BusyBox init: its poweroff and reboot run BasedOS's rcK. The card itself is unmounted by
# save_poweroff's strict stage 2 first (see below), as on the H700 BaseOS.
device_run_reboot_cmd() {
    sync
    reboot
}

run_poweroff_cmd() {
    sync
    poweroff
}

device_prepare_for_poweroff() {
    :
}

# BasedOS's rcK runs before BusyBox init signals anything, so the frontend still holds the card
# then: spruce unmounts it itself (stage 2) and, being strict, also keeps its own respawned
# session from starting again. Same as the H700 BaseOS (AnbernicXXCommon.sh).
device_system_handles_sdcard_unmount() {
    return 1
}

device_needs_strict_unmount() {
    return 0
}

# Same values as retroarch-GKD350HUltra.cfg.bak ships (linuxraw numbering, see the gkd_atom_joypad
# autoconfig): hotkey Select 8, fast forward R2 7, slow motion L2 6, state slot -/+ on Left/Right
# 14/15. dArkMossCommon's set puts fast forward on 10, which is the Menu button here.
set_default_ra_hotkeys() {
    RA_FILE="$(platform_path "/mnt/SDCARD/Saves/ra-configs/retroarch-%s.cfg")"

    log_message "Resetting RetroArch hotkeys to Spruce defaults."

    update_ra_config_file_with_new_setting "$RA_FILE" \
        "input_enable_hotkey_btn = \"8\"" \
        "input_exit_emulator_btn = \"0\"" \
        "input_fps_toggle_btn = \"2\"" \
        "input_load_state_btn = \"4\"" \
        "input_save_state_btn = \"5\"" \
        "input_menu_toggle = \"f1\"" \
        "input_menu_toggle_btn = \"3\"" \
        "input_quit_gamepad_combo = \"0\"" \
        "input_toggle_fast_forward_btn = \"7\"" \
        "input_screenshot_btn = \"1\"" \
        "input_shader_toggle_btn = \"nul\"" \
        "input_state_slot_decrease_btn = \"14\"" \
        "input_state_slot_increase_btn = \"15\"" \
        "input_toggle_slowmotion_btn = \"6\""
}

  ######################
#####   FIRMWARE   #####
  ######################

# BasedOS updates (.bosupd) are not applied by spruce yet.
check_if_fw_needs_update() {
    echo "false"
}

local_fw_update_file() {
    return 1
}

device_get_fw_version() {
    sed -n 's/^BASEOS_VERSION=//p' /etc/baseos-release 2>/dev/null
}
