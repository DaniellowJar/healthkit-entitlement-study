# Findings

## Enforcement-layer matrix (hypothesis vs observed)

| # | Layer | Mechanism | Experiment | Hypothesis | Observed |
|---|-------|-----------|------------|------------|----------|
| 1 | IDE / portal | App-ID capability allow-list per team type | SideStore-generated profile dumped off device | Free (Personal) teams cannot register HealthKit capability; profile can never contain `com.apple.developer.healthkit` | **CONFIRMED**: actual profile contains only `application-identifier`, `keychain-access-groups`, `get-task-allow`, `com.apple.developer.team-identifier`; expires in exactly 7 days |
| 2 | `codesign` CLI | None — signs any entitlements blob it is given | CI `codesign-tolerance-demo` job | Exit 0, entitlement embedded silently | **CONFIRMED**: job green; `codesign --force -s - --entitlements hk.entitlements` exit 0, blob verifiable via `codesign -d --entitlements :-`; no profile consulted |
| 3a | Install (`installd`) — trust gate | Signature must chain to Apple CA before any entitlement logic | Install unsigned/ad-hoc/corrupt/DanPlan specimens via pymobiledevice3 | Rejection before entitlement evaluation | **CONFIRMED**: all four → `ApplicationVerificationFailed: Failed to verify code signature` |
| 3b | Install (`installd`) — entitlement gate | Binary entitlements ⊄ profile entitlements ⇒ reject | Install V1 (real free cert + injected HK entitlement, profile-identical control passing) | Rejection with `0xe8008xxx` family | **CONFIRMED**: `0xe8008015 (A valid provisioning profile for this executable was not found.)` — iOS's code for entitlement∉profile at install; identical-signature V0 without the claim installs rc=0 |
| 4 | Launch (AMFI/kernel) | Entitlements/profile re-checked at exec; profile validity & cert chain | Not independently triggerable on stock iOS: the install gate (3b) preempts every binary that would fail at exec | SIGKILL (Code Signature Invalid) expected at exec for mismatched/invalid profiles | **Structurally preempted** — reachable only via post-install profile invalidation (e.g. the 7-day expiry on 2026-09-02: relaunching HealthProbe after expiry should yield the AMFI SIGKILL; left as a scheduled follow-up). See Apple Platform Security "code signing" / AMFI |
| 5 | `HKHealthStore.isHealthDataAvailable()` | Availability probe | Three runtime contexts | — | **MEASURED**: Simulator `true`; properly-installed device app (free profile, no HK ent.) `true`; LiveContainer guest `false` (containerization artifact — LC host process lacks expected process state, not iOS policy) ⇒ availability check does NOT consult HealthKit entitlement |
| 6 | `requestAuthorization()` / data access | healthd checks peer entitlement per connection | Same three contexts | Gate error | **CONFIRMED GATE**: `Missing com.apple.developer.healthkit entitlement.` — identical string on device and Simulator; nothing beyond this point reachable without a paid-membership-signed app |

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

## SideStore-installed probe (real hardware, 2026-08-26)
SideStore rewrites the bundle id, appending the Team ID: `work.danieltuma.healthprobe` →
`work.danieltuma.healthprobe.2V53L5T246`. Device report pulled over USB (house_arrest):
```
INIT          PASS
IS_AVAILABLE  isHealthDataAvailable() == true
REQUEST_AUTH  FAIL|error: Missing com.apple.developer.healthkit entitlement.
```

## Installd trust-gate specimens (2026-08-26)
Four install attempts via `pymobiledevice3 apps install`, all rejected before entitlement logic:
| Specimen | Signature state | Result |
|---|---|---|
| V-adhoc | ad-hoc signed (`rcodesign`), no entitlements | `ApplicationVerificationFailed: Failed to verify code signature` |
| V-corrupt | ad-hoc + flipped byte in CodeDirectory | same |
| DanPlan (user app) | CMS blob from unknown/non-Apple-chained signer, claims healthkit | same |
| unsigned CI build | no signature at all | same |

⇒ Entitlement-vs-profile comparison is only reachable with a signature chaining to Apple's
WWDR infrastructure (free or paid dev cert). Untrusted chains fail earlier and generically.

## THE decisive experiment (2026-08-26 14:3x local)
Signing identity: free-tier cert `iPhone Developer: service.beta.mail@gmail.com (CANY6CCCMD)`,
serial 375B1927…, minted by Sideloadly, key exported from its cache; profile = SideStore/
Sideloadly-generated `iOS Team Provisioning Profile: work.danieltuma.healthprobe.2V53L5T246`
(expires 2026-09-02, embeds both account certs). Signed on Linux with `rcodesign`, entitlements
dict merged from the profile (as Xcode does).

| Variant | Binary entitlements | Install result |
|---|---|---|
| V0-clean | profile dict only (app-id, keychain, get-task-allow, team-id) | **rc=0 "Installation succeed."** |
| V1-hkinject | profile dict **+ `com.apple.developer.healthkit`** | **rc=1 — `0xe8008015 (A valid provisioning profile for this executable was not found.)`** |
| V2-corrupt | V0 + flipped CodeDirectory byte | rc=1 `ApplicationVerificationFailed` |

⇒ Single-variable proof: the HealthKit entitlement claim alone triggers installd rejection.
iOS reports entitlement∉profile as `0xe8008015`; there is no path to launch, and therefore
none to `HKHealthStore`, with an unentitled profile.

## Free-tier reality check
- Personal-team profiles minted via AltServer/iLoader/SideStore contain no restricted capabilities.
- HealthKit on physical hardware requires paid membership ($99/yr). No documented legitimate bypass.
- Documented no-cost paths: iOS **Simulator** (full API, synthetic data) and **Shortcuts**
  (system app; native Read/Write Health actions without third-party entitlements).
