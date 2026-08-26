# HealthKit Entitlement Enforcement Study

Empirically maps **where iOS enforces the `com.apple.developer.healthkit` entitlement** for
free-provisioned (Personal Team) signing, and documents which parts of HealthKit are reachable
without a paid Apple Developer Program membership.

## Layout
- `probe/` — minimal SwiftUI probe app (staged: INIT → IS_AVAILABLE → REQUEST_AUTH → QUERY)
  - `Entitlements/baseline.entitlements` — empty dict
  - `Entitlements/healthkit.entitlements` — claims `com.apple.developer.healthkit`
- `.github/workflows/build.yml` — unsigned device build, codesign-tolerance demo, simulator control run
- `scripts/inspect_app.sh` — dump bundle id / entitlements blob / profile / signature flags
- `scripts/device_install_test.sh` — install via pymobiledevice3 + capture installd verdict & syslog

## Method summary
1. Build probe **unsigned** in CI (no Apple account involved).
2. Locally re-sign variants with a freshly minted **free-tier** identity:
   - V0 baseline (entitlements: none)
   - V1 injected (entitlements: healthkit) — profile does *not* authorize it
   - V2 negative control (broken signature)
3. Install each on-device; capture exact rejection layer/code.
4. Launch-layer evidence: revoke cert → relaunch previously-installed app.
5. LiveContainer guest test: same binary runs under host process entitlements.
6. Simulator control: same code path succeeds with zero signing.

## Findings
See `docs/findings.md`.

## Ethics & scope
Own devices only; no security mechanisms are bypassed or weakened. Every "failure" recorded is
Apple's enforcement working as designed.
