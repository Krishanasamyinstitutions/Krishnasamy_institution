"""One-shot Material -> Iconsax swap across lib/**.

Safe to re-run (idempotent-ish): skips files that already import app_icon.dart,
unless they still have Icons.xxx occurrences (mixed state).
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
LIB = os.path.join(ROOT, "lib")

# Material name -> (Iconsax SVG name, style)
#   style: 'bold' (default) or 'linear'
MAP = {
    "access_time_rounded": ("clock", "bold"),
    "account_balance_rounded": ("bank", "bold"),
    "account_balance_wallet": ("wallet-1", "linear"),
    "account_balance_wallet_rounded": ("wallet-1", "bold"),
    "add": ("add", "bold"),
    "add_circle_outline": ("add-circle", "linear"),
    "add_photo_alternate_outlined": ("gallery-add", "linear"),
    "add_rounded": ("add", "bold"),
    "admin_panel_settings_rounded": ("security-user", "bold"),
    "approval_rounded": ("tick-square", "bold"),
    "arrow_back_rounded": ("arrow-left", "bold"),
    "arrow_drop_down": ("arrow-down-1", "bold"),
    "arrow_forward_ios_rounded": ("arrow-right-1", "bold"),
    "arrow_forward_rounded": ("arrow-right", "bold"),
    "assessment_outlined": ("chart-1", "linear"),
    "assessment_rounded": ("chart-1", "bold"),
    "badge_outlined": ("personalcard", "linear"),
    "badge_rounded": ("personalcard", "bold"),
    "bar_chart_rounded": ("chart-2", "bold"),
    "beach_access_rounded": ("sun-1", "bold"),
    "block_rounded": ("forbidden-2", "bold"),
    "business_rounded": ("building", "bold"),
    "cake_rounded": ("cake", "bold"),
    "calendar_month_rounded": ("calendar-1", "bold"),
    "calendar_today": ("calendar", "linear"),
    "calendar_today_outlined": ("calendar", "linear"),
    "calendar_today_rounded": ("calendar-1", "bold"),
    "camera_alt_rounded": ("camera", "bold"),
    "campaign_rounded": ("volume-high", "bold"),
    "category_rounded": ("category", "bold"),
    "check_box_outline_blank_rounded": ("stop", "linear"),
    "check_box_rounded": ("tick-square", "bold"),
    "check_circle": ("tick-circle", "bold"),
    "check_circle_outline": ("tick-circle", "linear"),
    "check_circle_outline_rounded": ("tick-circle", "linear"),
    "check_circle_rounded": ("tick-circle", "bold"),
    "check_rounded": ("tick-circle", "bold"),
    "chevron_left": ("arrow-left-2", "linear"),
    "chevron_left_rounded": ("arrow-left-2", "bold"),
    "chevron_right": ("arrow-right-3", "linear"),
    "chevron_right_rounded": ("arrow-right-3", "bold"),
    "class_rounded": ("book-1", "bold"),
    "close": ("close-circle", "linear"),
    "close_rounded": ("close-circle", "bold"),
    "cloud_upload_outlined": ("cloud-add", "linear"),
    "currency_rupee": ("money-recive", "bold"),
    "dashboard_rounded": ("element-3", "bold"),
    "delete_rounded": ("trash", "bold"),
    "description_outlined": ("document-text", "linear"),
    "devices_rounded": ("monitor", "bold"),
    "domain_add_rounded": ("building", "bold"),
    "done_all_rounded": ("task-square", "bold"),
    "download_rounded": ("document-download", "bold"),
    "edit_notifications_rounded": ("notification-bing", "bold"),
    "edit_rounded": ("edit-2", "bold"),
    "email_outlined": ("sms", "linear"),
    "email_rounded": ("sms", "bold"),
    "error_outline": ("info-circle", "linear"),
    "error_outline_rounded": ("info-circle", "linear"),
    "error_rounded": ("close-circle", "bold"),
    "event_busy_rounded": ("calendar-remove", "bold"),
    "event_rounded": ("calendar-1", "bold"),
    "fact_check_rounded": ("clipboard-tick", "bold"),
    "family_restroom_rounded": ("people", "bold"),
    "file_download_rounded": ("document-download", "bold"),
    "filter_alt_rounded": ("filter", "bold"),
    "first_page": ("arrow-square-left", "linear"),
    "first_page_rounded": ("arrow-square-left", "bold"),
    "folder_open_rounded": ("folder-open", "bold"),
    "folder_rounded": ("folder-2", "bold"),
    "gavel_rounded": ("judge", "bold"),
    "grid_on_rounded": ("element-4", "bold"),
    "group_rounded": ("people", "bold"),
    "groups_rounded": ("profile-2user", "bold"),
    "hourglass_top_rounded": ("clock", "bold"),
    "inbox_rounded": ("message-text", "bold"),
    "info_outline_rounded": ("info-circle", "linear"),
    "insights_rounded": ("chart-21", "bold"),
    "inventory_2_outlined": ("box-1", "linear"),
    "key_rounded": ("key", "bold"),
    "keyboard_arrow_down": ("arrow-down-1", "linear"),
    "keyboard_arrow_down_rounded": ("arrow-down-1", "bold"),
    "keyboard_arrow_up": ("arrow-up", "linear"),
    "label_rounded": ("tag", "bold"),
    "last_page": ("arrow-square-right", "linear"),
    "last_page_rounded": ("arrow-square-right", "bold"),
    "link_rounded": ("link-1", "bold"),
    "list_alt_rounded": ("menu-1", "bold"),
    "list_rounded": ("menu-1", "bold"),
    "location_on_rounded": ("location", "bold"),
    "lock_outline_rounded": ("lock", "linear"),
    "lock_reset_rounded": ("password-check", "bold"),
    "lock_rounded": ("lock", "bold"),
    "logout_rounded": ("logout", "bold"),
    "mark_email_read_rounded": ("sms-tracking", "bold"),
    "menu_book_outlined": ("book-1", "linear"),
    "menu_book_rounded": ("book-1", "bold"),
    "menu_open_rounded": ("menu-board", "bold"),
    "menu_rounded": ("menu", "bold"),
    "message_rounded": ("message", "bold"),
    "notifications_active_rounded": ("notification-bing", "bold"),
    "notifications_off_rounded": ("notification-bing", "bold"),
    "notifications_outlined": ("notification", "linear"),
    "notifications_rounded": ("notification", "bold"),
    "payment": ("wallet-money", "linear"),
    "payment_rounded": ("wallet-money", "bold"),
    "payments_rounded": ("money-recive", "bold"),
    "pending_actions_rounded": ("timer", "bold"),
    "pending_outlined": ("clock", "linear"),
    "people_alt_outlined": ("people", "linear"),
    "people_alt_rounded": ("people", "bold"),
    "people_outline": ("people", "linear"),
    "people_rounded": ("people", "bold"),
    "person_add_rounded": ("user-add", "bold"),
    "person_outline": ("user", "linear"),
    "person_outline_rounded": ("user", "linear"),
    "person_rounded": ("user", "bold"),
    "phone_outlined": ("call", "linear"),
    "phone_rounded": ("call", "bold"),
    "picture_as_pdf_rounded": ("document-text", "bold"),
    "play_circle_outline_rounded": ("play-circle", "linear"),
    "preview_rounded": ("eye", "bold"),
    "print_rounded": ("printer", "bold"),
    "quiz_rounded": ("message-question", "bold"),
    "receipt_long": ("receipt-2", "linear"),
    "receipt_long_outlined": ("receipt-2", "linear"),
    "receipt_long_rounded": ("receipt-2", "bold"),
    "refresh_rounded": ("refresh", "bold"),
    "request_page_rounded": ("receipt-edit", "bold"),
    "save": ("save-2", "linear"),
    "save_rounded": ("save-2", "bold"),
    "school_outlined": ("teacher", "linear"),
    "school_rounded": ("teacher", "bold"),
    "search": ("search-normal", "linear"),
    "search_off": ("search-favorite", "linear"),
    "search_rounded": ("search-normal-1", "bold"),
    "security_rounded": ("shield-tick", "bold"),
    "send_rounded": ("send-2", "bold"),
    "settings_rounded": ("setting-2", "bold"),
    "shield_outlined": ("shield-tick", "linear"),
    "supervisor_account_rounded": ("profile-circle", "bold"),
    "support_agent_rounded": ("24-support", "bold"),
    "table_chart_rounded": ("grid-1", "bold"),
    "tag_rounded": ("tag", "bold"),
    "timer_off_rounded": ("timer-pause", "bold"),
    "today_rounded": ("calendar-1", "bold"),
    "trending_down_rounded": ("arrow-down", "bold"),
    "trending_up_rounded": ("arrow-up-1", "bold"),
    "upload_file_rounded": ("document-upload", "bold"),
    "upload_rounded": ("document-upload", "bold"),
    "verified_rounded": ("verify", "bold"),
    "verified_user_rounded": ("shield-tick", "bold"),
    "visibility": ("eye", "linear"),
    "visibility_off": ("eye-slash", "linear"),
    "visibility_off_outlined": ("eye-slash", "linear"),
    "visibility_outlined": ("eye", "linear"),
    "warning_rounded": ("warning-2", "bold"),
}


def relative_import_path(file_path: str) -> str:
    """Return the relative path from file_path to lib/widgets/app_icon.dart."""
    rel = os.path.relpath(
        os.path.join(LIB, "widgets", "app_icon.dart"),
        os.path.dirname(file_path),
    ).replace("\\", "/")
    return rel


def insert_import(content: str, import_line: str) -> str:
    if import_line in content:
        return content
    # Insert after last existing import line
    pattern = re.compile(r"^(import\s+['\"][^'\"]+['\"]\s*;\s*\n)+", re.MULTILINE)
    m = None
    for mm in pattern.finditer(content):
        m = mm
    if m is None:
        return import_line + "\n" + content
    end = m.end()
    return content[:end] + import_line + "\n" + content[end:]


ICON_CONSTRUCTOR_RE = re.compile(
    r"\bIcon\s*\(\s*Icons\.([a-zA-Z0-9_]+)\b"
)
ICONS_ONLY_RE = re.compile(r"\bIcons\.([a-zA-Z0-9_]+)\b")


def transform(content: str) -> tuple[str, int, set[str]]:
    """Return (new_content, replacement_count, unmapped_names)."""
    unmapped: set[str] = set()
    count = 0

    def sub_icon_ctor(m: re.Match) -> str:
        nonlocal count
        name = m.group(1)
        if name not in MAP:
            unmapped.add(name)
            return m.group(0)
        iconsax, style = MAP[name]
        count += 1
        if style == "linear":
            return f"AppIcon.linear('{iconsax}'"
        return f"AppIcon('{iconsax}'"

    new = ICON_CONSTRUCTOR_RE.sub(sub_icon_ctor, content)

    # Standalone Icons.xxx references (outside Icon() wrapper) — used in data
    # structures like `_NavItem(Icons.xxx, ...)`. We replace with a string
    # literal — caller must hold it as String.
    def sub_icons_only(m: re.Match) -> str:
        nonlocal count
        name = m.group(1)
        if name not in MAP:
            unmapped.add(name)
            return m.group(0)
        iconsax, _style = MAP[name]
        count += 1
        return f"'{iconsax}'"

    new = ICONS_ONLY_RE.sub(sub_icons_only, new)

    return new, count, unmapped


def process_file(path: str, dry_run: bool = False) -> tuple[int, set[str]]:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    if "Icons." not in content and "Icon(" not in content:
        return 0, set()

    new_content, count, unmapped = transform(content)
    if count == 0 and not unmapped:
        return 0, set()

    # Add import if any replacement happened
    if count > 0:
        rel = relative_import_path(path)
        import_line = f"import '{rel}';"
        new_content = insert_import(new_content, import_line)

    if not dry_run and new_content != content:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)

    return count, unmapped


def main():
    dry_run = "--dry-run" in sys.argv
    total_replacements = 0
    total_files = 0
    all_unmapped: dict[str, list[str]] = {}

    for root, _dirs, files in os.walk(LIB):
        for name in files:
            if not name.endswith(".dart"):
                continue
            path = os.path.join(root, name)
            # Skip the widget itself
            if os.path.basename(path) == "app_icon.dart":
                continue
            count, unmapped = process_file(path, dry_run=dry_run)
            if count:
                total_files += 1
                total_replacements += count
                rel_display = os.path.relpath(path, ROOT).replace("\\", "/")
                print(f"  [{count:3d}] {rel_display}")
            if unmapped:
                rel_display = os.path.relpath(path, ROOT).replace("\\", "/")
                all_unmapped[rel_display] = sorted(unmapped)

    print()
    print(f"Files changed:   {total_files}")
    print(f"Replacements:    {total_replacements}")
    if all_unmapped:
        print()
        print("UNMAPPED NAMES (left as Icons.xxx):")
        for fp, names in sorted(all_unmapped.items()):
            print(f"  {fp}")
            for n in names:
                print(f"      Icons.{n}")


if __name__ == "__main__":
    main()
