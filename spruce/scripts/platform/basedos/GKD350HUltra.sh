#!/bin/sh
# GKD 350H Ultra on BasedOS: this board's implementation. It stands alone: what it shares with the
# dArkMoss RK3566 units (input discovery, the MainUI alias, backlight, ALSA volume, battery, sleep,
# RetroArch setup) was copied from dArkMossCommon.sh (spruce faa0afebf, 2026-11-16) rather than
# sourced, so changes there don't reach this platform and the reverse; the copies keep their
# dArkMoss names. BasedOSCommon.sh holds what is BasedOS's rather than the board's (SSH, Wi-Fi,
# sleep, power, firmware). Bluetooth is not brought up on BasedOS yet.

. "/mnt/SDCARD/spruce/scripts/platform/common64bit.sh"
. "/mnt/SDCARD/spruce/scripts/platform/utils/cpu_control_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/utils/watchdog_launcher.sh"
. "/mnt/SDCARD/spruce/scripts/retroarch_utils.sh"
. "/mnt/SDCARD/spruce/scripts/platform/utils/sleep_functions.sh"
. "/mnt/SDCARD/spruce/scripts/platform/basedos/BasedOSCommon.sh"

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
    basedos_session_init
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

  ###################
#####   SLEEP   #####
  ###################

# Sleep is BasedOS's (BasedOSCommon.sh): basedos-suspend restores the ES9018K2M DAC's volume,
# which the stock kernel loses in deep sleep. The RTC (hym8563, on always-on GPIO0) wakes the board.

# Idle shutdown watches the pad's js node (js0 under event3), as on the H700 BaseOS.
set_event_arg_for_idlemon() {
    set_idlemon_to_pad
}


  ###################
#####   POWER   #####
  ###################

# The charger is the bq25890 (power_supply/bq25890-charger, type USB), not the ac and usb supplies
# dArkMossCommon reads: plugged in, a low battery must not force a shutdown.
device_low_battery_shutdown_ok() {
    if grep -qs "^1$" /sys/class/power_supply/bq25890-charger/online; then
        log_message "$PLATFORM battery: charger online, not forcing a shutdown"
        return 1
    fi
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

  ######################################################
#####   AS ON THE dArkMoss RK3566 UNITS (copied)   #####
  ######################################################

new_execution_loop() {
    log_message "new_execution_loop unneeded on this device" -v
}

  #################
#####   INPUT   #####
  #################

# The pad, by by-path link first (PAD_NODE_CANDIDATES) then by evdev name
# (PAD_NAME_CANDIDATES), both from the platform cfg.
resolve_pad_node() {
    _pad=""
    for _node in $PAD_NODE_CANDIDATES; do
        [ -e "$_node" ] && { _pad="$_node"; break; }
    done
    if [ -z "$_pad" ]; then
        _old_ifs="$IFS"; IFS='|'
        for _name in $PAD_NAME_CANDIDATES; do
            for _dir in /sys/class/input/event*; do
                if [ "$(cat "$_dir/device/name" 2>/dev/null)" = "$_name" ]; then
                    _pad="/dev/input/$(basename "$_dir")"
                    break 2
                fi
            done
        done
        IFS="$_old_ifs"
    fi
    if [ -n "$_pad" ]; then
        export EVENT_PATH_READ_INPUTS_SPRUCE="$_pad"
        export EVENT_PATH_SEND_TO_RA_AND_PPSSPP="$_pad"
        export EVENT_PATH_SEND_TO_DRASTIC="$_pad"
        log_message "$PLATFORM: joypad at $_pad"
    else
        log_message "$PLATFORM: no joypad node found - controls will be dead"
    fi
}

# Does the node declare BOTH KEY_VOLUMEDOWN(114) and KEY_VOLUMEUP(115)? A
# phantom single capability exists on some adc-keys nodes; a real rocker has both.
node_reports_volume_keys() {
    _caps="/sys/class/input/$1/device/capabilities/key"
    [ -r "$_caps" ] || return 1
    awk '{
        s=""
        for (i=1; i<=NF; i++) { w=$i; if (i>1) { while (length(w)<16) w="0" w } s=s w }
        have=0
        for (k=114; k<=115; k++) {
            nib=int(k/4); bit=k%4; pos=length(s)-nib
            if (pos < 1) continue
            c=tolower(substr(s,pos,1))
            v=index("0123456789abcdef",c)-1
            if (v < 0) continue
            if (int(v/(2^bit))%2 == 1) have++
        }
        exit (have==2)?0:1
    }' "$_caps"
}

