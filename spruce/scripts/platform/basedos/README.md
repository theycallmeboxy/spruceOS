# BasedOS platforms: what they own, and why

The GKD 350H Ultra (`GKD350HUltra`, family `basedos`) is a standalone platform. Where spruce has a
config or an implementation for another platform that this one needs too, this platform carries **its
own copy** in its own files, rather than sourcing another platform's file or adding a hook (a variable or
branch) to shared or other platforms' code for convenience or a smaller codebase. Flattening the
duplicates is left to spruce's maintainers.

Why: changes for another platform can't break this one, and changes here can't reach theirs; the platform
can be reviewed on its own; and it is what spruce does itself (the E5 Plus copied `take_screenshot` into
its own file rather than hooking dArkMoss's). Decided 2026-11-19.

The copies below were taken from upstream spruce at **`faa0afebf`** (Development, 2026-11-16). To pick up
a later upstream fix in an original, diff the original at that commit against upstream and port the change
by hand.

## Files and functions this platform owns

### `GKD350HUltra.sh`: copied from `darkmoss/dArkMossCommon.sh`

The 350H Ultra (RK3576S) shares the Mali Bifrost GPU, the pad driver family and much of the board design
with the dArkMoss RK3566 units, so its board code began from dArkMoss's. No spruce platform sources
another base's Common file, and a change to dArkMoss's (a systemd base) shouldn't reach a BusyBox base, so
the parts used here are copied, with their comments, under the banner "AS ON THE dArkMoss RK3566 UNITS
(copied)". They keep their dArkMoss names (`darkmoss_unit`, `darkmoss_vibrate`, ...) so a maintainer can
match them to the originals.

Copied (42): `new_execution_loop`, `resolve_pad_node`, `node_reports_volume_keys`,
`resolve_key_event_node`, `setup_mainui_alias`, `device_get_battery_percent`,
`device_get_charging_status`, `device_headphones_connected`, `darkmoss_installed_version`,
`darkmoss_unit`, `device_get_hw_epoch`, `device_enter_sleep`, `darkmoss_exit_sleep`, `signal_emulators`,
`device_exit_sleep`, `device_hdmi_connected`, `are_headphones_plugged_in`, `apply_playback_path`,
`get_volume_level`, `volume_up`, `volume_down`, `get_current_volume`, `set_volume`,
`bt_headset_volume`, `get_backlight_level`, `apply_backlight`, `set_backlight`, `apply_volume`,
`device_backlight_down`, `device_backlight_up`, `post_pyui_exit`, `enable_or_disable_rgb`, `rgb_led`,
`setup_for_retroarch`, `device_prepare_for_ports_run`, `device_cleanup_after_ports_run`,
`darkmoss_vibrate`, `vibrate`, `take_screenshot`, `get_config_path`, `send_menu_button_to_retroarch`,
`darkmoss_shutdown_logo`; and the shell variables `WAKE_ALARM_PATH`, `BT_PCM_RATE`,
`ASOUND_SPRUCE_PCMS`.

Differences from the originals:

| What | Why |
|---|---|
| `take_screenshot` adds `transpose=1` to its ffmpeg filter | The KMS plane it grabs is the panel's 1440x1600 scanout, turned (BasedOS's SDL2 turns every frame with the RGA); turned back, the capture is the 1600x1440 picture. dArkMoss's has no turn. Was briefly a `SCREENSHOT_TRANSPOSE` hook in dArkMossCommon.sh; removed. |
| Not copied: `darkmoss_debug_dump`, `darkmoss_drm_holders`, `darkmoss_import_card_networks`, `darkmoss_power_action`, `darkmoss_prepare_for_poweroff`, `darkmoss_ssh_up`, `darkmoss_wifi_up`, `migrate_platform_files`, and `utils/rk817_pmic.sh` | Only dArkMoss's own `device_init`, Wi-Fi, SSH and power code reach them, and this platform replaces all of those (BasedOSCommon.sh, its own `device_init`). The RK817 PMIC isn't on this board. |
| Replaced by this platform's own: `device_init`, `device_write_default_asound_rc`, `device_low_battery_shutdown_ok`, `set_default_ra_hotkeys`, `set_event_arg_for_idlemon` | Board differences: the ES9018K2M DAC's "Digital" control as the volume (no softvol), the bq25890 charger, this pad's RetroArch numbering, idle watch on the pad's js node. |

