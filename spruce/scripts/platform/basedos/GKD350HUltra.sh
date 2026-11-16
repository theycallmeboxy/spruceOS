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

# The kernel offers deep sleep (mem_sleep = s2idle [deep]); no systemd to ask. The write returns
# after resume. The RTC (hym8563, on always-on GPIO0) wakes the board from deep sleep.
trigger_device_sleep() {
    sync
    echo mem > /sys/power/state
}

# sleep_functions.sh's, with the alarm rounded up to a whole minute. The hym8563's alarm has
# minute resolution and fires at the start of the target minute, up to 59 s before
# TARGET_EPOCH, and device_woke_via_timer allows only 10 s early: a timed wake was taken for a
# manual one and the device stayed on (seen on the unit). Rounded up, it never fires early; the
# cost is up to 59 s more sleep before the shutdown.
set_wake_alarm() {
    IDLE_TIMEOUT="$1"
    WAKE_ALARM_PATH="$2"

    if [ "$IDLE_TIMEOUT" -le 0 ]; then
        log_message "set_wake_alarm: IDLE_TIMEOUT <= 0, not setting wakealarm"
        return 0
    fi
    _now=$(device_get_hw_epoch)
    _alarm="$IDLE_TIMEOUT"
    [ -n "$_now" ] && _alarm=$(( IDLE_TIMEOUT + (60 - (_now + IDLE_TIMEOUT) % 60) % 60 ))

    if [ -e "$WAKE_ALARM_PATH" ]; then
        echo 0 >"$WAKE_ALARM_PATH" 2>/dev/null
        if ! echo "+$_alarm" >"$WAKE_ALARM_PATH" 2>/dev/null; then
            log_message "WARNING: Failed to write WAKE_ALARM_PATH"
            return 1
        fi
        log_message "set_wake_alarm: Wakealarm set for +$_alarm seconds ($IDLE_TIMEOUT rounded up to the RTC's minute)"
    else
        log_message "WARNING: WAKE_ALARM_PATH missing, relying on external wake"
    fi
    return 0
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
