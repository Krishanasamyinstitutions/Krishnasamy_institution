# Admission Master — Design Specification

File: `lib/screens/admission/admission_master_screen.dart`
Sidebar group: **ADMISSION** → **Admission Master**

A pill-tab page for editing the three lookup tables that drive the
Admission form: Community, Admission No (register sequencing) and Concession.

This screen is the closest sibling of Fee Master and Master Data — they
share the same shell, the same `_addCard` / `_tableShell` pattern, and the
same Import CSV/Excel workflow.

---

## 1. Page shell

`AdmissionMasterScreen` is a `StatefulWidget` with
`SingleTickerProviderStateMixin` holding a `late final TabController`.

The build returns a plain `Column` — **no outer `Padding`, no
`AppCard.decoration()`**. The Dashboard shell already provides the
page-level breathing room.

```dart
@override
Widget build(BuildContext context) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListenableBuilder(
        listenable: _tabController,
        builder: (context, _) {
          final selected = _tabController.index;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _tabLabels.length; i++) ...[
                    PillTab(
                      icon: _tabIcons[i],
                      label: _tabLabels[i],
                      selected: selected == i,
                      onTap: () => _tabController.animateTo(i),
                    ),
                    if (i < _tabLabels.length - 1)
                      SizedBox(width: PillTab.gap(context)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
      SizedBox(height: 6.h),
      Expanded(
        child: TabBarView(
          controller: _tabController,
          children: const [
            MasterCrudPanel(
              table: 'community',
              idCol: 'com_id',
              nameCol: 'comname',
              title: 'Community',
              icon: 'people',
              countLabel: 'communities',
            ),
            _RegNoPanel(),
            _ConcessionPanelWithImport(),
          ],
        ),
      ),
    ],
  );
}
```

### Tab definitions

| Index | Label         | Icon              |
| ----- | ------------- | ----------------- |
| 0     | Community     | `people`          |
| 1     | Admission No  | `tag`             |
| 2     | Concession    | `discount-shape`  |

Tab spacing (`vertical: 8` + `SizedBox(height: 6.h)`) is shared with Fee
Master, Master Data and Reports — don't change just for this page.

---

## 2. Community tab

Delegates entirely to `MasterCrudPanel` (in `lib/widgets/master_crud_panel.dart`).

```dart
MasterCrudPanel(
  table: 'community',
  idCol: 'com_id',
  nameCol: 'comname',
  title: 'Community',
  icon: 'people',
  countLabel: 'communities',
)
```

The shared widget renders:

- **Left** — `_addCard()` with `people` icon + "Add Community" title, the
  bold-label field "Community Name *" with placeholder "Enter community
  name", and the amber Add button.
- **Right** — `_tableShell()` outer card with header bar `people` icon +
  "Communities" title + count badge "X communities".
- Inner bordered table card (8r) with cream `tableHeadBg` header band:
  S NO. / COMMUNITY / ACTION.
- Body rows zebra-striped starting with white.

If `onImport` is wired (it is, via `_PanelWithImport`), the **Import
CSV/Excel** button sits inside the title bar to the right.

---

## 3. Admission No tab (`_RegNoPanel`)

A more complex CRUD panel — same outer two-card row, but the Add form has
several fields and the table has several columns.

### Add card

White Container, padding `20.w`, radius `10.r`, full `AppColors.border`.
Header row: `tag` icon (18, accent) + "Admission Number Sequencing"
(`15.sp w700`).

Fields (each is a `Column(_lbl + 6h SizedBox + field)`):

| Label                | Hint                  | Widget               |
| -------------------- | --------------------- | -------------------- |
| Name *               | "Enter name"          | `TextField`          |
| Mode                 | "Select mode"         | `DropdownButtonFormField` ("Prefix" / "Suffix") |
| Prefix / Suffix value| "e.g. ADM/"           | `TextField`          |
| Start No             | "1"                   | `TextField` (number) |
| End No               | "—"                   | `TextField` (number) |
| Width                | "4"                   | `TextField` (number) |
| Division             | "Division description"| `TextField` maxLines 2 |

Start No / End No / Width sit side-by-side in a `Row(Expanded × 3, 8w gap)`.

