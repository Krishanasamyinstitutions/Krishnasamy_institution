# Forms — Tab Focus Traversal & Field Border Standard

Reference for two app-wide form conventions:

1. **Tab-click (keyboard focus) behaviour** — how `Tab` / `Shift+Tab` move
   through a form's fields.
2. **Field border width = 1.5px** — the standard outline weight for input
   fields, and exactly which fields use it.

---

## Part 1 — Tab focus traversal

### Goal
Pressing **Tab** moves focus field‑by‑field **within the current form**, in
reading order, and **never** lands on the sidebar menu or the top‑bar chrome.
**Shift+Tab** moves backwards. **Enter / Space** activates the focused control.

### The four mechanisms

| Mechanism | Widget | Where | Purpose |
| --------- | ------ | ----- | ------- |
| **Per‑form group** | `FocusTraversalGroup` | around each form's field `Column` / card | Keeps a form's fields together and ordered; stops focus leaking out mid‑form |
| **Per‑table + per‑row group** | nested `FocusTraversalGroup` | around an editable table's `ListView` AND around each row | Tab walks every row top‑to‑bottom; within a row, left‑to‑right |
| **Chrome excluded** | `ExcludeFocus` | sidebar + top bar in [dashboard_screen.dart](../lib/screens/dashboard/dashboard_screen.dart) | The nav tiles & header buttons are **not** keyboard‑focusable (still mouse‑clickable), so Tab can never reach them from any screen |
| **Focusable custom controls** | [`FocusableTap`](../lib/widgets/focusable_tap.dart) | replaces tap‑only `GestureDetector`s (chips, pill buttons, date pickers) | Makes tap‑only controls reachable by Tab, activatable with Enter/Space, and shows an accent focus ring |

### `FocusableTap` (the key helper)
`lib/widgets/focusable_tap.dart` — drop‑in replacement for a `GestureDetector`
form control. Same `onTap` + `child` API. It:
- joins Tab / Shift+Tab traversal,
- activates on **Enter / Space**,
- draws a **1.5px accent focus ring** (`foregroundDecoration`, so no layout shift),
- still works with the mouse exactly as before.

```dart
// before — invisible to Tab
GestureDetector(onTap: _pick, child: dateBox)
// after — joins the Tab order
FocusableTap(onTap: _pick, child: dateBox)
```

> **Why it was needed:** plain `GestureDetector`s (and `DropdownButton` inside a
> bare `Container`) can't hold keyboard focus, so Tab skipped right over them.
> The Notice form was almost entirely `GestureDetector` chips/date pickers, which
> is why Tab appeared to "do nothing" there until they were wrapped.

### Rules for which regions get wrapped

