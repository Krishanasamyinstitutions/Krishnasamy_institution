# Performance Baselines

The plan in `C:\Users\User7\.claude\plans\purring-launching-hearth.md` Section 4
defines budgets for the user-visible flows. This file is the place to record
the measured numbers each release.

## Microbenchmarks (CI-checked)

`test/perf/formatters_perf_test.dart` runs under `flutter test` and fails
the build if any hot-path helper regresses by ≥ 10× from the baseline.

```cmd
flutter test test/perf/
```

| Helper | Baseline | Hard ceiling |
|---|---|---|
| `formatIndianNumber(1234567.89)` | ~0.5 µs | 5 µs |
| `parseAmount('₹1,23,456.78 Cr')` | ~1.0 µs | 5 µs |
| `toIsoDate('15/04/2026')` | ~0.5 µs | 3 µs |
| `normalizeReference(' utr-123/45 ')` | ~0.4 µs | 2 µs |

## Manual scenarios (record per release)

Run with `flutter run --profile -d windows` and capture timings via
DevTools → Performance tab. Update this table on every release:

| Scenario | Budget | Last measurement | Date | Notes |
|---|---|---|---|---|
| Cold start to login screen | < 4 s | — | — | timestamp launch → first frame |
| Login → Dashboard render | < 2 s | — | — | RPC return → dashboard pumped |
| Students list with 765 rows (scroll) | 60 fps | — | — | DevTools frame jank |
| Fee Demand drill-down (53 students) | < 1.5 s | — | — | RPC → UI ready |
| Daily Collection Excel export (10K rows) | < 8 s | — | — | click → file saved |
| PDF receipt generation | < 1 s | — | — | click → preview shown |
| Bank CSV upload + match (1000-row HDFC) | < 5 s | — | — | upload → results table |
| `get_bank_recon_data` cold-cache | < 3 s | — | — | network panel timing |

## Memory

- Baseline RSS at idle on dashboard: record number.
- After 10× navigate-into-fee-collection-and-back: leak should be < 50 MB.

## Build size

`flutter build windows --release` — record `build/windows/x64/runner/Release/`
total bytes. Alert if grows by > 10 MB between releases.

## Reproducing measurements

1. Pick the scenario.
2. Launch in profile mode: `flutter run --profile -d windows`.
3. Open DevTools → Performance → record.
4. Trigger the scenario, stop recording, read the duration.
5. Run 3 trials, write the median into the table above.
