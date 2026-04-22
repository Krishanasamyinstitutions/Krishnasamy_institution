// One-shot Material -> Iconsax swap across lib/**.
// Run: node tools/swap_icons.mjs [--dry-run]

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.resolve(__dirname, "..");
const LIB = path.join(ROOT, "lib");

// Material name -> [Iconsax SVG name, style ('bold' | 'linear')]
const MAP = {
  access_time_rounded: ["clock", "bold"],
  account_balance_rounded: ["bank", "bold"],
  account_balance_wallet: ["wallet-1", "linear"],
  account_balance_wallet_rounded: ["wallet-1", "bold"],
  add: ["add", "bold"],
  add_circle_outline: ["add-circle", "linear"],
  add_photo_alternate_outlined: ["gallery-add", "linear"],
  add_rounded: ["add", "bold"],
  admin_panel_settings_rounded: ["security-user", "bold"],
  approval_rounded: ["tick-square", "bold"],
  arrow_back_rounded: ["Chevron Left", "linear"],
  arrow_drop_down: ["Chevron Down", "linear"],
  arrow_forward_ios_rounded: ["Chevron Right", "linear"],
  arrow_forward_rounded: ["Chevron Right", "linear"],
  assessment_outlined: ["chart-1", "linear"],
  assessment_rounded: ["chart-1", "bold"],
  badge_outlined: ["personalcard", "linear"],
  badge_rounded: ["personalcard", "bold"],
  bar_chart_rounded: ["chart-2", "bold"],
  beach_access_rounded: ["sun-1", "bold"],
  block_rounded: ["forbidden-2", "bold"],
  business_rounded: ["building", "bold"],
  cake_rounded: ["cake", "bold"],
  calendar_month_rounded: ["calendar-1", "bold"],
  calendar_today: ["calendar", "linear"],
  calendar_today_outlined: ["calendar", "linear"],
  calendar_today_rounded: ["calendar-1", "bold"],
  camera_alt_rounded: ["camera", "bold"],
  campaign_rounded: ["volume-high", "bold"],
  category_rounded: ["category", "bold"],
  check_box_outline_blank_rounded: ["stop", "linear"],
  check_box_rounded: ["tick-square", "bold"],
  check_circle: ["tick-circle", "bold"],
  check_circle_outline: ["tick-circle", "linear"],
  check_circle_outline_rounded: ["tick-circle", "linear"],
  check_circle_rounded: ["tick-circle", "bold"],
  check_rounded: ["tick-circle", "bold"],
  chevron_left: ["Chevron Left", "linear"],
  chevron_left_rounded: ["Chevron Left", "linear"],
  chevron_right: ["Chevron Right", "linear"],
  chevron_right_rounded: ["Chevron Right", "linear"],
  class_rounded: ["book-1", "bold"],
  close: ["close-circle", "linear"],
  close_rounded: ["close-circle", "bold"],
  cloud_upload_outlined: ["cloud-add", "linear"],
  currency_rupee: ["money-recive", "bold"],
  dashboard_rounded: ["element-3", "bold"],
  delete_rounded: ["trash", "bold"],
  description_outlined: ["document-text", "linear"],
  devices_rounded: ["monitor", "bold"],
  domain_add_rounded: ["building", "bold"],
  done_all_rounded: ["task-square", "bold"],
  download_rounded: ["document-download", "bold"],
  edit_notifications_rounded: ["notification-bing", "bold"],
  edit_rounded: ["edit-2", "bold"],
  email_outlined: ["sms", "linear"],
  email_rounded: ["sms", "bold"],
  error_outline: ["info-circle", "linear"],
  error_outline_rounded: ["info-circle", "linear"],
  error_rounded: ["close-circle", "bold"],
  event_busy_rounded: ["calendar-remove", "bold"],
  event_rounded: ["calendar-1", "bold"],
  fact_check_rounded: ["clipboard-tick", "bold"],
  family_restroom_rounded: ["people", "bold"],
  file_download_rounded: ["document-download", "bold"],
  filter_alt_rounded: ["filter", "bold"],
  first_page: ["Double Arrow Left", "linear"],
  first_page_rounded: ["Double Arrow Left", "linear"],
  folder_open_rounded: ["folder-open", "bold"],
  folder_rounded: ["folder-2", "bold"],
  gavel_rounded: ["judge", "bold"],
  grid_on_rounded: ["element-4", "bold"],
  group_rounded: ["people", "bold"],
  groups_rounded: ["profile-2user", "bold"],
  hourglass_top_rounded: ["clock", "bold"],
  inbox_rounded: ["message-text", "bold"],
  info_outline_rounded: ["info-circle", "linear"],
  insights_rounded: ["chart-21", "bold"],
  inventory_2_outlined: ["box-1", "linear"],
  key_rounded: ["key", "bold"],
  keyboard_arrow_down: ["Chevron Down", "linear"],
  keyboard_arrow_down_rounded: ["Chevron Down", "linear"],
  keyboard_arrow_up: ["Chevron Up", "linear"],
  label_rounded: ["tag", "bold"],
  last_page: ["Double Arrow Right", "linear"],
  last_page_rounded: ["Double Arrow Right", "linear"],
  link_rounded: ["link-1", "bold"],
  list_alt_rounded: ["menu-1", "bold"],
  list_rounded: ["menu-1", "bold"],
  location_on_rounded: ["location", "bold"],
  lock_outline_rounded: ["lock", "linear"],
  lock_reset_rounded: ["password-check", "bold"],
  lock_rounded: ["lock", "bold"],
  logout_rounded: ["logout", "bold"],
  mark_email_read_rounded: ["sms-tracking", "bold"],
  menu_book_outlined: ["book-1", "linear"],
  menu_book_rounded: ["book-1", "bold"],
  menu_open_rounded: ["menu-board", "bold"],
  menu_rounded: ["menu", "bold"],
  message_rounded: ["message", "bold"],
  notifications_active_rounded: ["notification-bing", "bold"],
  notifications_off_rounded: ["notification-bing", "bold"],
  notifications_outlined: ["notification", "linear"],
  notifications_rounded: ["notification", "bold"],
  payment: ["wallet-money", "linear"],
  payment_rounded: ["wallet-money", "bold"],
  payments_rounded: ["money-recive", "bold"],
  pending_actions_rounded: ["timer", "bold"],
  pending_outlined: ["clock", "linear"],
  people_alt_outlined: ["people", "linear"],
  people_alt_rounded: ["people", "bold"],
  people_outline: ["people", "linear"],
  people_rounded: ["people", "bold"],
  person_add_rounded: ["user-add", "bold"],
  person_outline: ["user", "linear"],
  person_outline_rounded: ["user", "linear"],
  person_rounded: ["user", "bold"],
  phone_outlined: ["call", "linear"],
  phone_rounded: ["call", "bold"],
  picture_as_pdf_rounded: ["document-text", "bold"],
  play_circle_outline_rounded: ["play-circle", "linear"],
  preview_rounded: ["eye", "bold"],
  print_rounded: ["printer", "bold"],
  quiz_rounded: ["message-question", "bold"],
  receipt_long: ["receipt-2", "linear"],
  receipt_long_outlined: ["receipt-2", "linear"],
  receipt_long_rounded: ["receipt-2", "bold"],
  refresh_rounded: ["refresh", "bold"],
  request_page_rounded: ["receipt-edit", "bold"],
  save: ["save-2", "linear"],
  save_rounded: ["save-2", "bold"],
  school_outlined: ["teacher", "linear"],
  school_rounded: ["teacher", "bold"],
  search: ["search-normal", "linear"],
  search_off: ["search-favorite", "linear"],
  search_rounded: ["search-normal", "linear"],
  security_rounded: ["shield-tick", "bold"],
  send_rounded: ["send-2", "bold"],
  settings_rounded: ["setting-2", "bold"],
  shield_outlined: ["shield-tick", "linear"],
  supervisor_account_rounded: ["profile-circle", "bold"],
  support_agent_rounded: ["24-support", "bold"],
  table_chart_rounded: ["grid-1", "bold"],
  tag_rounded: ["tag", "bold"],
  timer_off_rounded: ["timer-pause", "bold"],
  today_rounded: ["calendar-1", "bold"],
  trending_down_rounded: ["arrow-down", "bold"],
  trending_up_rounded: ["arrow-up-1", "bold"],
  upload_file_rounded: ["document-upload", "bold"],
  upload_rounded: ["document-upload", "bold"],
  verified_rounded: ["verify", "bold"],
  verified_user_rounded: ["shield-tick", "bold"],
  visibility: ["eye", "linear"],
  visibility_off: ["eye-slash", "linear"],
  visibility_off_outlined: ["eye-slash", "linear"],
  visibility_outlined: ["eye", "linear"],
  warning_rounded: ["warning-2", "bold"],
};

