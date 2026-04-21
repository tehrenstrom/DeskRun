# DeskRun

**Open-source macOS menu bar app for controlling your walking treadmill — now with multi-brand support.**

> *You have mass-produced a treadmill desk setup. Your party gains +2 productivity. The trail ahead is long, but your legs are ready.*

DeskRun is built for people who walk while they work. It connects to your under-desk treadmill over Bluetooth Low Energy and gives you speed controls, live stats, goal tracking, and workout history — all from your menu bar. No need to reach for your phone or switch apps. No need to ford the river on foot.

## Features

### Menu Bar Control Center
Speed controls, start/stop, and live stats right from the menu bar. Adjust your pace without leaving your workflow. It's like having a wagon master in your system tray.

### BLE Treadmill Control
Connects to treadmills across four protocol families over Bluetooth Low Energy. Start, stop, pause, and adjust speed directly from your Mac.

### Goal Tracking
Set daily, weekly, monthly, or yearly goals for distance, time, or steps. Track progress with visual indicators and stay motivated with streak tracking. Every mile marker counts.

### Journey Mode
Pick a real-world trail and watch your daily miles accumulate along it:
- **Pacific Crest Trail** (2,650 mi)
- **Appalachian Trail** (2,190 mi)
- **Camino de Santiago** (500 mi)
- **Walk Across America** (2,800 mi)
- **Around the World** (24,901 mi)
- Custom journeys with your own distance targets

Your desk is Independence, Missouri. The finish line is wherever you point it.

### Auto-Recording
Workouts start and stop automatically based on treadmill activity. No buttons to press — just walk.

### Smart Notifications
Morning motivation, goal nudges, streak alerts, and milestone celebrations. Rate-limited so they help without getting annoying. Fully configurable. Think of them as friendly notes from the general store.

### Workout History & Streaks
Full log of every session with distance, time, steps, and calories. Consecutive day streaks to keep you coming back. Don't let the trail go cold.

## Supported Treadmills

DeskRun v2 speaks four protocol families. If your treadmill shows up over Bluetooth, there's a good chance we've got a wagon hitched for it.

### DeerRun / PitPat
| Brand / Model | BLE Name | Status |
|---|---|---|
| DeerRun Urban Pro Plus | `PitPat-T01` | ✅ Confirmed |
| Other PitPat-compatible treadmills | `PitPat-*` | 🔬 Community-tested |

### KingSmith / WalkingPad
| Brand / Model | BLE Name | Status |
|---|---|---|
| WalkingPad R1, R2 | `WalkingPad` | ✅ Confirmed |
| WalkingPad A1, C2 | `WalkingPad` | ✅ Confirmed |
| Other KingSmith models | `KS-*` | 🔬 Community-tested |

### FTMS (Bluetooth Fitness Machine Service)
The industry standard. If your treadmill advertises the FTMS service UUID, DeskRun will pick it up automatically.

| Brand | Status |
|---|---|
| LifeSpan | ✅ Confirmed |
| Horizon | ✅ Confirmed |
| NordicTrack | 🔬 Community-tested |
| Any FTMS-compliant treadmill | 🔬 Should work — let us know! |

### FitShow / Budget Brands
A whole wagon train of affordable under-desk treadmills speak the FitShow protocol.

| Brand | BLE Name | Status |
|---|---|---|
| UREVO | `FS-*` | ✅ Confirmed |
| Goplus / SuperFit | `FS-*` | 🔬 Community-tested |
| REDLIRO | `FS-*` | 🔬 Community-tested |
| Costway | `SW*` | 🔬 Community-tested |
| UMAY | `FS-*` | 🔬 Community-tested |
| Sperax | `FS-*` | 🔬 Community-tested |
| Egofit | `DB-*` | 🔬 Community-tested |
| AIRHOT | `MERACH-*` | 🔬 Community-tested |
| Other FitShow-compatible | `FS-*`, `SW*`, `MERACH-*`, `DB-*`, `XQIAO-*` | 🔬 Contributions welcome |

Don't see your treadmill? Open an issue with the BLE name and we'll help you scout the trail.

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

DeskRun uses an **adapter pattern** to support multiple treadmill brands through a single interface. Each protocol family gets its own adapter that conforms to the `TreadmillAdapter` protocol, and a central `TreadmillAdapterRegistry` handles discovery and instantiation. Adding a new brand is like adding a new wagon to the train — build it to spec and hitch it up.