Gap between fields: `SizedBox(height: 16.h)`. Last field-to-button gap:
`SizedBox(height: 18.h)`.

Add button is full-width amber:

```dart
SizedBox(
  width: double.infinity,
  child: ElevatedButton.icon(
    onPressed: _saving ? null : _add,
    icon: _saving
        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Icon(Icons.add, size: 16),
    label: const Text('Add'),
    style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
  ),
)
```

### List card

Outer white card (10r, 16.w padding, full border) with the title-bar
header pattern: `tag` icon + "Register Sequences" + count badge
"X sequences" + Spacer.

Inner bordered table (8r, antiAlias clip) with these columns:

| Header     | Width    |
| ---------- | -------- |
| NAME       | flex: 3  |
| PRE/SUF    | 64.w     |
| AFFIX      | 64.w     |
| START      | 56.w     |
| END        | 56.w     |
| W          | 36.w     |
| (action)   | 44.w     |

Body rows zebra-striped (white / surface). Delete icon centered in the
last cell, `AppColors.error`, size 16, wrapped in
`InkWell(child: Padding(EdgeInsets.all(4.w), child: ...))`.

---

## 4. Concession tab (`_ConcessionPanelWithImport`)

Delegates to `MasterCrudPanel` again, with the Master Data Concession
import flow wired in:

```dart
MasterCrudPanel(
  table: 'concessioncategory',
  idCol: 'con_id',
  nameCol: 'condesc',
  title: 'Concession',
  icon: 'discount-shape',
  countLabel: 'concessions',
  inSchema: true,
  ordidCol: 'ordid',
  onImport: () => setState(() => _importing = true),
)
```

When `_importing` is true the wrapper swaps the body for
`MasterImportScreen(initialTabIndex: 4, showInternalTabs: false)` and
shows a "Back to list" header (`OutlinedButton.icon` + "Import
Concession" 14.sp w700 title).

---

## 5. Form field helpers (shared with the rest of the project)

### `_lbl(String text)`

Bold black label rendered above each field:

```dart
Widget _lbl(String text) => Text(text,
    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: Colors.black));
```

### `_filledFieldDec(String hint)`

Responsive input decoration:

| Property        | Compact (≤1366px) | Expanded |
| --------------- | ----------------- | -------- |
| Hint text size  | 11                | 14       |
| Horizontal pad  | 8                 | 14       |
| Vertical pad    | 5                 | 14       |
| Border radius   | 5                 | 8        |

```dart
InputDecoration(
  hintText: hint,
  hintStyle: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.6), fontSize: textSize),
  contentPadding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.border)),
  enabledBorder: …same…,
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.accent)),
  filled: true,
  fillColor: Colors.white,
)
```

### Dropdown popups

Every `DropdownButtonFormField` includes:

```dart
dropdownColor: Colors.white,
borderRadius: BorderRadius.circular(12),
elevation: 6,
```

---

## 6. Colors

| Token                          | Use                                          |
| ------------------------------ | -------------------------------------------- |
| `AppColors.primary`            | Edit row icon                                |
| `AppColors.accent`             | Add-card icon, count badge, Add/Import button, focused border |
| `AppColors.error`              | Delete row icon                              |
| `AppColors.tableHeadBg`        | Inner table header band                      |
| `AppColors.surface`            | Zebra odd rows                               |
| `AppColors.border`             | All borders                                  |
| `AppColors.textPrimary`        | Headers, labels                              |
| `AppColors.textSecondary`      | Body cells                                   |

---

## 7. When adding a new tab

1. Add a label + icon (Iconsax name) to `_tabLabels` / `_tabIcons`.
2. Append the panel to `TabBarView.children`.
3. If it's a single-name lookup, use `MasterCrudPanel` directly with
   `icon` + `countLabel` set — no custom code needed.
4. If it's a multi-field master, follow the `_RegNoPanel` pattern: white
   `_addCard` Container, `_lbl + _filledFieldDec` for every field, inner
   bordered table with cream header band and zebra-striped body.
5. To support CSV/Excel import, wrap it in a `_PanelWithImport` (Master
   Data file) or the local `_ConcessionPanelWithImport` (this file) and
   wire the `onImport` callback through to the table-shell's `actions`
   slot.