# Find the power and volume nodes by asking the kernel, and persist them to
# SPRUCE_INPUT_NODES_FILE: the button watchdogs are separate processes that
# re-source the platform cfg, which reads that file back.
#
# When the volume keys sit on the pad itself, every pad watcher already sees
# them; EVENT_PATH_VOLUME is parked on the power node so nothing reads the pad
# twice, and VOLUME_KEYS_ON_PAD tells buttons_watchdog to leave volume to the
# menu while one is up.
resolve_key_event_node() {
    _power=""
    _volume=""
    _seen=""

    for _dir in /sys/class/input/event*; do
        [ -e "$_dir" ] || continue
        _ev=$(basename "$_dir")
        _name=$(cat "$_dir/device/name" 2>/dev/null)
        _seen="$_seen ${_ev}:${_name}"

        if node_reports_volume_keys "$_ev" && [ -z "$_volume" ]; then
            _volume="/dev/input/$_ev"
        fi
        case "$_name" in
            *pwrkey*|*Power*|*power*) [ -z "$_power" ] && _power="/dev/input/$_ev" ;;
        esac
    done

    log_message "$PLATFORM: input nodes:$_seen"

    if [ -n "$_power" ] && [ -c "$_power" ]; then
        export EVENT_PATH_POWER="$_power"
        log_message "$PLATFORM: power key on $_power"
    fi

    VOLUME_KEYS_ON_PAD=0
    if [ -n "$_volume" ] && [ -c "$_volume" ]; then
        if [ "$_volume" = "$EVENT_PATH_READ_INPUTS_SPRUCE" ]; then
            VOLUME_KEYS_ON_PAD=1
            export EVENT_PATH_VOLUME="$EVENT_PATH_POWER"
            log_message "$PLATFORM: volume keys are on the joypad node"
        else
            export EVENT_PATH_VOLUME="$_volume"
            log_message "$PLATFORM: volume keys on $_volume"
        fi
    else
        log_message "$PLATFORM: no node reports the volume keys - leaving $EVENT_PATH_VOLUME"
    fi
    export VOLUME_KEYS_ON_PAD

    {
        echo "EVENT_PATH_READ_INPUTS_SPRUCE='${EVENT_PATH_READ_INPUTS_SPRUCE}'"
        echo "EVENT_PATH_SEND_TO_RA_AND_PPSSPP='${EVENT_PATH_READ_INPUTS_SPRUCE}'"
        echo "EVENT_PATH_SEND_TO_DRASTIC='${EVENT_PATH_READ_INPUTS_SPRUCE}'"
        echo "EVENT_PATH_VOLUME='${EVENT_PATH_VOLUME}'"
        echo "EVENT_PATH_POWER='${EVENT_PATH_POWER}'"
        echo "VOLUME_KEYS_ON_PAD='${VOLUME_KEYS_ON_PAD}'"
    } > "$SPRUCE_INPUT_NODES_FILE" 2>/dev/null
}

