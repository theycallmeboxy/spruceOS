#!/bin/sh
# BasedOS (github.com/theycallmeboxy/BasedOS), the base every basedos/ board shares: a BaseOS-style
# system on the eMMC with BusyBox init and no systemd, NetworkManager or udev, which runs spruce from
# the card. A board's .sh sources the hardware it shares with another base first (the 350H Ultra:
# dArkMossCommon.sh), then this, which replaces what assumes that base's userland; the board's own
# file keeps only its hardware. BasedOSCommon.cfg holds the matching variables.

. "/mnt/SDCARD/spruce/scripts/platform/utils/baseos_session_shield.sh"

# The spruce login (password happygaming) for spruce's dropbear and Samba, as the H700 BaseOS
# platform adds it (AnbernicXXCommon.sh): bind-mounted copies of /etc/passwd and /etc/shadow, never
# written to the base's files; a reboot drops them.
add_spruce_system_user() {
    grep -q '^spruce:' /etc/passwd 2>/dev/null && return 0

    SP_HASH='$6$spruceos00$.nwqRlVkLe.wmkXcEHXcu127ZFxpFQ.8JDbdh4CRd.FbF5biVcIl9qeE9T6QNAbbJaFKp3MLUwlaPUN0alXcl.'
    cp /etc/passwd /tmp/spruce_passwd || return 0
    cp /etc/shadow /tmp/spruce_shadow || return 0
    echo 'spruce:x:0:0:spruce:/root:/bin/sh' >> /tmp/spruce_passwd
    echo "spruce:${SP_HASH}:19000:0:99999:7:::" >> /tmp/spruce_shadow
    chmod 644 /tmp/spruce_passwd
    chmod 600 /tmp/spruce_shadow
    mount -o bind /tmp/spruce_passwd /etc/passwd
    mount -o bind /tmp/spruce_shadow /etc/shadow
}

# For the board's device_init, as on the H700 BaseOS: the spruce login for dropbear and Samba, and
# keep BasedOS's respawned session from remounting the card while save_poweroff shuts down.
basedos_session_init() {
    add_spruce_system_user
    shield_baseos_session /sbin/frontend-session
    basedos_portmaster_orientation
}

