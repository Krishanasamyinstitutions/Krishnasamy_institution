# ONGC — Project UI/UX Specifications

A single reference for the app‑wide standards and changes implemented in this
project. Each section states the rule, where it lives, and what is intentionally
excluded.

Related design docs:
[forms-focus-and-borders.md](forms-focus-and-borders.md) ·
[admission-menus-design.md](admission-menus-design.md) ·
[admission-design.md](admission-design.md) ·
[admission-master-design.md](admission-master-design.md) ·
[fast-admission-design.md](fast-admission-design.md) ·
[class-allocation-design.md](class-allocation-design.md)

---

## 1. Table row heights

**Rule:** every table has a **header row of 44.h** and a **body/data row of 36.h**.
Footer / total rows that visually match the header use the header height.

| Table type | How height is set |
| ---------- | ----------------- |
| Flutter `DataTable` | `headingRowHeight: 44.h`, `dataRowMinHeight: 36.h`, `dataRowMaxHeight: 36.h` |
| Custom `Container(padding…) + Row` | header `vertical: 12.h`, body `vertical: 6.h` (≈ 44 / 36) |
| Fixed‑height custom rows | header/footer `height: 44.h`, body `height: 36.h` |

**Exception:** the Settings payment‑sequence `DataTable` keeps
`dataRowMaxHeight: double.infinity` (editable prefix cells); only header 44.h /
min 36.h are enforced.

Applied across all tables in fees, admission, admin, students, superadmin and
transactions screens.

---

## 2. Zebra striping

**Rule:** editable / data table rows alternate **white** (`Colors.white`) and
**surface** (`AppColors.surface`, `#F9F8F4`) — `color: i.isEven ? Colors.white : AppColors.surface`.
Selection is shown by the control (e.g. amber checkbox), **not** by tinting the
whole row, so the stripes always read.

Reference fix: Pending Fee Demands grid in
[student_fee_collection_screen.dart](../lib/screens/fees/student_fee_collection_screen.dart)
(rows were all tinted by selection, hiding the zebra).

---

## 3. Tab focus traversal (keyboard navigation)

**Rule:** `Tab` / `Shift+Tab` move through a form's fields in reading order and
**never** reach the sidebar menu or top‑bar chrome. `Enter` / `Space` activates
the focused control.

Mechanisms (full detail in
[forms-focus-and-borders.md](forms-focus-and-borders.md)):
- **`FocusTraversalGroup`** around each form (and around an editable table's
  `ListView` + each row).
- **`ExcludeFocus`** on the sidebar + top bar in
  [dashboard_screen.dart](../lib/screens/dashboard/dashboard_screen.dart) — they
  stay mouse‑clickable but are out of the Tab ring.
- **[`FocusableTap`](../lib/widgets/focusable_tap.dart)** — a reusable widget
  that makes tap‑only controls (chips, pill buttons, date pickers) keyboard‑
  focusable, Enter/Space‑activatable, and shows an accent focus ring.

Covers every multi‑field form / editable table; single‑field forms and read‑only
tables are intentionally not wrapped.

---

## 4. Field border width = 1.5px

**Rule:** every form **input field** (text, dropdown, date, and the normal
unselected state) outlines at **1.5px** in both states — grey `AppColors.border`
when idle, accent `AppColors.accent` when focused (navy `AppColors.primary` for
theme‑fallback fields). Only the colour changes on focus, not the thickness.

Sources of truth:
- Global `inputDecorationTheme` in [app_theme.dart](../lib/utils/app_theme.dart).
- Per‑screen field‑decoration helpers (`_dec`, `_fieldDec`, `_filledFieldDec`,
  `_lookupFieldDec`, `_inputDecoration`, `_cellDec`, `_numField`, …).
- Dropdown / date `Container` borders and the `FocusableTap` ring.

**Not 1.5 (non‑field, left at 2px):** trust‑logo border, wizard stepper circle,
splash ring, a `2.5` chart stroke; card / table / chip / divider borders unchanged.

---

## 5. Navigation — FEES menu order

**Fee Collection** is the **second** item in the FEES sidebar group, defined in
[dashboard_screen.dart](../lib/screens/dashboard/dashboard_screen.dart):

1. Fee Master → 2. **Fee Collection** → 3. Fee Demand → 4. Fee Demand Approval
*(admin)* → 5. Fee Concession → 6. Bank Reconciliation *(admin)* → 7. Transactions

---

## 6. Search suggestions popup anchoring

**Rule:** a field's search‑results popup is anchored to the field with a
`LayerLink` (`CompositedTransformTarget` + `CompositedTransformFollower`), so it
always drops **directly below the search bar** regardless of window size —
never hard‑coded screen coordinates.

Reference: student search popup in
[student_fee_collection_screen.dart](../lib/screens/fees/student_fee_collection_screen.dart).

---

## 7. Fee Demand Approval table

The **STANDARD** column was removed from the demand‑approval table
([fee_demand_approval_screen.dart](../lib/screens/fees/fee_demand_approval_screen.dart));
the row now flows SECTION → YEAR → TERM.

---

## 8. Colour palette (reference)

Source: [`AppColors`](../lib/utils/app_theme.dart).

| Token | Hex | Use |
| ----- | --- | --- |
| `primary` | `#002147` | navy — titles, primary buttons, focused (theme) field border |
| `accent` | `#D2913C` | amber — CTAs, focused field border, focus ring, section header tint |
| `success` | `#22C55E` | completed step, allocated banner |
| `warning` | `#F59E0B` | pending badges |
| `error` | `#EF4444` | delete icons, error border |
| `surface` | `#F9F8F4` | page background, zebra odd rows, read‑only fields |
| `tableHeadBg` | `#EFEAD8` | table header band |
| `border` | `#BFC1C2` | field / card / table borders (idle) |
| `textPrimary` | `#1A1A1A` | titles, labels, cell text |
| `textSecondary` | `#4A5568` | subtitles, body cells |

Note: the green **Refresh** button seen disabled uses `#10B981`
(`disabledBackgroundColor`); when enabled it is `accent #D2913C`.

---

## 9. Responsive rule (compact ≤ 1366 px)

Action buttons and field padding shrink below 1366px via
[`AppBtn`](../lib/utils/app_theme.dart) / `AppTheme.compactButtons`.

| Property | Compact (≤1366) | Expanded |
| -------- | --------------- | -------- |
| Button height / icon / h‑pad / radius / text | 30 / 12 / 10 / 6 / 11 | 40 / 16 / 18 / 10 / 13 |
| Field hint / h‑pad / v‑pad / radius | 11 / 8 / 5 / 5 | 14 / 14 / 14 / 8 |

---

## 10. Environment note

Windows desktop build uses the standalone **NuGet** CLI (installed via
`winget install Microsoft.NuGet`). A leftover running `school_admin.exe` locks
the build output and causes `Error copying directory … data/flutter_assets`;
close the app (or kill the process) before rebuilding.

---

## Verification

After each change set, the project was validated with `flutter analyze lib`
(**0 errors**) and run on Windows desktop (`flutter run -d windows`).