setup_mainui_alias() {
    MAINUI="/mnt/SDCARD/spruce/flip/bin/MainUI"
    PY="/mnt/SDCARD/spruce/flip/bin/python3.10"

    if [ ! -f "$PY" ]; then
        log_message "$PLATFORM: $PY missing - PyUI cannot start"
        return 1
    fi

    if [ -s "$MAINUI" ] && [ "$(stat -c%s "$MAINUI" 2>/dev/null)" = "$(stat -c%s "$PY" 2>/dev/null)" ]; then
        return 0
    fi

    touch "$MAINUI" 2>/dev/null
    mount -o bind "$PY" "$MAINUI" 2>/dev/null

    if [ ! -s "$MAINUI" ]; then
        log_message "$PLATFORM: MainUI bind mount failed, copying interpreter instead"
        umount "$MAINUI" 2>/dev/null
        cp "$PY" "$MAINUI" || { log_message "$PLATFORM: could not create MainUI"; return 1; }
        chmod +x "$MAINUI" 2>/dev/null
    fi
    log_message "$PLATFORM: MainUI alias ready ($(stat -c%s "$MAINUI" 2>/dev/null) bytes)"
}

  ###################
#####   POWER   #####
  ###################

# The kernel's gauge (dArkMoss's reads BatteryPlus's smoothed file first; BasedOS has no BatteryPlus).
device_get_battery_percent() {
    cat "$BATTERY/capacity" 2>/dev/null || echo 0
}

device_get_charging_status() {
    cat "/sys/class/power_supply/battery/status"
}

device_headphones_connected() {
    are_headphones_plugged_in
}

  ###################
#####   SLEEP   #####
  ###################

WAKE_ALARM_PATH="/sys/class/rtc/rtc0/wakealarm"

# The RTC's time from sysfs, without hwclock.
device_get_hw_epoch() {
    cat /sys/class/rtc/rtc0/since_epoch 2>/dev/null
}

device_enter_sleep() {
    IDLE_TIMEOUT="$1"
    log_message "Entering sleep w/ IDLE_TIMEOUT of $IDLE_TIMEOUT"
    save_sleep_info "$IDLE_TIMEOUT" || return 1
    set_wake_alarm "$IDLE_TIMEOUT" "$WAKE_ALARM_PATH" || return 1
    # A timed wake must not light the panel or run the game until save_poweroff
    # closes it: the backlight goes off and the game stops here, and only a manual
    # wake (device_exit_sleep) restores both.
    signal_emulators STOP
    echo 0 > "$DEVICE_BACKLIGHT_PATH"
    trigger_device_sleep
}

darkmoss_exit_sleep() {
    set_volume "$(get_volume_level)" false
    echo 0 >"$WAKE_ALARM_PATH" 2>/dev/null
    apply_backlight "$(get_backlight_level)"
    signal_emulators CONT
}

signal_emulators() {
    for process in $EMU_PROCESSES; do
        killall -q -"$1" "$process" 2>/dev/null
    done
}

device_exit_sleep() {
    darkmoss_exit_sleep
}

# extcon reports 1, a DRM connector reports "connected".
device_hdmi_connected() {
    case "$(cat "$HDMI_STATE_PATH" 2>/dev/null)" in
        1|connected) return 0 ;;
        *) return 1 ;;
    esac
}

  #################
#####   AUDIO   #####
  #################

are_headphones_plugged_in() {
    [ -n "$HEADPHONE_STATE_PATH" ] && [ "$(cat "$HEADPHONE_STATE_PATH" 2>/dev/null)" = "1" ]
}

apply_playback_path() {
    if are_headphones_plugged_in; then
        amixer -q cset name="$AUDIO_PATH_CONTROL" "$AUDIO_PATH_HP" 2>/dev/null
    else
        amixer -q cset name="$AUDIO_PATH_CONTROL" "$AUDIO_PATH_SPK" 2>/dev/null
    fi
}

get_volume_level() {
    jq -r '.vol' "$SYSTEM_JSON" 2>/dev/null || echo 0
}

volume_up() {
    VOLUME_LV=$(get_volume_level)
    if [ "$VOLUME_LV" -lt 20 ]; then
        set_volume "$(( VOLUME_LV + 1 ))"
    fi
}

