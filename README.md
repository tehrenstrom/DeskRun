# DeskRun

**Open-source macOS menu bar app for controlling DeerRun (PitPat) walking treadmills.**

DeskRun is built for people who walk while they work. It connects to your under-desk treadmill over Bluetooth Low Energy and gives you speed controls, live stats, goal tracking, and workout history — all from your menu bar. No need to reach for your phone or switch apps.

## Features

### Menu Bar Control Center
Speed controls, start/stop, and live stats right from the menu bar. Adjust your pace without leaving your workflow.

### BLE Treadmill Control
Connects to DeerRun/PitPat treadmills over Bluetooth Low Energy. Start, stop, pause, and adjust speed directly from your Mac.

### Goal Tracking
Set daily, weekly, monthly, or yearly goals for distance, time, or steps. Track progress with visual indicators and stay motivated with streak tracking.

### Journey Mode
Pick a real-world trail and watch your daily miles accumulate along it:
- Pacific Crest Trail (2,650 mi)
- Appalachian Trail (2,190 mi)
- Camino de Santiago (500 mi)
- Walk Across America (2,800 mi)
- Around the World (24,901 mi)
- Custom journeys with your own distance targets

### Auto-Recording
Workouts start and stop automatically based on treadmill activity. No buttons to press — just walk.

### Smart Notifications
Morning motivation, goal nudges, streak alerts, and milestone celebrations. Rate-limited so they help without getting annoying. Fully configurable.

### Workout History & Streaks
Full log of every session with distance, time, steps, and calories. Consecutive day streaks to keep you coming back.

## Supported Treadmills

| Model | Status |
|-------|--------|
| DeerRun Urban Pro Plus (PitPat-T01) | ✅ Confirmed |
| Other PitPat-compatible treadmills | 🔬 Untested — contributions welcome |

If you have a different treadmill model and can capture BLE traffic, we'd love help expanding device support.

## Requirements

- macOS 14.0 (Sonoma) or later
- Bluetooth Low Energy
- Xcode 15+ (to build from source)

## Building

```bash
git clone https://github.com/travisehrenstrom/DeskRun.git
cd DeskRun
open DeskRun.xcodeproj
```

1. Set your Development Team under **Signing & Capabilities**
2. Build and run (`⌘R`)

The app requires Bluetooth permissions. macOS will prompt you on first launch.

## Architecture

```
DeskRun/
├── BLE/
│   ├── PitPatProtocol.swift      # BLE command encoding/decoding
│   └── TreadmillBLEManager.swift # CoreBluetooth connection management
├── Models/
│   ├── AppSettings.swift         # User preferences
│   ├── AppState.swift            # Global app state
│   ├── Goal.swift                # Goal type definitions
│   ├── GoalManager.swift         # Goal tracking logic
│   ├── NotificationManager.swift # Smart notification scheduling
│   ├── StatsCalculator.swift     # Workout statistics
│   ├── WorkoutRecord.swift       # Workout data model
│   ├── WorkoutRecorder.swift     # Auto-recording logic
│   └── WorkoutStore.swift        # Persistence
├── Views/
│   ├── MenuBarView.swift         # Menu bar popover
│   ├── DashboardView.swift       # Main dashboard
│   ├── GoalsView.swift           # Goal management UI
│   ├── HistoryView.swift         # Workout history
│   ├── ConnectionView.swift      # BLE connection status
│   └── SettingsView.swift        # App settings
└── DeskRunApp.swift              # App entry point
```

**Tech stack:** Swift, SwiftUI, CoreBluetooth, SwiftUI Charts

## BLE Protocol

DeskRun communicates with PitPat-compatible treadmills using a proprietary BLE protocol. The protocol was reverse-engineered from these projects:

- [pitpat-treadmill-control](https://github.com/azmke/pitpat-treadmill-control) — Python implementation of the PitPat BLE protocol
- [pacekeeper](https://github.com/peteh/pacekeeper) — ESP32-based treadmill controller

## Status

DeskRun is in early development:

- ✅ BLE connection and device discovery
- ✅ Treadmill start/stop/speed control
- ✅ Menu bar UI with live stats
- ✅ Goal system (daily/weekly/monthly/yearly)
- ✅ Journey mode with real trails
- ✅ Auto-recording and workout history
- ✅ Smart notifications
- ✅ Streak tracking
- 🔄 Speed calibration refinement
- 📋 HealthKit sync
- 📋 Map visualization for journeys
- 📋 Additional treadmill brand support

## Contributing

Contributions are welcome! Here's how you can help:

1. **Test with your treadmill** — If you have a PitPat-compatible treadmill, try DeskRun and report how it works.
2. **Add treadmill support** — Capture BLE traffic from other treadmill brands and help implement new protocols.
3. **Report bugs** — Open an issue with steps to reproduce.
4. **Submit PRs** — Fork the repo, create a feature branch, and submit a pull request.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

Travis Ehrenstrom