const DRY = process.argv.includes("--dry-run");

function relativeImport(filePath) {
  const target = path.join(LIB, "widgets", "app_icon.dart");
  let rel = path.relative(path.dirname(filePath), target).replace(/\\/g, "/");
  if (!rel.startsWith(".")) rel = "./" + rel;
  return rel;
}

function insertImport(content, importLine) {
  if (content.includes(importLine)) return content;
  const re = /^(import\s+['"][^'"]+['"]\s*;\s*\n)+/m;
  const m = content.match(re);
  if (!m) return importLine + "\n" + content;
  const end = m.index + m[0].length;
  return content.slice(0, end) + importLine + "\n" + content.slice(end);
}

// Regex: match `Icon(` wrapping and capture the argument `Icons.NAME`
// Handles whitespace/newlines between `Icon(` and `Icons.NAME`
const ICON_CTOR_RE = /\bIcon\s*\(\s*Icons\.([a-zA-Z0-9_]+)/g;
const ICONS_ONLY_RE = /\bIcons\.([a-zA-Z0-9_]+)/g;

function transform(content) {
  const unmapped = new Set();
  let count = 0;

  // Phase 1: `Icon(Icons.x ...` → `AppIcon('y' ...` or `AppIcon.linear('y' ...`
  let out = content.replace(ICON_CTOR_RE, (full, name, offset) => {
    if (!(name in MAP)) {
      unmapped.add(name);
      return full;
    }
    const [iconsax, style] = MAP[name];
    count++;
    if (style === "linear") {
      return `AppIcon.linear('${iconsax}'`;
    }
    return `AppIcon('${iconsax}'`;
  });

  // Phase 2: standalone `Icons.NAME` (e.g., data structures like `_NavItem(Icons.x, ...)`)
  out = out.replace(ICONS_ONLY_RE, (full, name) => {
    if (!(name in MAP)) {
      unmapped.add(name);
      return full;
    }
    const [iconsax] = MAP[name];
    count++;
    return `'${iconsax}'`;
  });

  // Phase 3: `IconData` type annotations -> `String`.
  // Safe because this codebase never invokes IconData(...) as a constructor;
  // it only appears as a type on params/fields.
  out = out.replace(/\bIconData\b/g, "String");

  // Phase 4: convert any remaining `Icon(` widget constructors -> `AppIcon(`.
  // Phase 1 already handled explicit `Icon(Icons.x ...)` cases; this catches
  // dynamic calls like `Icon(icon, ...)` where `icon` is a variable now typed
  // as String after Phase 3. `\bIcon\(` is bounded by word-char boundary, so
  // it won't match `AppIcon(`, `IconButton(`, `IconTheme(`, etc.
  out = out.replace(/\bIcon\s*\(/g, (match, offset) => {
    count++;
    return "AppIcon(";
  });

  return { out, count, unmapped };
}

function walk(dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, acc);
    else if (entry.isFile() && entry.name.endsWith(".dart")) acc.push(full);
  }
  return acc;
}

