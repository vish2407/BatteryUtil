# BatteryUtil

A tiny macOS menu bar app that shows live battery stats — charge, power draw, voltage, current, and health — without opening System Settings.

## Features

- **Menu bar icon** that reflects charge level and charging state at a glance (uses the system `battery.*` SF Symbols, rendered as a template image so it matches the rest of the menu bar).
- **Click the icon** to open a compact popover with:
  - Battery percentage and a flat, Apple-style progress bar (green while charging, yellow/red at low charge, primary color otherwise)
  - Power draw (W), voltage (V), current (A)
  - Battery health (%), matching the "Maximum Capacity" figure under System Settings → Battery → Battery Health
  - Time to full charge
- **Launch at Login** toggle, right in the popover — no need to dig through System Settings.
- **Right-click the icon** for a Quit option (there's no Dock icon, so this is the only way to quit besides Activity Monitor).
- Live values refresh every 2 seconds while the popover is open, and stop polling when it's closed.

## Requirements

- macOS 13 (Ventura) or later — Apple Silicon or Intel
- Xcode 15+ to build

## Building & Running

1. Open `BatteryUtil.xcodeproj` in Xcode.
2. Select the **BatteryUtil** scheme.
3. Build and run (⌘R).

Or from the command line:

```bash
xcodebuild -project BatteryUtil.xcodeproj -scheme BatteryUtil -configuration Debug build
```

The app is a plain SwiftUI + AppKit menu bar agent — no external dependencies, no Package.swift/SwiftPM involved.

### Installing to /Applications

Xcode builds land in DerivedData, which gets wiped on clean builds — not a stable place for a "Launch at Login" item to point at. After building, copy the app somewhere permanent:

```bash
cp -R "$(xcodebuild -project BatteryUtil.xcodeproj -scheme BatteryUtil -configuration Debug -showBuildSettings 2>/dev/null | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/BatteryUtil.app" /Applications/
open /Applications/BatteryUtil.app
```

Then open the popover and check **Launch at Login** — it registers via `SMAppService`, so it'll relaunch automatically after every reboot.

## Usage

| Action | Result |
|---|---|
| Left-click the menu bar icon | Open/close the stats popover |
| Right-click the menu bar icon | Quit BatteryUtil |

## How it works

Battery data comes from two IOKit sources, read fresh on every poll:

- **`IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription`** — charge percentage, charging state, time-to-full.
- **The `AppleSmartBattery` IORegistry service** — voltage, current (amperage), and health (`BatteryData.NominalChargeCapacity` ÷ `BatteryData.DesignCapacity`, clamped to 100%).

Battery *temperature* isn't exposed by either API on all Macs — on hardware where it's missing, that stat was dropped in favor of Health, which is reliably available and more broadly useful.

## Project structure

```
BatteryUtil.xcodeproj/           Xcode project (macOS app target, file-system-synchronized group)
BatteryUtil/
  BatteryReader.swift            IOKit reading logic (BatteryState, BatteryReader)
  ContentView.swift              App entry point, status bar/popover UI, SwiftUI views
  Assets.xcassets/AppIcon.appiconset/   App icon (all required sizes)
```

## Known limitations

- Battery temperature isn't shown — see [How it works](#how-it-works) above.
- No sandboxing beyond what Xcode's default macOS app template applies; the app only reads IOKit power data, it doesn't write anything
