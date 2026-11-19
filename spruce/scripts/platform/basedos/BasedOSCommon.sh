#!/bin/sh
# BasedOS (github.com/theycallmeboxy/BasedOS), the base every basedos/ board shares: a BaseOS-style
# system on the eMMC with BusyBox init and no systemd, NetworkManager or udev, which runs spruce from
# the card. A board's .sh sources the hardware it shares with another base first (the 350H Ultra:
# dArkMossCommon.sh), then this, which replaces what assumes that base's userland; the board's own
# file keeps only its hardware. BasedOSCommon.cfg holds the matching variables.

. "/mnt/SDCARD/spruce/scripts/platform/utils/baseos_session_shield.sh"
. "/mnt/SDCARD/spruce/scripts/platform/utils/spruce_system_user.sh"

# For the board's device_init, as on the H700 BaseOS: the spruce login for dropbear and Samba, and
# keep BasedOS's respawned session from remounting the card while save_poweroff shuts down.
basedos_session_init() {
    add_spruce_system_user
    shield_baseos_session /sbin/frontend-session
}

  #################
#####   SSH   #####
  #################

# spruce's own dropbear owns port 22, as on the H700 BaseOS: with SSH on it stops BasedOS's sshd
# and starts its own, with SSH off it stops both (sshFunctions.sh). No systemctl here, so this is
# common64bit's name again over any systemd unit name a hardware layer gave.
get_ssh_service_name() {
    echo "dropbearmulti"
}

  ##################
#####   WIFI   #####
  ##################

# spruce owns Wi-Fi, as on its wpa_supplicant devices: its own supplicant on the card's saved
# networks ($WPA_SUPPLICANT_FILE) and udhcpc (BasedOS's default.script sets the address, route and
# DNS). BasedOS only loads the board's Wi-Fi driver at boot (BASEDOS_WIFI_MODULE); its own
# supplicant runs only in maintenance mode or after a failing frontend. These are spruce's
# defaults again over a hardware layer's NetworkManager ones.
device_manages_own_wifi() {
    return 1
}

# The driver stays loaded (BasedOS loads it at boot; this covers a boot where that failed or hasn't
# finished): on and off take the link up and down.
device_wifi_power_on() {
    if [ ! -e /sys/class/net/wlan0 ] && [ -n "$BASEDOS_WIFI_MODULE" ]; then
        modprobe "$BASEDOS_WIFI_MODULE" 2>/dev/null
        _w=0
        while [ ! -e /sys/class/net/wlan0 ] && [ "$_w" -lt 50 ]; do sleep 0.1; _w=$((_w + 1)); done
    fi
    ip link set wlan0 up 2>/dev/null
}

device_wifi_power_off() {
    ip link set wlan0 down 2>/dev/null
}

device_start_dhcp_client() {
    pgrep -f "udhcpc.*wlan0" >/dev/null || udhcpc -i wlan0 -b -t 5 -T 3
}

device_stop_dhcp_client() {
    killall -9 udhcpc 2>/dev/null
}

device_wifi_connect() {
    wpa_add_network "$1" "$2"
}

device_wifi_forget_all() {
    wpa_forget_all_networks
}

device_extra_wifi_setup() {
    :
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

# No systemd to ask: BasedOS's basedos-suspend writes mem to /sys/power/state and then does its own
# wake fixes (a board's driver quirks, as a systemd system-sleep hook would); it returns after
# resume. A BasedOS without it gets the plain write.
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
# then: spruce unmounts it itself (stage 2) and, being strict, also keeps its own respawned session
# from starting again. Same as the H700 BaseOS (AnbernicXXCommon.sh).
device_system_handles_sdcard_unmount() {
    return 1
}

device_needs_strict_unmount() {
    return 0
}

  ######################
#####   FIRMWARE   #####
  ######################

# As the BaseOS platforms: BasedOS installs a baseos-<target>-<version>.bosupd from the card root at
# the next boot (its basedos-update), so spruce's BaseOS updater only fetches or finds one and
# reboots. Releases come from BASEOS_TARGET's repo (baseos_repo).
check_if_fw_needs_update() {
    baseos_fw_needs_update
}

local_fw_update_file() {
    baseos_local_update_file
}

device_get_fw_version() {
    sed -n 's/^BASEOS_VERSION=//p' /etc/baseos-release 2>/dev/null | tr -d '"'
}
