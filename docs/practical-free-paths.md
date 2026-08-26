# Getting value from Apple Health without a paid developer account

The research above proves no sideloaded/free-signed **app** can touch HealthKit on real
hardware. But your actual goals — *export steps, write sleep entries* — are fully achievable
free of charge through Apple's own entitled surfaces:

## 1. Shortcuts (personal automation, zero cost, fully supported)

Shortcuts runs inside Apple's own process and has native Health read/write actions.

### Export steps
1. Shortcuts ▸ **+** ▸ name it `Export Steps`
2. Add action **Find Health Samples**
   - Type: `Steps` · Limit: e.g. `1,000` · Sort: End Date ▸ Latest First
3. Add action **Repeat with Each** (over the samples)
   - inside: **Get Details of Health Sample** ▸ `Value` and `End Date`
   - **Text** action: `[End Date] [Value]` (one line per step sample)
4. Add **Append to Text File** ▸ path in Files (e.g. `Exports/steps.csv`)
5. Optional: **Automation ▸ Personal ▸ Time of Day** → run daily automatically.

### Import sleep entries ("fake sleep")
1. New shortcut `Log Sleep`
2. **Adjust Date** (Current Date, offset −8 h) → Start · another for End
3. **Log Health Sample**
   - Type: `Sleep Analysis` · Value: `Asleep (Core)`
   - Start/End wired from the Adjust Date actions
4. Run it whenever; chain multiple Adjust/Log pairs for multiple sessions.

### What Shortcuts can read vs write
| Direction | Action | Types |
|---|---|---|
| read | Find Health Samples | everything Health stores (steps, sleep, HR, weight, workouts, …) |
| write | Log Health Sample | sleep analysis, weight/body measurements, nutrition & water, many vitals |
| write | Log Workout | workouts (type, distance, duration, kcal) |
| ✗ write | steps | system-derived from motion coprocessor — cannot be injected |
| ✗ | clinical records / ECG | not exposed to Shortcuts |

Entries are attributed to source **Shortcuts** (visible in Health ▸ Show All Data) and cannot
be disguised — provenance enforcement mirrors the app-side story in this study.

Notes:
- First run asks for Health write/read permission once — that's Shortcuts' own entitlement,
  no developer account involved.
- Everything stays on-device unless an upload/share action is added (Files, ownCloud, HTTP…).

## 2. iOS Simulator (for *developing* your app)
`xcodebuild`-built apps run against HealthKit fully in the Simulator with zero signing —
already proven in this repo's CI (`simulator-control` job). Use it for all DanPlan
development/debugging; only device testing needs the paid tier.

## 3. Shipping DanPlan
Any distribution path for a HealthKit app (App Store, TestFlight, ad-hoc to customers)
requires the **$99/yr** Apple Developer Program membership. Your code is already correct —
`HealthKitManager`, usage strings, entitlement — the *only* missing piece is paid signing.

## What does NOT work (proven in this study)
| Attempt | Outcome |
|---|---|
| SideStore / AltStore / Sideloadly / iLoader signing | profile can't contain HealthKit |
| Injecting `com.apple.developer.healthkit` into the binary | `0xe8008015` at install |
| LiveContainer guest | host process entitlements apply → HealthKit absent |
| Signing on Linux with the real free identity | identical rejection (this repo's V1) |
