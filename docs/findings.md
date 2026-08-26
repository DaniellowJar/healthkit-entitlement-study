# Findings

## Enforcement-layer matrix (hypothesis vs observed)

| # | Layer | Mechanism | Experiment | Hypothesis | Observed |
|---|-------|-----------|------------|------------|----------|
| 1 | IDE / portal | App-ID capability allow-list per team type | n/a (no Mac) — inferred from minted profile contents | Free (Personal) teams cannot register HealthKit capability; profile can never contain `com.apple.developer.healthkit` | _pending_ |
| 2 | `codesign` CLI | None — signs any entitlements blob it is given | CI `codesign-tolerance-demo` job | Exit 0, entitlement embedded silently | **CONFIRMED**: job green; `codesign --force -s - --entitlements hk.entitlements` exit 0, blob verifiable via `codesign -d --entitlements :-`; no profile consulted |
| 3 | Install (`installd`) | Binary entitlements ⊄ profile entitlements ⇒ reject | Install V1 via pymobiledevice3 | Rejection with `0xe8008xxx` family ("not entitled"/"invalid entitlements") | _pending_ |
| 4 | Launch (AMFI/kernel) | Entitlements/profile re-checked at exec; profile validity & cert chain | Cert revocation relaunch test | SIGKILL (Code Signature Invalid), AMFI syslog lines | _pending_ |
| 5 | `HKHealthStore.isHealthDataAvailable()` | Returns NO on device when process lacks healthkit entitlement | V0 runtime probe | `false` on device; `true` in Simulator | _pending_ |
| 6 | `requestAuthorization()` / data access | healthd checks peer entitlement per connection | Only reachable in Simulator w/o paid acct | Works in Simulator; unreachable on device sans entitlement | _pending_ |

## Specimen: user app "Dan's Plan" (`work.danieltuma.plan`)
- Binary embeds entitlements blob claiming `com.apple.developer.healthkit`, CERT-SIGNED flags=0x0,
  CMS blob present, **no embedded.mobileprovision** → predicted outcome at install: layer-3 rejection
  (or launch kill if a stale/mismatched profile is attached).
- Observed: _pending_

## Simulator control (CI run 32915832097 / 32916164824)
Baseline build (no entitlements file, no profile, unsigned):
```
PROBE|INIT|PASS|HKHealthStore instance created
PROBE|IS_AVAILABLE|RUN|isHealthDataAvailable() == true
PROBE|REQUEST_AUTH|FAIL|error: Missing com.apple.developer.healthkit entitlement.
PROBE|DONE
```
- Layer-5 (`isHealthDataAvailable`) **not gated** in Simulator (returns true sans entitlement).
- Layer-6 (`requestAuthorization`) **gated even in Simulator** with explicit error text — a runtime
  API-level check independent of provisioning profiles. Error string is a reusable detector.

## LiveContainer guest test (real hardware, iPad14,1 / iOS 27.0b)
Unsigned probe ipa loaded as LiveContainer guest (guest code executes under LC host's entitlements):
```
INIT          PASS
IS_AVAILABLE  isHealthDataAvailable() == false   ← on-device, no entitlement anywhere in process
REQUEST_AUTH  skipped/FAIL
QUERY         skipped/FAIL
```
- Layer-5 IS gated on real hardware: `isHealthDataAvailable() == false` without a healthkit-entitled
  process — while the identical unsigned binary returns `true` in Simulator.
- Confirms entitlement evaluation is **process-scoped at exec time** (kernel/AMFI), not bundle-scoped:
  a guest app cannot "bring its own" HealthKit rights into an unentitled host process.

## Free-tier reality check
- Personal-team profiles minted via AltServer/iLoader/SideStore contain no restricted capabilities.
- HealthKit on physical hardware requires paid membership ($99/yr). No documented legitimate bypass.
- Documented no-cost paths: iOS **Simulator** (full API, synthetic data) and **Shortcuts**
  (system app; native Read/Write Health actions without third-party entitlements).