volume_down() {
    VOLUME_LV=$(get_volume_level)
    if [ "$VOLUME_LV" -gt 0 ]; then
        set_volume "$(( VOLUME_LV - 1 ))"
    fi
}

get_current_volume() {
    # Opt-in (cfg): read on the same mapped (-M) scale that set_volume writes.
    amixer ${DARKMOSS_VOLUME_READ_MAPPED:+-M} get "${VOLUME_CONTROL:-Master}" 2>/dev/null | sed -n 's/.*\[\([0-9]\+\)%\].*/\1/p' | head -1
}

# Level before path: switching output with the old level applied is what
# produced the burst the Flip had to be fixed for.
set_volume() {
    VOLUME_LV="$1"
    SAVE_TO_CONFIG="${2:-true}"

    VOLUME_PCT=$(( VOLUME_LV * 5 ))
    [ "$VOLUME_PCT" -gt 100 ] && VOLUME_PCT=100
    [ "$VOLUME_PCT" -lt 0 ] && VOLUME_PCT=0

    amixer -q sset -M "${VOLUME_CONTROL:-Master}" "${VOLUME_PCT}%" 2>/dev/null
    bt_headset_volume "$(( VOLUME_PCT / 5 ))"
    apply_playback_path
    log_message "$PLATFORM: volume ${VOLUME_LV}/20 (${VOLUME_PCT}%)"

    if [ "$SAVE_TO_CONFIG" = true ]; then
        save_volume_to_config_file "$VOLUME_LV" 2>/dev/null
    fi
}

# bluealsad 5's ALSA plugin would switch the codec to each client's rate (see
# asound-setup.sh); 48 kHz is what it picks at connect and what games use.
BT_PCM_RATE=48000

# bluealsad 5 has bluealsactl: soft volume, so the level holds on headsets that
# ignore the remote one. Same 0-20 level as device.sh's default.
bt_headset_volume() {
    pgrep -x bluealsad >/dev/null 2>&1 || return 0
    _v=$(( $1 * 127 / 20 ))
    for _pcm in $(${BTCTL_TIMEOUT:-timeout 2} bluealsactl --quiet list-pcms 2>/dev/null | grep '/a2dpsrc/sink$'); do
        # bluealsad 5.0 starts each headset on its own volume, and turning SoftVolume on
        # resets the level to full: only switch it when off, or every press bursts.
        ${BTCTL_TIMEOUT:-timeout 2} bluealsactl soft-volume "$_pcm" 2>/dev/null | grep -q true ||
            ${BTCTL_TIMEOUT:-timeout 2} bluealsactl soft-volume "$_pcm" y >/dev/null 2>&1
        ${BTCTL_TIMEOUT:-timeout 2} bluealsactl volume "$_pcm" "$_v" "$_v" >/dev/null 2>&1
    done
}

get_backlight_level() {
    jq -r '.backlight // 5' "$SYSTEM_JSON" 2>/dev/null || echo 5
}

# Panel only, for PyUI's backlightCmd: PyUI saves the level itself, and its
# screensaver dim must not be saved.
apply_backlight() {
    level="$1"
    [ "$level" -lt 0 ] && level=0
    [ "$level" -gt 10 ] && level=10
    eval "raw=\$SYSTEM_BACKLIGHT_LEVEL_$level"
    echo "$raw" > "$DEVICE_BACKLIGHT_PATH"
    echo 0 > /sys/class/backlight/backlight/bl_power 2>/dev/null
}

set_backlight() {
    apply_backlight "$1"
    log_message "$PLATFORM: backlight ${level}/10 (raw $raw)"
    tmp="$SYSTEM_JSON.tmp.$$"
    jq ".backlight = $level" "$SYSTEM_JSON" > "$tmp" && mv "$tmp" "$SYSTEM_JSON" || rm -f "$tmp"
}