# PortMaster guesses the panel's orientation (stock's fbcon=rotate:3 and the panel's portrait mode
# say 270) and would turn its GUI and ports on top of BasedOS's SDL2, which already turns the panel.
# Its device_info.txt reads /tmp/spruce_device_info.env after its own guess; runtime.sh writes that
# file (write_device_info) before device_init, so the orientation is added here.
basedos_portmaster_orientation() {
    [ -f /tmp/spruce_device_info.env ] || return 0
    grep -q '^DISPLAY_ORIENTATION=' /tmp/spruce_device_info.env ||
        echo 'DISPLAY_ORIENTATION="0"' >> /tmp/spruce_device_info.env
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

# As the BaseOS platforms, BasedOS installs a baseos-<target>-<version>.bosupd from the card root at
# the next boot (its basedos-update), but only when asked: BasedOS's own updater app
# (App/-FirmwareUpdate-/basedosUpdate.sh) fetches or finds one, asks for the install (basedos-update
# request) and reboots. Releases come from BASEOS_TARGET's repo (baseos_repo).
check_if_fw_needs_update() {
    baseos_fw_needs_update
}

local_fw_update_file() {
    baseos_local_update_file
}

device_get_fw_version() {
    sed -n 's/^BASEOS_VERSION=//p' /etc/baseos-release 2>/dev/null | tr -d '"'
}

  ###################
#####   PORTS   #####
  ###################

# spruce's run_port (emu/lib/ports_functions.sh), BasedOS's own copy, so that RetroArch-core ports
# run. Their scripts call $raloc/retroarch, which is /usr/bin/retroarch for a firmware PortMaster's
# scripts don't name (spruce among them), and BasedOS has no RetroArch of its own. As spruce does
# for the A30 (run_A30_port), the port runs from a copy of its script whose retroarch call is
# spruce's own RetroArch with this platform's config, started as spruce starts it (run_retroarch).
# Every port is waited for, as run_port waits for the others, so the menu doesn't come back over
# the game. standard_launch.sh calls this for PLATFORM_FAMILY basedos.
#
# Ports on PortMaster's Weston pack (westonwrap.sh) get three things more:
# - udev's daemon while they run (BasedOS's basedos-udev): Weston won't start without input
#   devices, and libinput finds them only in udev's database. BasedOS doesn't otherwise run it, so
#   it is stopped again after the port and nothing else sees udev.
# - CRUSTY_LIBSDL, BasedOS's SDL2 for the pack's Crusty layer to draw with. westonwrap.sh would take
#   the first libSDL2 on the library path, PortMaster's own (its lib folder comes first), and
#   Crusty can't use that build: it tells its own SDL's calls from the program's by the first
#   memory range of the library, and that SDL's first range isn't its code, so Crusty fakes SDL's
#   display device for it too and recurses until it runs out of files. BasedOS's SDL2 also turns
#   the picture for this panel. CRUSTY_LIBSDL32 likewise, for the pack's 32-bit ports (BasedOS's
#   /usr/lib32), and Crusty's /tmp links to its SDL are removed first: it never replaces them.
# - after the port, what's left of it ended (end_weston_port_leftovers). Quitting (gptokeyb's
#   Select+Start) sends SIGTERM to every process whose command line names the game, westonwrap.sh
#   among them, so the port script goes on to clean up and unmount the pack while the game is still
#   shutting down with its display gone, and PortMaster's pm_finish kills gptokeyb before it can
#   force the game. The game is left behind, sometimes for good (Alex the Allegator 4 hung in its
#   own SIGTERM handler), holding /tmp/weston. Ports without the pack exit cleanly (Celeste Classic,
#   DevilutionX checked).
is_weston_port() {
    grep -q "westonwrap\.sh" "$ROM_FILE"
}

# end_weston_port_leftovers <port session id>: give what's left in the port's process group 3 s to
# exit, then kill it, as spruce's menu button ends a port (button_actions.sh); then unmount the
# pack if the port's script couldn't.
end_weston_port_leftovers() {
    _i=0
    while kill -0 -"$1" 2>/dev/null && [ "$_i" -lt 30 ]; do
        sleep 0.1
        _i=$((_i + 1))
    done
    if kill -0 -"$1" 2>/dev/null; then
        log_message "Weston port: processes still running 3 s after it ended; killing them"
        kill -9 -"$1" 2>/dev/null
        sleep 0.5
    fi
    if grep -q " /tmp/weston " /proc/mounts; then
        umount /tmp/weston 2>/dev/null && log_message "Weston port: unmounted the pack its script left mounted"
    fi
}

run_basedos_port() {
    log_message "Running port on $PLATFORM w/ ($PLATFORM_ARCHITECTURE)"

    PORTS_DIR=/mnt/SDCARD/Roms/ports
    export PORTS_DIR

    device_prepare_for_ports_run

    # Setup variables
    export HOME="/mnt/SDCARD/Saves/flip/home"
    export LD_LIBRARY_PATH="$PORTS_LD_LIBRARY_PATH:$LD_LIBRARY_PATH"
    export LC_ALL=C

    export XDG_DATA_HOME="/mnt/SDCARD/Persistent/portmaster/"
    PM_DIR="/mnt/SDCARD/Persistent/portmaster/PortMaster"
    export PATH="/mnt/SDCARD/spruce/flip/bin/:$PATH"

    set_port_abxy_scheme
    launch_script="$ROM_FILE"
    tmp_launch_script=""
    if is_retroarch_port; then
        . /mnt/SDCARD/spruce/scripts/emu/lib/ra_functions.sh
        prepare_ra_config 2>/dev/null
        # RetroArch runs with HOME=/mnt/SDCARD/RetroArch/ and opens ALSA's default from its
        # .asoundrc there: written for this device first, as run_retroarch does (the card may have
        # been in another device last, whose sound card isn't here).
        /mnt/SDCARD/spruce/scripts/asound-setup.sh /mnt/SDCARD/RetroArch
        _ra="/mnt/SDCARD/RetroArch/${RA_BIN_64:-ra64.universal}"
        # The rewrite takes a line's retroarch command at its start or after ; & | (an exec
        # first, a path before it). Every RetroArch port in PortMaster's catalogue (seven, checked
        # 2026-11-21) calls it so: $raloc/retroarch $raconf -L <core> <content>. A line that
        # passes its own -c/--config is left as it is.
        tmp_launch_script=$(mktemp "${ROM_FILE}.basedos.XXXXXX") || {
            log_message "Unable to create a temporary launch script for $ROM_FILE"
            return 1
        }
        if ! sed -E '
            /^[[:space:]]*#/! {
                /[[:space:]](-c|--config)(=|[[:space:]])/! s#(^[[:space:]]*|[;&|][[:space:]]*)(exec[[:space:]]+)?([^[:space:];|&]*/)?retroarch([[:space:]]|$)#\1\2env HOME=/mnt/SDCARD/RetroArch/ '"$_ra"' --config '"$PLATFORM_CFG"'\4#
            }
        ' "$ROM_FILE" > "$tmp_launch_script"; then
            log_message "Unable to rewrite the RetroArch call in $ROM_FILE"
            rm -f "$tmp_launch_script"
            return 1
        fi
        chmod 755 "$tmp_launch_script"
        launch_script="$tmp_launch_script"
        log_message "Launching RA port $ROM_FILE with $_ra --config $PLATFORM_CFG"
        cd /mnt/SDCARD/RetroArch/
    else
        mount -o bind \
            /mnt/SDCARD/Persistent/portmaster/bin/python3.10 \
            /mnt/SDCARD/Persistent/portmaster/bin/python

        log_message "PORTS_DIR: $PORTS_DIR, HOME=$HOME, LD_LIBRARY_PATH=$LD_LIBRARY_PATH, PATH=$PATH"
    fi

    weston_port="" weston_udev=""
    if is_weston_port; then
        weston_port=1
        export CRUSTY_LIBSDL=/usr/lib/libSDL2-2.0.so.0
        # 32-bit ports: the pack's own 32-bit lookup, which would find PortMaster's or another SDL
        # first just the same.
        [ -e /usr/lib32/libSDL2-2.0.so.0 ] && export CRUSTY_LIBSDL32=/usr/lib32/libSDL2-2.0.so.0
        # Crusty links its SDL into /tmp once and never replaces the link, so a run without these
        # (an older BasedOSCommon, a port started some other way) would keep the wrong SDL until
        # a reboot.
        # (/tmp/CRUSTY_LIBSDL64.so from the 64-bit Crusty, /tmp/CRUSTY_LIBSDL.so from the 32-bit one.)
        rm -f /tmp/CRUSTY_LIBSDL64.so /tmp/CRUSTY_LIBSDL.so
        if command -v basedos-udev >/dev/null 2>&1 && basedos-udev start; then
            weston_udev=1
            log_message "Weston port: CRUSTY_LIBSDL=$CRUSTY_LIBSDL, udevd started"
        else
            log_message "Weston port: CRUSTY_LIBSDL=$CRUSTY_LIBSDL, no udevd (BasedOS older than basedos-udev?)"
        fi
    fi

    setsid "$launch_script" > /mnt/SDCARD/Saves/spruce/port.log 2>&1 &
    SID=$!
    echo "$SID" > /tmp/last_port_sid
    wait "$SID"
    rm -f /tmp/last_port_sid
    [ -n "$tmp_launch_script" ] && rm -f "$tmp_launch_script"
    if [ -n "$weston_port" ]; then
        end_weston_port_leftovers "$SID"
        [ -n "$weston_udev" ] && basedos-udev stop
    fi

    device_cleanup_after_ports_run
}
