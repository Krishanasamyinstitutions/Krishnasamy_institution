# EduDesk — School Administrative Desktop Application

A comprehensive Flutter desktop application for school administration, featuring student management, staff scheduling, attendance tracking, fee collection, and analytics dashboards.

## Screens

| Screen | Description |
|--------|-------------|
| **Splash Screen** | Animated logo with progress bar, auto-navigates to onboarding |
| **Onboarding (3 pages)** | Student Management, Staff & Scheduling, Reports & Analytics |
| **Welcome Screen** | Split-panel layout with Sign In / Create Account / Demo options |
| **Login Screen** | Email/password auth with form validation and demo credentials |
| **Register Screen** | Full registration with name, email, role selection, password |
| **Forgot Password** | Email-based password reset flow with success state |
| **Dashboard** | Full admin dashboard with sidebar nav, stats, charts, events, activity feed |

## Project Structure

```
lib/
├── main.dart                         # App entry point
├── utils/
│   ├── app_theme.dart                # Colors, gradients, typography, theme
│   ├── app_routes.dart               # Named route definitions
│   └── auth_provider.dart            # Authentication state management
├── screens/
│   ├── splash/splash_screen.dart     # Animated splash screen
│   ├── onboarding/onboarding_screen.dart  # 3-page onboarding flow
│   ├── welcome/welcome_screen.dart   # Welcome / landing screen
│   ├── auth/
│   │   ├── login_screen.dart         # Login form
│   │   ├── register_screen.dart      # Registration form
│   │   └── forgot_password_screen.dart # Password reset
│   └── dashboard/dashboard_screen.dart # Main dashboard
└── widgets/
    ├── stat_card.dart                # KPI stat cards
    ├── attendance_chart.dart         # Weekly attendance bar chart
    ├── upcoming_events.dart          # Upcoming events list
    ├── recent_activities.dart        # Activity feed
    └── quick_actions.dart            # Quick action buttons
```

## Getting Started

### Prerequisites
- Flutter SDK 3.1+ installed
- Desktop support enabled (`flutter config --enable-windows-desktop` / `--enable-macos-desktop` / `--enable-linux-desktop`)

### Setup

```bash
# Clone or copy the project
cd school_admin

# Install dependencies
flutter pub get

# Run on desktop
flutter run -d windows    # or macos / linux

# Run on Chrome (for testing)
flutter run -d chrome
```

### Demo Credentials
- **Email:** admin@edudesk.com
- **Password:** admin123

Alternatively, any email + password (6+ chars) will log in as a "Teacher" role.

## Design System

- **Primary:** Deep Navy (`#1A2E4A`)
- **Accent:** Vibrant Teal (`#00BFA6`)
- **Secondary:** Warm Amber (`#F7A800`)
- **Typography:** Plus Jakarta Sans (via Google Fonts)
- **Responsive:** Adapts between desktop, tablet, and mobile layouts

## Dependencies

| Package | Purpose |
|---------|---------|
| `provider` | State management |
| `google_fonts` | Plus Jakarta Sans typography |
| `animate_do` | Page transition animations |
| `smooth_page_indicator` | Onboarding page dots |
| `fl_chart` | Chart library (available for extension) |
| `flutter_svg` | SVG asset support |

## Extending the App

The dashboard sidebar has navigation items for Students, Teachers, Classes, Attendance, Exams, Fees, Calendar, Notices, and Settings — each can be built as a separate module. The `_selectedNavIndex` in `DashboardScreen` controls which view is active.
