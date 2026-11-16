#!/bin/sh
# GKD 350H Ultra on BasedOS. dArkMossCommon.sh carries what this board shares with the dArkMoss
# RK3566 units (input discovery, the MainUI alias, backlight, ALSA volume, battery, RetroArch
# setup). BasedOS is BusyBox init with no systemd, NetworkManager or udev, so the functions below
# replace dArkMossCommon's systemd and nmcli ones. Bluetooth is not brought up on BasedOS yet.

. "/mnt/SDCARD/spruce/scripts/platform/darkmoss/dArkMossCommon.sh"

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

device_wifi_power_on() {
    :
}

device_wifi_power_off() {
    :
}

device_start_dhcp_client() {
    :
}

device_stop_dhcp_client() {
    :
}

device_wifi_connect() {
    log_message "$PLATFORM: Wi-Fi networks are set in BasedOS (/data/wpa_supplicant.conf); not adding $1"
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

# The kernel offers deep sleep (mem_sleep = s2idle [deep]); no systemd to ask.
trigger_device_sleep() {
    sync
    echo mem > /sys/power/state
}

  ###################
#####   POWER   #####
  ###################

# BusyBox init: its poweroff and reboot run BasedOS's rcK, which unmounts the card.
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