function main() {
  const files = walk(LIB);
  let changedFiles = 0;
  let totalReplacements = 0;
  const unmappedByFile = {};

  for (const fp of files) {
    if (path.basename(fp) === "app_icon.dart") continue;
    const orig = fs.readFileSync(fp, "utf8");
    if (!orig.includes("Icons.")) continue;

    const { out, count, unmapped } = transform(orig);
    let finalOut = out;
    if (count > 0) {
      const rel = relativeImport(fp);
      finalOut = insertImport(finalOut, `import '${rel}';`);
    }
    if (count > 0 && finalOut !== orig) {
      if (!DRY) fs.writeFileSync(fp, finalOut, "utf8");
      changedFiles++;
      totalReplacements += count;
      const display = path.relative(ROOT, fp).replace(/\\/g, "/");
      console.log(`  [${String(count).padStart(3)}] ${display}`);
    }
    if (unmapped.size > 0) {
      const display = path.relative(ROOT, fp).replace(/\\/g, "/");
      unmappedByFile[display] = [...unmapped].sort();
    }
  }

  console.log("");
  console.log(`Files changed:  ${changedFiles}`);
  console.log(`Replacements:   ${totalReplacements}`);
  console.log(`Mode:           ${DRY ? "DRY-RUN" : "WRITTEN"}`);
  if (Object.keys(unmappedByFile).length > 0) {
    console.log("");
    console.log("UNMAPPED NAMES (left as Icons.xxx):");
    for (const [fp, names] of Object.entries(unmappedByFile).sort()) {
      console.log(`  ${fp}`);
      for (const n of names) console.log(`      Icons.${n}`);
    }
  }
}

main();