| Region type | Rule |
| ----------- | ---- |
| Multi‑field entry/edit form (≥2 focusable inputs) | one `FocusTraversalGroup` around the field column / form card |
| Editable row/grid table (rows with ≥2 inputs) | `FocusTraversalGroup` around the `ListView` **and** around each row |
| Editable table whose rows have 1 input | table‑level group only (a single field can't reorder) |
| Tap‑only control that should be Tab‑reachable | wrap with `FocusableTap` |
| Single standalone field / search box | not wrapped (nothing to order) |
| Read‑only tables, cards, dividers | never wrapped |

---

## Part 2 — Field border width = **1.5px**

### The standard
Every **form input field** outlines at **1.5px** in **both** states:
- **Unselected / normal (unfocused):** 1.5px, grey `AppColors.border` (`#BFC1C2`)
- **Focused:** 1.5px, accent `AppColors.accent` (`#D2913C`) — navy
  `AppColors.primary` (`#002147`) for fields that fall back to the global theme

### Which fields use 1.5px
| Field type | How the 1.5 is applied |
| ---------- | ---------------------- |
| **Text fields** (`TextField` / `TextFormField`) | `OutlineInputBorder` `borderSide.width: 1.5` on `border` / `enabledBorder` / `focusedBorder` / `errorBorder` |
| **Dropdowns** | `DropdownButtonFormField` → same InputDecoration borders; `DropdownButton` wrapped in a `Container` → `Border.all(..., width: 1.5)` |
| **Date fields** | tappable date `Container(Border.all(..., width: 1.5))` (inside `FocusableTap` / `GestureDetector`), or `InputDecorator` using the field helper |
| **Unselected (normal) state** | the `enabledBorder` (idle) is 1.5px too — so the border does **not** change thickness on focus, only colour |
| **`FocusableTap` focus ring** | 1.5px accent ring |

### Where the 1.5 lives (single sources of truth)
| Location | Covers |
| -------- | ------ |
| Global `inputDecorationTheme` in [app_theme.dart](../lib/utils/app_theme.dart) (`border`, `enabledBorder`, `focusedBorder`, `errorBorder` → `width: 1.5`) | every field that doesn't set its own border (incl. plain auth fields) |
| Per‑screen field‑decoration helpers (`_dec`, `_fieldDec`, `_filledFieldDec`, `_lookupFieldDec`, `_inputDecoration`, `_cellDec`, `_filledDec`, `_inputDec`, `_fieldDecoration`, `_numField`, `_dialogInputDec`, etc.) | fields on the fees / admission / admin / students / superadmin / notices screens |
| Dropdown & date `Container` borders (notices `_buildDropdown` / `_buildCourseFilterDropdown` / `_buildDatePicker`; reports date & dropdown boxes) | custom dropdown / date controls |
| [`FocusableTap`](../lib/widgets/focusable_tap.dart) ring | chips, pill buttons, date pickers |

### What is intentionally **NOT** 1.5 (non‑field borders left at 2px)
These are not form fields and keep their own weight:
- Trust logo border — [dashboard_screen.dart:963](../lib/screens/dashboard/dashboard_screen.dart#L963)
- Wizard stepper circle — [admission_screen.dart:832](../lib/screens/admission/admission_screen.dart#L832)
- Splash ring — `splash_screen.dart`
- A `2.5` chart stroke — `failed_transactions_screen.dart`
- Card borders, table/grid frames, table‑cell separators, chip/badge/pill
  outlines, dividers — unchanged.

---

## Part 3 — Forms covered

All multi‑field forms / editable tables in the app carry the Tab‑group +
1.5px‑border treatment.

**Fees**
- Fee Master — fee‑entry table (table + per‑row), Add Fee Group / Fee Type / Term cards
- Student Fee Collection — Pending Demands grid (table + per‑row), Cheque/UPI dialog
- Student Fee Definition dialog — Opted/Amount grid (table + per‑row)
- Fee Concession — concession grid (table‑level)
- Fee Demand — Add Fee Demand form

**Admission**
- Fast Admission — bulk‑entry grid (table + per‑row)
- Class / Section Allocation — allocation rows (table‑level)
- Admission — 4‑step wizard sections (shared `_section`)
- Admission Master — Reg‑No add card + Term Period add card

**Admin**
- Admin Creation, Bank Details, Master Data, Staff Designation — add/edit forms
- Settings — Fine Rules form, Staff Designation form, Custom Roles form, Payment‑Sequence editable cells
- Custom Roles — Add Role form

**Students / Superadmin / Notices**
- Students — Student / Parent / Payment field groups
- Super Admin Dashboard — Account Settings form
- Notices — Notice compose/edit form (all chips & date pickers are `FocusableTap`)

**Auth / Welcome / Dashboard**
- Login, Register (3 steps), Forgot Password (password step), Device Activation,
  Super Admin Registration, Welcome (sign‑in + forgot‑password), Academic‑Year dialog

**Shared widget**
- `MasterCrudPanel` add/edit card — used by Community, Concession, Sections and
  other simple‑master tabs (one fix covers all)

**Not wrapped (correctly):** single‑field forms, standalone search/filter fields,
read‑only tables.

---

## Part 4 — Checklist for a NEW form

1. Wrap the form's field `Column` (or card) in `FocusTraversalGroup`.
2. For an editable table, also wrap the `ListView` **and** each row.
3. Replace any tap‑only `GestureDetector` control (chip, pill, date picker)
   with [`FocusableTap`](../lib/widgets/focusable_tap.dart).
4. Use a field decoration whose `OutlineInputBorder` borderSides are `width: 1.5`
   (or just rely on the global theme — it's already 1.5).
5. For a `DropdownButton`/date control built as a bordered `Container`, set
   `Border.all(..., width: 1.5)`.
6. Don't touch card / table / chip / divider borders — those are not fields.
7. The sidebar & top bar are already `ExcludeFocus`'d in the dashboard shell, so
   Tab will stay inside your form automatically.