The board's own code sits above the banner; the sources it needs (`common64bit.sh`,
`utils/cpu_control_functions.sh`, `utils/watchdog_launcher.sh`, `retroarch_utils.sh`,
`utils/sleep_functions.sh`) are spruce's shared utilities, sourced as every platform does.

### `GKD350HUltra.sh`: `set_wake_alarm`, from `utils/sleep_functions.sh`

spruce's function plus one change: the alarm is rounded up to the RTC's resolution
(`WAKE_ALARM_RESOLUTION`, 60 s in the cfg). The hym8563's alarm only has minutes; it fires at the start of
the minute, possibly before `TARGET_EPOCH`, and `device_woke_via_timer` only allows `DRIFT_TOLERANCE`
early, so it could fail to recognise the timer's wake (and "Shutdown after sleeping" not happen). Defined after the platform sources
`sleep_functions.sh`, which only platform files source, so this copy is the one that runs. Was briefly a
`WAKE_ALARM_RESOLUTION` branch in the shared file; removed.

### `GKD350HUltra.cfg`: copied from `darkmoss/dArkMossCommon.cfg`

The values dArkMoss's cfg sets and this platform doesn't set again, copied under the same banner, in place
of sourcing it. **Kept as they were and not yet checked one by one against this board**; a few are
probably dArkMoss-only and are candidates for review: `BATTERYPLUS_PERCENT_FILE` (BatteryPlus is a
dArkMoss image service), `CPU_SMART_GOVENOR`, `GPU_SMART_GOVERNOR`, `GPU_OVERCLOCK_GOVERNOR`,
`DEVICE_BACKLIGHT_PATH`, `SD_DEV`/`SD_MOUNTPOINT`.

### `BasedOSCommon.sh`: what is BasedOS's rather than the board's

| Function | Copied from | Why its own |
|---|---|---|
| SSH, Wi-Fi, Bluetooth stubs, sleep, power, firmware functions | spruce's defaults (`device.sh`, `common64bit.sh`) and the BaseOS platforms' | BasedOS has no systemd or NetworkManager: spruce's wpa_supplicant/udhcpc defaults again over dArkMoss's nmcli ones, BasedOS's `basedos-suspend`, BusyBox `poweroff`/`reboot`, the BaseOS updater (`.bosupd`). |
| `add_spruce_system_user` | `h700/AnbernicXXCommon.sh` | The spruce login (dropbear, Samba) on a base whose `/etc/passwd` lacks it. Was briefly moved into a shared `utils/spruce_system_user.sh` used by both platforms; reverted, the H700 file is upstream's again. |
| `basedos_portmaster_orientation` | (new; replaces a hook) | PortMaster guesses a 270-degree panel (stock's `fbcon=rotate:3`, the panel's portrait mode) and would turn its GUI and ports on top of BasedOS's SDL2, which already turns the panel. Adds `DISPLAY_ORIENTATION="0"` to `/tmp/spruce_device_info.env`, which runtime.sh writes before `device_init` and PortMaster's `device_info.txt` reads after its own guess. Was briefly a `PORTMASTER_DISPLAY_ORIENTATION` hook in `runtimeHelper.sh`; removed. |
| `run_basedos_port` | `emu/lib/ports_functions.sh`'s `run_port`, plus the A30's script rewrite (`run_A30_port`) | PortMaster's RetroArch-core ports (Quake, ...) call `$raloc/retroarch`, which is `/usr/bin/retroarch` for a firmware their scripts don't name; BasedOS has no RetroArch of its own. A port runs from a copy of its script whose `retroarch` call is spruce's own RetroArch (`RA_BIN_64`) with this platform's config, started as `run_retroarch` starts it, and every port is waited for (run_port starts RetroArch ports in the background, so the menu would come back over the game). Ports on PortMaster's Weston pack (`westonwrap.sh`) also get BasedOS's udevd for their length (`basedos-udev start/stop`: libinput finds input devices only in udev's database, and BasedOS doesn't otherwise run udevd) and `CRUSTY_LIBSDL` pointing at BasedOS's SDL2 (the pack would take PortMaster's own libSDL2, which its Crusty layer can't tell from the program's calls, and recurses), `CRUSTY_LIBSDL32` at BasedOS's 32-bit one for the pack's 32-bit ports, and Crusty's `/tmp` links to its SDL removed before each such port (Crusty never replaces them, so one run without these would keep the wrong SDL until a reboot). After such a port, `end_weston_port_leftovers` gives what's left of its process group 3 s, kills it as spruce's menu button ends a port, and unmounts the pack if the port's script couldn't: quitting sends SIGTERM to westonwrap.sh along with the game, so the script cleans up while the game is still exiting, and the game could be left behind holding `/tmp/weston` (ports without the pack exit cleanly). |