```
DeskRun/
├── BLE/
│   ├── TreadmillProtocol.swift        # TreadmillAdapter protocol definition
│   ├── TreadmillAdapterRegistry.swift # Registry — matches BLE devices to adapters
│   ├── TreadmillBLEManager.swift      # CoreBluetooth connection management
│   ├── PitPatProtocol.swift           # Legacy PitPat command encoding/decoding
│   └── Adapters/
│       ├── PitPatAdapter.swift        # DeerRun / PitPat protocol
│       ├── KingSmithAdapter.swift     # KingSmith / WalkingPad protocol
│       ├── FTMSAdapter.swift          # Bluetooth FTMS standard
│       └── FitShowAdapter.swift       # FitShow / budget brand protocol
├── Models/
│   ├── AppSettings.swift              # User preferences
│   ├── AppState.swift                 # Global app state + adapter registration
│   ├── Goal.swift                     # Goal type definitions
│   ├── GoalManager.swift              # Goal tracking logic
│   ├── NotificationManager.swift      # Smart notification scheduling
│   ├── StatsCalculator.swift          # Workout statistics
│   ├── WorkoutRecord.swift            # Workout data model
│   ├── WorkoutRecorder.swift          # Auto-recording logic
│   └── WorkoutStore.swift             # Persistence
├── Views/
│   ├── MenuBarView.swift              # Menu bar popover
│   ├── DashboardView.swift            # Main dashboard
│   ├── GoalsView.swift                # Goal management UI
│   ├── HistoryView.swift              # Workout history
│   ├── ConnectionView.swift           # BLE connection status
│   └── SettingsView.swift             # App settings
└── DeskRunApp.swift                   # App entry point
```

**Tech stack:** Swift, SwiftUI, CoreBluetooth, SwiftUI Charts

## BLE Protocols

DeskRun communicates with treadmills using four protocol families. The PitPat protocol was reverse-engineered from these projects:

- [pitpat-treadmill-control](https://github.com/azmke/pitpat-treadmill-control) — Python implementation of the PitPat BLE protocol
- [pacekeeper](https://github.com/peteh/pacekeeper) — ESP32-based treadmill controller

The FTMS adapter implements the official [Bluetooth Fitness Machine Service](https://www.bluetooth.com/specifications/specs/fitness-machine-service-1-0/) specification. KingSmith and FitShow protocols were reverse-engineered from BLE traffic captures.

## Status

- ✅ BLE connection and multi-brand device discovery
- ✅ Treadmill start/stop/speed control
- ✅ Menu bar UI with live stats
- ✅ Goal system (daily/weekly/monthly/yearly)
- ✅ Journey mode with real trails
- ✅ Auto-recording and workout history
- ✅ Smart notifications
- ✅ Streak tracking
- ✅ Multi-brand support (PitPat, KingSmith, FTMS, FitShow)
- 🔄 Speed calibration refinement
- 📋 HealthKit sync
- 📋 Map visualization for journeys

## Contributing

Contributions are welcome! The trail is better with company.

### Test With Your Treadmill
If you have any Bluetooth treadmill, try DeskRun and report how it works. Even a "it showed up but didn't connect" is valuable intel.

### Add a New Treadmill Adapter
Got a treadmill that speaks a protocol we don't support yet? Here's how to blaze that trail:

1. **Create your adapter** — Add a new file in `DeskRun/BLE/Adapters/` (e.g., `YourBrandAdapter.swift`). Conform to the `TreadmillAdapter` protocol defined in `TreadmillProtocol.swift`.
2. **Register it** — Add your adapter to the registry in `AppState.swift` so DeskRun knows to try it during discovery.
3. **Update the project** — Add your new file to `DeskRun.xcodeproj/project.pbxproj` (Xcode handles this if you create the file through the IDE).
4. **Submit a PR** — Include any BLE traffic captures or protocol notes that might help future travelers.

### Report Bugs
Open an issue with steps to reproduce. Bonus points for BLE logs.

### Submit PRs
Fork the repo, create a feature branch, and submit a pull request. Keep commits focused and descriptions clear.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Author

Travis Ehrenstrom

---

*The trail is long. The desk is steady. Keep walking.*