# PyUI's volumeCmd: the 0-20 level PyUI has already saved.
apply_volume() {
    set_volume "$1" false
}

device_backlight_down() {
    set_backlight $(( $(get_backlight_level) - 1 ))
}

device_backlight_up() {
    set_backlight $(( $(get_backlight_level) + 1 ))
}

# spruce's ALSA config is ~/.asoundrc (device_init writes it), so a program with
# another HOME gets raw hw:0,0. device_write_default_asound_rc names its default
# spruce_speaker; asound-setup.sh adds spruce_bt and the default.
ASOUND_SPRUCE_PCMS=1

  #############################
#####   MENU LOOP HOOKS   #####
  #############################

post_pyui_exit() {
    log_message "post_pyui_exit not needed on this device" -v
}

enable_or_disable_rgb() {
    log_message "No controllable RGB LED on this device" -v
}

rgb_led() {
    return 0
}

# The button printed "Home" (B_HOME, BTN_TRIGGER_HAPPY1) in a game: the action picked in Settings ->
# Button Settings -> Home button action, through the shared perform_action (button_actions.sh), as
# the Smart Pro S and XU20 do. In the menu PyUI handles it itself (the same setting).
device_home_button_pressed() {
    action="$(get_config_value '.menuOptions."Button Settings".homeAction.selected' "Game Switcher")"
    perform_action "$action"
    # perform_action leaves game-state cleanup to the caller: only the actions that end the game.
    case "$action" in
        "Game Switcher"|"Exit game")
            rm -f /tmp/cmd_to_run.sh
            rm -f /mnt/SDCARD/spruce/flags/lastgame.lock
            ;;
    esac
}

  ###############################
#####   EMULATION AND PORTS   #####
  ###############################

# 64-bit only. The per-core library cases are the Flip's and apply unchanged:
# the same aarch64 userland libraries. EASYRPG genuinely has no lib-RGB30.
setup_for_retroarch() {
    case "$CORE" in
        uae4arm)      export LD_LIBRARY_PATH="$EMU_DIR:$LD_LIBRARY_PATH" ;;
        easyrpg)      export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR/lib-Flip" ;;
        yabasanshiro) export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$EMU_DIR/lib64" ;;
    esac

    export CORE_DIR="$RA_DIR/.retroarch/cores64"

    if [ -f "$EMU_DIR/${CORE}_libretro.so" ]; then
        export CORE_PATH="$EMU_DIR/${CORE}_libretro.so"
    else
        export CORE_PATH="$CORE_DIR/${CORE}_libretro.so"
    fi

    echo "$RA_BIN"
}

device_prepare_for_ports_run() {
    :
}

device_cleanup_after_ports_run() {
    log_message "device_cleanup_after_ports_run unneeded on this device" -v
}

# Force-feedback rumble through the pad's evdev node. On a unit without a
# motor the kernel accepts the effect and nothing happens.
# Tiers tuned 2026-09-01 on a modded RGB30: the small button motor is faint,
# so the tier carries a duration as well as a magnitude.
darkmoss_vibrate() {
    duration=""
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"

    while [ $# -gt 0 ]; do
        case "$1" in
        --intensity)
            shift
            intensity="$1"
            ;;
        [0-9]*)
            duration="$1"
            ;;
        esac
        shift
    done

    case "$intensity" in
        "Off")    return 0 ;;
        "Weak")   intensity=0xC000; tier_duration=200 ;;
        "Medium") intensity=0xFFFF; tier_duration=300 ;;
        "Strong") intensity=0xFFFF; tier_duration=450 ;;
        *)        intensity=0xFFFF; tier_duration=300 ;;
    esac
    [ -n "$duration" ] || duration="$tier_duration"

    [ -x /mnt/SDCARD/spruce/bin64/rumble ] || return 0
    /mnt/SDCARD/spruce/bin64/rumble "$EVENT_PATH_READ_INPUTS_SPRUCE" "$intensity" "$duration"
}