### Configs with this platform's name

| File | Began from | Why its own |
|---|---|---|
| `App/PyUI/main-ui/devices/gkd/gkd350hultra-system.json` | `darkmoss/json/pixel2-darkmoss-system.json` (same content) | PyUI's defaults for a fresh card (`SYSTEM_JSON_DEFAULT`); the platform used to point at the Pixel 2's file. |
| `Emu/NDS/config/drastic-GKD350HUltra.cfg` (and `.bak`) | the Miniloong's | This pad's d-pad (b12-b15), touch press on L3. |
| `Emu/PSP/default_configs/SYSTEM/ppsspp-GKD350HUltra.ini`, `controls-GKD350HUltra.ini` | the E5 Plus's config, the H700 controls layout | The positional pad map. |
| `Emu/SATURN/pad/keymap-GKD350HUltra.json`, `es-GKD350HUltra.xml` | the Miniloong layout | The d-pad on b12-b15; written by hand from the measured pad and checked on the device (spruce's generator for that folder doesn't know this platform folder: keep them when it regenerates). |
| `Emu/N64/mupen64plus/pad/InputAutoCfg-GKD350HUltra.ini` | the Anbernic one-stick layout | This pad's raw numbers. |
| `Emu/DC/default_configs/flycast/pads/GKD350HUltra/` | (own) | Positional A/B/X/Y, L1/R1 as Z/C, L2/R2 as the triggers. |
| `RetroArch/platform/retroarch-GKD350HUltra.cfg.bak`, `RetroArch/.retroarch/autoconfig/linuxraw/gkd_atom_joypad.cfg` | (own) | This pad under RetroArch's linuxraw driver (no udevd). |

## Where this platform still edits shared files, and why

Only where spruce has no per-platform mechanism, each change used by this platform alone:

- **Device lists** (`Emu/*/config.json`, `App/*/config.json`): `BASEDOS` added where a system or app is
  checked on the device. This is spruce's mechanism for listing.
- **Per-platform branches** spruce already has for other platforms: `helperFunctions.sh` (detection,
  `device_names`, `baseos_repo`), `App/PyUI/launch.sh`, `App/Gallery/launch.sh`,
  `App/PixelReader/launch.sh`, `spruce/portmaster/portmaster.txt`, the DraStic, Flycast, Mupen and PPSSPP
  launch functions (`emu/lib/*_functions.sh`), `App/-FirmwareUpdate-/baseosUpdate.sh`.
- **`emu/standard_launch.sh`'s PORTS arm** calls `run_basedos_port` for `PLATFORM_FAMILY` basedos: spruce
  has no per-platform hook for ports (the A30 has its own Emu system, A30PORTS, instead), so this one
  dispatch line is the minimum. For the maintainers to fold in as they see fit.
- **`platform/README.md`**: the BasedOS section.

## Put back to upstream's

- `darkmoss/dArkMossCommon.sh`, `h700/AnbernicXXCommon.sh`, `utils/sleep_functions.sh`,
  `runtimeHelper.sh`, and `utils/spruce_system_user.sh` removed: see the hooks above.
- **Mupen64Plus's Rice and Glide64mk2 plugins** (`Emu/N64/mupen64plus/*.so`): spruce's binaries, used by
  every device. The fork had rebuilt them with `M64P_VIEWPORT_Y` from theycallmeboxy/mupen64plus-spruce,
  whose pull request isn't merged; until it is, N64 games under those two plugins sit at the bottom of this
  panel (the Mupen launch arm still sets the variable, which spruce's plugins ignore).
- `Emu/SATURN/pad/README.md`: the note about this platform's hand-written pad files is in this file now
  (the table above).
