# sketchybar-zmk-battery

Shows the battery levels of a ZMK split keyboard in [SketchyBar](https://github.com/FelixKratz/SketchyBar):

```
󰌌 85% | 62%
   │      └─ peripheral half
   └─ central half (always first, unless you choose otherwise)
```

Scripts based on `pmset -g accps` can't tell the halves apart, because macOS lists them in no fixed order. This tool reads the levels over Bluetooth LE instead. ZMK's central half labels every peripheral level it forwards as "Peripheral N", so the halves never swap.

It runs as a small background process. It updates the bar only when a level changes, never scans for devices, and uses ~0% CPU and a few MB of memory. It works with any ZMK keyboard that connects over Bluetooth, whatever its MCU or board.

## Requirements

- macOS 13 or later
- SketchyBar
- Swift 6 toolchain: `xcode-select --install` (Command Line Tools) or Xcode
- A ZMK keyboard paired with your Mac over Bluetooth (not a USB connection)

## 1. Enable battery reporting in your ZMK firmware

Add these lines to your keyboard's `.conf` file in your `zmk-config` (e.g. `config/lily58.conf`):

```
CONFIG_ZMK_BATTERY_REPORTING=y
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y
```

Rebuild and flash **both halves**. Then remove the keyboard from **System Settings › Bluetooth** and pair it again, so macOS picks up the new Bluetooth services.

> The last two options are what let the plugin tell the halves apart. Without them only the central half's level is available.

## 2. Build and install

```sh
git clone https://github.com/ngbucsit/sketchybar-zmk-battery.git
cd sketchybar-zmk-battery
swift build -c release
mkdir -p ~/.local/bin
cp .build/release/sketchybar-zmk-battery .build/release/sketchybar-zmk-battery-graph ~/.local/bin/
```

## 3. Check that your keyboard is detected

With the keyboard on and connected, run:

```sh
~/.local/bin/sketchybar-zmk-battery --list
```

On first run, macOS asks to allow Bluetooth access for your terminal; allow it. You should see something like:

```
Lily58 [6D505B1A-…] (selected)
  central: 31%
  peripheral 0: 59%
```

Other Bluetooth devices that report a battery level (mice, headphones) may be listed too. Only the entry marked `(selected)` appears in the bar.

## 4. Add it to SketchyBar

Add this to `~/.config/sketchybar/sketchybarrc`. If you already have a keyboard battery item, replace it, along with any `script=`/`update_freq=` that polls `pmset`:

```sh
sketchybar --add item kb_batt right \
           --set kb_batt icon="󰌌" width=100 \
                 click_script='pkill -x sketchybar-zmk-battery-graph || "$HOME/.local/bin/sketchybar-zmk-battery-graph" &'

# Restart the daemon on every config reload so only one copy runs.
pkill -x sketchybar-zmk-battery
"$HOME/.local/bin/sketchybar-zmk-battery" --item kb_batt &
```

Use the full path: SketchyBar started by `brew services` usually doesn't have `~/.local/bin` on its `PATH`. Style the item (icon, font, colors, padding) like any other SketchyBar item. The daemon only sets the label.

Reload:

```sh
sketchybar --reload
```

macOS may ask once more for Bluetooth access, this time for SketchyBar, because SketchyBar starts the daemon. Allow it.

## Battery history graph

Click the item to open a graph of recent battery levels: central on top, each peripheral below. The Y axis runs 0–100% in steps of 25. The X axis shows 7 ticks ending at now, spaced 30 minutes apart by default. Press ← / → to switch between 15m, 30m and 2h spacing (1.5, 3 or 12 hours of history). Gaps show when the keyboard was disconnected. Click the item again, click anywhere else, or press Esc to close it. The window copies your bar's `color`, `blur_radius`, `corner_radius`, border and `shadow`, read from `sketchybar --query bar` when it opens.

The `click_script` above opens it. The daemon records each level change to `~/Library/Application Support/sketchybar-zmk-battery/history.jsonl` and keeps 24 hours. History builds up from when you first start the daemon.

The graph is a separate program, `sketchybar-zmk-battery-graph`, which runs only while the window is open. That keeps the daemon free of UI frameworks. To render the graph to an image without opening a window:

```sh
sketchybar-zmk-battery-graph --snapshot graph.png              # default 30m spacing
sketchybar-zmk-battery-graph --snapshot graph.png --interval 15m
```

## Options

| Option | Default | Description |
|---|---|---|
| `--item NAME` | `kb_batt` | SketchyBar item whose label is updated |
| `--central left\|right` | `left` | Side of the label the central half appears on |
| `--device NAME` | auto-detect | Pick the keyboard by Bluetooth name (case-insensitive substring). Required for non-split keyboards |
| `--separator STR` | `" \| "` | Text between levels |
| `--sketchybar PATH` | search `PATH` | Location of the `sketchybar` binary |
| `--list` | | Print detected devices and their levels, then exit |
| `--once` | | Print the label once and exit (for scripts) |
| `--verbose` | | Log Bluetooth activity to stderr |

Examples:

```sh
# Central half on the right
sketchybar-zmk-battery --central right &

# Non-split keyboard, or several ZMK keyboards connected at once
sketchybar-zmk-battery --device "Corne" &
```

### What gets shown

| Setup | Label |
|---|---|
| Split keyboard | `central% \| peripheral%` |
| Split with a dongle (dongle has no battery) | `peripheral0% \| peripheral1%`, in the order the halves were paired to the dongle |
| More than two parts | central, then `Peripheral 0`, `Peripheral 1`, … |
| Non-split keyboard (needs `--device`) | `level%` |
| Keyboard disconnected or asleep | `--% \| --%`; levels return automatically when it reconnects |

## Troubleshooting

Run with `--verbose` to see what the daemon finds:

```sh
pkill -x sketchybar-zmk-battery
~/.local/bin/sketchybar-zmk-battery --verbose --item kb_batt
```

**`No connected Bluetooth device exposes battery levels`**: make sure the keyboard is connected over Bluetooth (not USB) and that `CONFIG_ZMK_BATTERY_REPORTING=y` is set. If you just changed the firmware, remove the keyboard in System Settings and pair it again.

**The keyboard is listed but only shows `central`**: the peripheral battery proxy isn't enabled. Add the two `CONFIG_ZMK_SPLIT_BLE_CENTRAL_*` options above and flash both halves. Until then, use `--device NAME` to show just the central level.

**`Bluetooth access denied`**: enable the app that started the daemon (your terminal and/or SketchyBar) in **System Settings › Privacy & Security › Bluetooth**.

**`sketchybar not found`**: pass its location, e.g. `--sketchybar /opt/homebrew/bin/sketchybar`.

**The bar stays at `--% | --%`**: check that the item name in `--item` matches the item in your `sketchybarrc`, and that only one copy is running (`pgrep -l sketchybar-zmk-battery`).

**`swift build` fails with "Unknown error parsing property list"**: some Swift 6.4 toolchains hit this. It isn't caused by this package. Build with the legacy build system instead:

```sh
swift build -c release --build-system native
```

## Uninstall

```sh
pkill -x sketchybar-zmk-battery
rm ~/.local/bin/sketchybar-zmk-battery ~/.local/bin/sketchybar-zmk-battery-graph
rm -r ~/Library/Application\ Support/sketchybar-zmk-battery
```

Then remove the `kb_batt` lines from your `sketchybarrc`.

## Development

```sh
swift test
```

- `Sources/ZMKBatteryCore`: classification, label formatting, flag parsing and history. This is the pure logic, and it is unit-tested.
- `Sources/sketchybar-zmk-battery`: the daemon (CoreBluetooth and SketchyBar).
- `Sources/sketchybar-zmk-battery-graph`: the history window (AppKit, SwiftUI and Swift Charts).
