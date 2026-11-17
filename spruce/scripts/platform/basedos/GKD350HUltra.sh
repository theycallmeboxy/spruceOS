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

# The kernel offers deep sleep (mem_sleep = s2idle [deep]); no systemd to ask. The write returns
# after resume. The RTC (hym8563, on always-on GPIO0) wakes the board from deep sleep.
trigger_device_sleep() {
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

  #################
#####   CPU   #####
  #################

# cpu_control_functions.sh's cores_online with two changes:
# - the A72s go to their lowest clock before they are parked. The clusters share the CCI
#   (rockchip,opp-shared-cci in the cpu OPP tables), and the driver holds the A53s' minimum at the
#   CCI level the A72s last asked for: parked from 2016 MHz they left the A53s stuck at 1800
#   (Smart's top) until a reboot; parked from 408 MHz the A53s scale from 408 again (both on the
#   unit, 2026-11-16).
# - the wanted cores come up before the others go down. spruce's single walk over cpu0-7 would
#   reach cpu3 as the last core online when switching from the A53s to the A72s, and the kernel
#   won't park the last core.
cores_online() {
    [ -z "$1" ] && return  # skip empty call
    core_string="${1:-0123}"

    # TODO why silent?
    # Silently fall back on invalid input
    case "$core_string" in (*[!0-7]*) core_string=0123 ;; esac

    case "$core_string" in
        (*[4-7]*) ;;
        (*) [ "$2" = "--no-offline" ] || gkd350hultra_a72_to_lowest_clock ;;
    esac

    for want in 1 0; do
        for cpu_path in /sys/devices/system/cpu/cpu[0-7]*; do
            [ -e "$cpu_path/online" ] || continue

            cpu="${cpu_path##*cpu}"
            case "$core_string" in
                (*"$cpu"*) val=1 ;;
                (*)        val=0 ;;
            esac
            [ "$val" = "$want" ] || continue

            # Offlining is a slow hotplug; a caller may leave it to the next call.
            [ "$val" = 0 ] && [ "$2" = "--no-offline" ] && continue

            # Re-locking a core already in that state only costs forks.
            read -r cur < "$cpu_path/online" 2>/dev/null && [ "$cur" = "$val" ] && continue

            # lock requested cpus online and all others offline
            chmod a+w "$cpu_path/online" 2>/dev/null
            echo "$val" >"$cpu_path/online" 2>/dev/null
            chmod a-w "$cpu_path/online" 2>/dev/null
        done
    done
    log_message "Setting cores online: ${core_string}"
}

# The A72 policy to its lowest step while any A72 is still online (see cores_online). The mode
# that brings them back writes its own governor and range.
gkd350hultra_a72_to_lowest_clock() {
    grep -q 1 /sys/devices/system/cpu/cpu[4-7]/online 2>/dev/null || return 0
    _lo="$(cat "$CPU_4_DIR/cpuinfo_min_freq" 2>/dev/null)"
    [ -n "$_lo" ] || return 0
    for _f in scaling_min_freq scaling_max_freq; do
        chmod a+w "$CPU_4_DIR/$_f" 2>/dev/null
        echo "$_lo" > "$CPU_4_DIR/$_f" 2>/dev/null
    done
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
