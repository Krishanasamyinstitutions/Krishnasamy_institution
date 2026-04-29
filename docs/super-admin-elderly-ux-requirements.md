# Super Admin Login — UX Requirements for Elderly Users (80+)

**Target user:** Super admin who is 80+ years old.
**Goal:** Make the super admin app comfortable, safe, and confidence-inspiring for an elderly user — without losing functionality the role needs.

---

## 1. Text Size

| Element | Current | Required |
|---|---|---|
| Body text | 13.sp | **min 16px** (raw, not scaled) |
| Field labels | 12-13.sp | **min 14px** |
| Numbers / amounts | 16-18.sp | **18-20px**, weight `w700`+ |
| Hint text in fields | 13.sp at 55% alpha | **14px at 100% color** |
| Section headers | 14.sp | **18-20px**, weight `w700` |

- No `textSecondary` text rendered on white at < 60% alpha.
- WCAG AAA contrast for body text: **7:1** ratio.
- Avoid italic / thin / condensed font weights.

## 2. Touch / Click Targets

- Minimum button height: **48px** (preferably **56px**).
- Minimum spacing between clickable items: **12px**.
- Avoid icon-only buttons. Every clickable icon needs a text label.
- Hover-only tooltips are unreliable — must work without hover.
- Right-click / long-press should never be the only way to access a feature.

## 3. Reduce Cognitive Load

- One primary task per screen.
- Break long forms into clear, named sections (≤ 5 fields per section).
- Consistent button positions:
  - **Cancel / Back** → bottom-left.
  - **Apply / Save / Next** → bottom-right.
- Drop secondary actions (Export, Filter, Refresh) behind a single menu rather than crowding the toolbar.
- Default values pre-filled wherever possible.
- "Today" pills, smart presets, last-used selections.

## 4. Confirmations for Destructive Actions

Every destructive action requires a confirm dialog with **explicit object naming**:

| Action | Confirm message |
|---|---|
| Delete institution | "Yes, delete KCET Institutes" |
| Sign out | "Are you sure you want to sign out?" |
| Reset password | "Reset password for `<user>`?" |
| Force-push / overwrite | Explicit "this will replace existing data" warning |

## 5. Error Messages

- **Friendly, not technical.**
- Bad: `PostgrestException: Invalid schema kp20262027`
- Good: `KCET Polytechnique's data isn't available right now. Please contact support.`
- Show errors inline near the field that caused them.
- Use full-screen error pages only for fatal failures.

## 6. Avoid Time Pressure

- Razorpay 10-minute payment cap → extend to **30 minutes** with a visible, slow-moving countdown.
- No auto-logout while a form has unsaved input.
- Notifications must not blink, flash, or auto-disappear.
- Toast messages: minimum **8 seconds** visible (vs default 4).

## 7. Visual Hierarchy

- **One** accent color (`#D2913C` amber) reserved for the primary action only — don't use it for decorative purposes.
- Critical actions (Pay, Approve, Delete) are visually distinct from casual ones (Refresh, Export).
- Page title is the largest text on the screen.
- Numbers always larger than their labels.

## 8. Icons + Labels

- Always pair icons with text. Never rely on icon shape alone.
- Use bold-style icons (filled), not linear/outline (less legible).
- Icon size: **18-22px** for body, **24-28px** for headers.

## 9. Animations & Transitions

- Page transitions: **400ms** (vs 250ms default) — less jarring.
- Disable rapid transitions on data refresh.
- No parallax, no auto-rotating carousels, no auto-playing videos.

## 10. App-Specific Recommendations

### Course-wise Drilldown
- Add "**X of Y**" total count under tables.
- Keep `Back` button always visible (already in the breadcrumb card — good).
- Avoid pagination if list is < 30 rows.

### Register Institution (3-step wizard)
- Allow skipping non-required fields. Don't block on Next.
- Save draft automatically — don't lose data on accidental refresh / navigation.
- Step 3 (Account Setup) should require typing current password twice to pre-empt typos.

### Settings
- Show **"You are signed in as `<name>`"** prominently in case the user forgets.
- Group related fields tightly. Add visible spacing between Account / Password sections.

### Header
- Institution logo + name centered (already done).
- User avatar + name visible at all times so the user knows who is logged in.
- Notification bell: badge color must be high-contrast red, not subtle.

### Sidebar
- Section labels (`MAIN MENU`, `INSTITUTIONS`, `GENERAL`) clearly differentiated from items (already done with amber labels).
- Selected item: navy fill with white text — keep current.
- Unselected items: ensure contrast is ≥ 7:1 against sidebar background.

### Notifications
- Read/unread status must be visually obvious (current red dot — good).
- Bigger badge on bell when unread > 0.

### Tables
- Larger row heights: **52-60px** (currently 14px vertical padding).
- No tiny dropdown filters — replace with full-width modal (popup).
- Zebra striping helps eye-tracking — keep it.

## 11. Accessibility (WCAG-Adjacent)

- Keyboard navigation: every interactive element reachable by Tab.
- Focus indicator visible (Flutter default is fine — don't override).
- Screen reader support: meaningful semantic labels on icon buttons.
- Don't rely on color alone to convey state (e.g., "red = error" — also use text).

## 12. What NOT to Do

- ❌ Modal dialogs that auto-dismiss after a few seconds.
- ❌ Drag-and-drop interactions (motor skill barrier).
- ❌ Multi-finger gestures (pinch-zoom is OK; complex gestures are not).
- ❌ "Confirm by clicking quickly twice" — single deliberate clicks only.
- ❌ Dark mode by default — light mode is more legible for elderly users.
- ❌ Tiny X (close) buttons in dialog corners — use a labeled "Close" button instead.

---

## Implementation Priority (Quick Wins)

| Priority | Task | Effort |
|---|---|---|
| **P0** | Bump base font size 13 → 16 raw px | Small |
| **P0** | Make all buttons min 52px height | Small |
| **P0** | Add confirm dialog before Sign Out | Small |
| **P1** | Replace icon-only actions with labeled buttons | Medium |
| **P1** | Slow page transitions to 400ms | Small |
| **P1** | Friendlier error messages app-wide | Medium |
| **P2** | Auto-save register form drafts | Medium |
| **P2** | Toast messages stay 8s | Small |
| **P2** | Extend Razorpay timeout to 30 min | Small |

---

_Maintained by:_ Krishnaswamy Institutions
_Last updated:_ 2026-04-27
