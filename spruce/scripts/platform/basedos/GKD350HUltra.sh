#!/bin/sh
# GKD 350H Ultra on BasedOS: this board's hardware. dArkMossCommon.sh carries what it shares with the
# dArkMoss RK3566 units (input discovery, the MainUI alias, backlight, ALSA volume, battery,
# RetroArch setup); BasedOSCommon.sh then replaces what assumes dArkMoss's systemd base (SSH, Wi-Fi,
# sleep, power, firmware). Bluetooth is not brought up on BasedOS yet.

. "/mnt/SDCARD/spruce/scripts/platform/darkmoss/dArkMossCommon.sh"
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
