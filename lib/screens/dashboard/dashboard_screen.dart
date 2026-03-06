import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../students/students_screen.dart';
import '../fees/fees_screen.dart';
import '../fees/fee_collection_screen.dart';
import '../transactions/failed_transactions_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedNavIndex = 0;
  bool _sidebarCollapsed = false;

  String? _institutionType;
  String _institutionRecognized = 'Yes';
  DateTime? _institutionStartDate;
  DateTime? _affiliationStartYear;
  final TextEditingController _institutionNameController =
      TextEditingController();
  final TextEditingController _institutionCodeController =
      TextEditingController();
  final TextEditingController _authorizedUsernameController =
      TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  final TextEditingController _mobileNumberController = TextEditingController();
  final TextEditingController _institutionAffiliationController =
      TextEditingController();
  final TextEditingController _affiliationNumberController =
      TextEditingController();
  final TextEditingController _address1Controller = TextEditingController();
  final TextEditingController _address2Controller = TextEditingController();
  final TextEditingController _address3Controller = TextEditingController();
  final TextEditingController _pinCodeController = TextEditingController();
  final List<String> _institutionTypes = [
    'Schools (Primary, Secondary, Higher Secondary)',
    'Colleges',
    'Universities',
    'Polytechnic Institutions',
    'Vocational Training Centers',
    'Coaching Institutes',
  ];

  final List<_NavItem> _navItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.people_alt_rounded, 'Students'),
    _NavItem(Icons.domain_add_rounded, 'Institution creation'),
    _NavItem(Icons.account_balance_wallet_rounded, 'Fees'),
    _NavItem(Icons.error_outline_rounded, 'Failed Transactions'),
    _NavItem(Icons.notifications_rounded, 'Notices'),
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  @override
  void dispose() {
    _institutionNameController.dispose();
    _institutionCodeController.dispose();
    _authorizedUsernameController.dispose();
    _designationController.dispose();
    _mobileNumberController.dispose();
    _institutionAffiliationController.dispose();
    _affiliationNumberController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _address3Controller.dispose();
    _pinCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;
    final isTablet = size.width > 500 && size.width <= 800;

    return Scaffold(
      backgroundColor: AppColors.surface,
      drawer: (!isDesktop && !isTablet)
          ? Drawer(child: _buildSidebar(context, false))
          : null,
      body: Row(
        children: [
          // Sidebar
          if (isDesktop || isTablet)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: _sidebarCollapsed ? 78 : (isDesktop ? 260 : 78),
              child: _buildSidebar(
                  context, _sidebarCollapsed || isTablet),
            ),

          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(context, isDesktop),

                // Content area
                Expanded(
                  child: _isFullHeightScreen()
                      ? Padding(
                          padding: EdgeInsets.all(isDesktop ? 28 : 16),
                          child: _buildDashboardContent(context, isDesktop),
                        )
                      : SingleChildScrollView(
                          padding: EdgeInsets.all(isDesktop ? 28 : 16),
                          child: _buildDashboardContent(context, isDesktop),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, bool collapsed) {
    return Container(
      color: AppColors.primary,
      child: Column(
        children: [
          // Logo area
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 16 : 24,
              vertical: 24,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: AppColors.accent,
                    size: 22,
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 14),
                  Text(
                    'EduDesk',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Nav items
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 16),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final isSelected = _selectedNavIndex == index;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _selectedNavIndex = index),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                          horizontal: collapsed ? 12 : 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.accent.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              color: isSelected
                                  ? AppColors.accent
                                  : Colors.white.withValues(alpha: 0.5),
                              size: 22,
                            ),
                            if (!collapsed) ...[
                              const SizedBox(width: 14),
                              Text(
                                item.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: isSelected
                                          ? AppColors.accent
                                          : Colors.white.withValues(alpha: 0.7),
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDesktop) {
    final auth = context.watch<AuthProvider>();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 28 : 16,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (!isDesktop && MediaQuery.of(context).size.width <= 500)
            IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          if (isDesktop)
            IconButton(
              onPressed: () =>
                  setState(() => _sidebarCollapsed = !_sidebarCollapsed),
              icon: Icon(
                _sidebarCollapsed
                    ? Icons.menu_open_rounded
                    : Icons.menu_rounded,
              ),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _navItems[_selectedNavIndex].label,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  'Academic Year 2025-26',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),

          // Search bar (desktop only)
          if (isDesktop)
            Container(
              width: 280,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search students, staff...',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textLight,
                        fontSize: 13,
                      ),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 20, color: AppColors.textLight),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                ),
              ),
            ),

          const SizedBox(width: 16),

          // Notification bell
          Stack(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_outlined, size: 22),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                  child: Text(
                    (auth.userName ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 180 : 120,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.userName ?? 'User',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        auth.userRole ?? 'Staff',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Profile options',
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 8),
                  color: Colors.white,
                  elevation: 10,
                  surfaceTintColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppColors.border),
                  ),
                  menuPadding: const EdgeInsets.symmetric(vertical: 6),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onSelected: (value) async {
                    if (value == 'signout') {
                      await auth.logout();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, AppRoutes.welcome);
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'signout',
                      child: Row(
                        children: [
                          Icon(Icons.logout_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Sign out'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Screens that manage their own scroll and need full bounded height
  bool _isFullHeightScreen() {
    final label = _navItems[_selectedNavIndex].label;
    return label == 'Dashboard' || label == 'Students' || label == 'Fees' || label == 'Institution creation' || label == 'Failed Transactions';
  }

  Widget _buildDashboardContent(BuildContext context, bool isDesktop) {
    final selectedMenu = _navItems[_selectedNavIndex].label;
    if (selectedMenu == 'Institution creation') {
      return _buildInstitutionCreationContent(context, isDesktop);
    }
    if (selectedMenu == 'Students') {
      return const StudentsScreen();
    }
    if (selectedMenu == 'Fees') {
      return const FeesScreen();
    }
    if (selectedMenu == 'Failed Transactions') {
      return const FailedTransactionsScreen();
    }
    // Dashboard shows Fee Collection screen
    return const FeeCollectionScreen();
  }

  Widget _buildInstitutionCreationContent(BuildContext context, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top action bar
        Row(
          children: [
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _saveInstitution,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Split layout: LEFT = Institution Info | RIGHT = Affiliation + Address
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT — Institution Information
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Row(children: [
                          Icon(Icons.domain_add_rounded, color: AppColors.accent, size: 20),
                          SizedBox(width: 8),
                          Text('Institution Information',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        ]),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(color: AppColors.border),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _insField(label: 'Institution Type', child: DropdownButtonFormField<String>(
                                initialValue: _institutionType,
                                decoration: _insDec('Select institution type'),
                                isExpanded: true,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                items: _institutionTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (v) => setState(() => _institutionType = v),
                              )),
                              const SizedBox(height: 14),
                              _insRow2(
                                _insField(label: 'Institution Name *', child: TextFormField(
                                  controller: _institutionNameController,
                                  decoration: _insDec('Enter institution name'),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                )),
                                _insField(label: 'Institution Code *', child: TextFormField(
                                  controller: _institutionCodeController,
                                  decoration: _insDec('Enter institution code'),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                )),
                              ),
                              const SizedBox(height: 14),
                              _insField(
                                label: 'Institution Start Date',
                                child: InkWell(
                                  onTap: _pickInstitutionStartDate,
                                  child: InputDecorator(
                                    decoration: _insDec('Select date').copyWith(
                                      suffixIcon: const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.textSecondary),
                                    ),
                                    child: Text(
                                      _institutionStartDate != null ? _formatDate(_institutionStartDate!) : 'Select date',
                                      style: TextStyle(
                                        color: _institutionStartDate != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6),
                                        fontSize: 13,
                                        fontWeight: _institutionStartDate != null ? FontWeight.w700 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              _insRow2(
                                _insField(label: 'Authorized Username', child: TextFormField(
                                  controller: _authorizedUsernameController,
                                  decoration: _insDec('Enter authorized username'),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                )),
                                _insField(label: 'Designation', child: TextFormField(
                                  controller: _designationController,
                                  decoration: _insDec('Enter designation'),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                )),
                              ),
                              const SizedBox(height: 14),
                              _insRow2(
                                _insField(label: 'Mobile Number', child: TextFormField(
                                  controller: _mobileNumberController,
                                  decoration: _insDec('Enter mobile number'),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                  keyboardType: TextInputType.phone,
                                )),
                                _insField(label: 'Institution Recognized', child: DropdownButtonFormField<String>(
                                  initialValue: _institutionRecognized,
                                  decoration: _insDec('Select'),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                  items: const [
                                    DropdownMenuItem(value: 'Yes', child: Text('Yes')),
                                    DropdownMenuItem(value: 'No', child: Text('No')),
                                  ],
                                  onChanged: (v) { if (v != null) setState(() => _institutionRecognized = v); },
                                )),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // RIGHT — Affiliation + Address
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Affiliation card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.verified_rounded, color: AppColors.accent, size: 20),
                              SizedBox(width: 8),
                              Text('Affiliation Information', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            ]),
                            const SizedBox(height: 4),
                            const Divider(color: AppColors.border),
                            const SizedBox(height: 12),
                            _insRow2(
                              _insField(label: 'Institution Affiliation', child: TextFormField(
                                controller: _institutionAffiliationController,
                                decoration: _insDec('Enter affiliation'),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                              )),
                              _insField(label: 'Affiliation Number', child: TextFormField(
                                controller: _affiliationNumberController,
                                decoration: _insDec('Enter affiliation number'),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                              )),
                            ),
                            const SizedBox(height: 14),
                            _insField(
                              label: 'Affiliation Start Year',
                              child: InkWell(
                                onTap: _pickAffiliationStartYear,
                                child: InputDecorator(
                                  decoration: _insDec('Select year').copyWith(
                                    suffixIcon: const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.textSecondary),
                                  ),
                                  child: Text(
                                    _affiliationStartYear != null ? '${_affiliationStartYear!.year}' : 'Select year',
                                    style: TextStyle(
                                      color: _affiliationStartYear != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6),
                                      fontSize: 13,
                                      fontWeight: _affiliationStartYear != null ? FontWeight.w700 : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Address card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.location_on_rounded, color: AppColors.accent, size: 20),
                              SizedBox(width: 8),
                              Text('Address', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            ]),
                            const SizedBox(height: 4),
                            const Divider(color: AppColors.border),
                            const SizedBox(height: 12),
                            _insField(label: 'Address Line 1 *', child: TextFormField(
                              controller: _address1Controller,
                              decoration: _insDec('Enter address line 1'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                            )),
                            const SizedBox(height: 14),
                            _insField(label: 'Address Line 2', child: TextFormField(
                              controller: _address2Controller,
                              decoration: _insDec('Enter address line 2'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                            )),
                            const SizedBox(height: 14),
                            _insRow2(
                              _insField(label: 'Address Line 3', child: TextFormField(
                                controller: _address3Controller,
                                decoration: _insDec('Enter address line 3'),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                              )),
                              _insField(label: 'Pin Code', child: TextFormField(
                                controller: _pinCodeController,
                                decoration: _insDec('Enter pin code'),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary),
                                keyboardType: TextInputType.number,
                              )),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _insField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _insRow2(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 14),
        Expanded(child: right),
      ],
    );
  }

  InputDecoration _insDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent)),
    filled: true,
    fillColor: Colors.white,
  );

  Future<void> _saveInstitution() async {
    // Basic validation
    if (_institutionNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter institution name'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_institutionCodeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter institution code'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      await SupabaseService.client.from('institution').insert({
        'instype': _institutionType,
        'insname': _institutionNameController.text.trim(),
        'inscode': _institutionCodeController.text.trim(),
        'insstartdate': _institutionStartDate?.toIso8601String().split('T').first,
        'insauthorizedusername': _authorizedUsernameController.text.trim(),
        'insdesignation': _designationController.text.trim(),
        'insmobile': _mobileNumberController.text.trim(),
        'insrecognized': _institutionRecognized,
        'insaffiliation': _institutionAffiliationController.text.trim(),
        'insaffno': _affiliationNumberController.text.trim(),
        'insaffstartyear': _affiliationStartYear?.year.toString(),
        'insaddress1': _address1Controller.text.trim(),
        'insaddress2': _address2Controller.text.trim(),
        'insaddress3': _address3Controller.text.trim(),
        'inspincode': _pinCodeController.text.trim(),
        'activestatus': 1,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Institution saved successfully'), backgroundColor: AppColors.accent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving institution: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }


  Future<void> _pickInstitutionStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _institutionStartDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _institutionStartDate = picked);
    }
  }

  Future<void> _pickAffiliationStartYear() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _affiliationStartYear ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Select Affiliation Start Year',
      fieldLabelText: 'Year',
    );
    if (picked != null) {
      setState(() => _affiliationStartYear = DateTime(picked.year));
    }
  }

  String _formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year.toString();
    return '$dd/$mm/$yyyy';
  }

  String _formatCurrency(double amount) {
    final str = amount.toStringAsFixed(0);
    final pattern = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formatted = str.replaceAllMapped(pattern, (m) => '${m[1]},');
    return '₹$formatted';
  }

}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
