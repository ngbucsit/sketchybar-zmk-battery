# sketchybar-zmk-battery

Shows the battery levels of a ZMK split keyboard in [SketchyBar](https://github.com/FelixKratz/SketchyBar), with the central half always in the same position.

It reads the levels over Bluetooth LE with CoreBluetooth. The central's own level and each peripheral's level are told apart by the descriptors ZMK attaches to them. Order in `pmset` output is never used, so the halves can't swap. Works with any ZMK board/MCU.

## Requirements

Enable battery reporting and the central's peripheral battery proxy in your ZMK config:

```
CONFIG_ZMK_BATTERY_REPORTING=y
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y
```

## Install

```sh
swift build -c release
cp .build/release/sketchybar-zmk-battery ~/.local/bin/
```

## Usage

In `sketchybarrc`:

```sh
sketchybar --add item kb_batt right --set kb_batt icon=󰌌 width=100
pkill -x sketchybar-zmk-battery; sketchybar-zmk-battery &
```

The daemon finds the keyboard among connected Bluetooth devices and sets the item's label, e.g. `85% | 62%`. It updates only when a level changes and shows `--%` while the keyboard is disconnected. On first run, macOS asks for Bluetooth permission.

| Option | Default | |
|---|---|---|
| `--item NAME` | `kb_batt` | SketchyBar item to update |
| `--device NAME` | auto-detect | Match the keyboard by Bluetooth name. Needed for non-split boards |
| `--central left\|right` | `left` | Side of the label the central half is shown on |
| `--separator STR` | `" \| "` | Text between levels |
| `--sketchybar PATH` | search `PATH` | Location of the `sketchybar` binary |
| `--list` | | Print detected devices and their levels, then exit |
| `--once` | | Print the label once, then exit |
| `--verbose` | | Log Bluetooth activity to stderr |