vibrate() {
    darkmoss_vibrate "$@"
}

# fb0 is a dead shim under DRM, so grab the KMS plane. That plane is the panel's scanout, 1440x1600
# and turned (BasedOS's SDL2 turns every frame with the RGA), so the capture is turned back 90
# degrees clockwise (ffmpeg transpose=1) to the 1600x1440 picture. spruce/bin/ffmpeg is the
# static build with the kmsgrab demuxer (bin64/ffmpeg has none); BasedOS has no ffmpeg of its own.
take_screenshot() {
    screenshot_path="$1"
    [ -n "$screenshot_path" ] || return 1
    _ff=/mnt/SDCARD/spruce/bin/ffmpeg
    [ -x "$_ff" ] || {
        log_message "take_screenshot: no ffmpeg with kmsgrab available"
        return 1
    }
    mkdir -p "$(dirname "$screenshot_path")" 2>/dev/null

    if timeout 15 "$_ff" -hide_banner -loglevel error \
        -f kmsgrab -i - \
        -vf "hwdownload,format=bgr0,format=rgba,transpose=1" \
        -frames:v 1 -update 1 -y "$screenshot_path" >/dev/null 2>&1; then
        return 0
    fi

    rm -f "$screenshot_path" 2>/dev/null
    log_message "take_screenshot: kmsgrab capture failed"
    return 1
}

get_config_path() {
    echo "$SYSTEM_JSON"
}

  ###################################
#####   SLEEP: THE WAKE ALARM   #####
  ###################################

# spruce's set_wake_alarm (utils/sleep_functions.sh), with the alarm rounded up to the RTC's
# resolution: the hym8563 only has minute alarms (WAKE_ALARM_RESOLUTION), which fire at the start
# of the minute, possibly before TARGET_EPOCH, and device_woke_via_timer only allows
# DRIFT_TOLERANCE early.
set_wake_alarm() {
    IDLE_TIMEOUT="$1"
    WAKE_ALARM_PATH="$2"

    # If timeout is not positive, do not set an alarm
    if [ "$IDLE_TIMEOUT" -le 0 ]; then
        log_message "set_wake_alarm: IDLE_TIMEOUT <= 0, not setting wakealarm"
        return 0
    fi

    if [ -e "$WAKE_ALARM_PATH" ]; then
        # Clear previous alarm first (important on some BSP kernels)
        echo 0 >"$WAKE_ALARM_PATH" 2>/dev/null

        # WAKE_ALARM_RESOLUTION (platform cfg, seconds): an RTC whose alarm only has that
        # resolution fires at the start of the slot, possibly before TARGET_EPOCH, and
        # device_woke_via_timer only allows DRIFT_TOLERANCE early. Round the alarm up to the slot.
        _alarm="$IDLE_TIMEOUT"
        _res="${WAKE_ALARM_RESOLUTION:-1}"
        if [ "$_res" -gt 1 ]; then
            _now="$(device_get_hw_epoch)"
            [ -n "$_now" ] && _alarm=$(( IDLE_TIMEOUT + (_res - (_now + IDLE_TIMEOUT) % _res) % _res ))
        fi

        if ! echo "+$_alarm" >"$WAKE_ALARM_PATH" 2>/dev/null; then
            log_message "WARNING: Failed to write WAKE_ALARM_PATH"
            return 1
        fi

        if [ "$_alarm" = "$IDLE_TIMEOUT" ]; then
            log_message "set_wake_alarm: Wakealarm set for +$IDLE_TIMEOUT seconds"
        else
            log_message "set_wake_alarm: Wakealarm set for +$_alarm seconds ($IDLE_TIMEOUT rounded up to the RTC's ${_res} s alarm resolution)"
        fi
    else
        log_message "WARNING: WAKE_ALARM_PATH missing, relying on external wake"
    fi

    return 0
}
