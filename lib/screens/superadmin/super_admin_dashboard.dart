import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../auth/register_screen.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  int _selectedNavIndex = 0;
  bool _sidebarCollapsed = false;

  static const List<_SANavItem> _navItems = [
    _SANavItem(Icons.dashboard_rounded, 'Dashboard'),
    _SANavItem(Icons.domain_add_rounded, 'Register Institution'),
    _SANavItem(Icons.business_rounded, 'Manage Institutions'),
  ];

  List<Map<String, dynamic>> _institutions = [];
  bool _loadingInstitutions = true;

  @override
  void initState() {
    super.initState();
    _loadInstitutions();
  }

  Future<void> _loadInstitutions() async {
    try {
      final result = await SupabaseService.client
          .from('institution')
          .select('ins_id, insname, inscode, insmail, insmobno, inscity, insstate, activestatus')
          .order('insname');
      if (mounted) {
        setState(() {
          _institutions = List<Map<String, dynamic>>.from(result);
          _loadingInstitutions = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingInstitutions = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      backgroundColor: AppColors.surface,
      drawer: !isDesktop
          ? Drawer(child: _buildSidebar(context, false))
          : null,
      body: Row(
        children: [
          if (isDesktop)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: _sidebarCollapsed ? 78 : 240,
              child: _buildSidebar(context, _sidebarCollapsed),
            ),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context, isDesktop),
                Expanded(child: _buildContent(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, bool collapsed) {
    return Container(
      color: AppColors.surfaceSidebar,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 16.w : 24.w,
              vertical: 24.h,
            ),
            child: Row(
              children: [
                Container(
                  width: 42.w,
                  height: 42.h,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    color: AppColors.primary,
                    size: 22.sp,
                  ),
                ),
                if (!collapsed) ...[
                  SizedBox(width: 14.w),
                  Text(
                    'Super Admin',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 8.h),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 12.w : 16.w),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final isSelected = _selectedNavIndex == index;
                return Padding(
                  padding: EdgeInsets.only(bottom: 4.h),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _selectedNavIndex = index),
                      borderRadius: BorderRadius.circular(12.r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                          horizontal: collapsed ? 12.w : 16.w,
                          vertical: 12.h,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                              size: 20.sp,
                            ),
                            if (!collapsed) ...[
                              SizedBox(width: 14.w),
                              Flexible(
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      ),
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
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDesktop) {
    final auth = context.watch<AuthProvider>();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 28 : 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          if (isDesktop)
            IconButton(
              onPressed: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
              icon: Icon(_sidebarCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
              ),
            ),
          SizedBox(width: 16.w),
          Text(
            _navItems[_selectedNavIndex].label,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 17.r,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                  child: Text(
                    (auth.userName ?? 'S')[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(width: 10.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(auth.userName ?? 'Super Admin',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Super Admin',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: 'Options',
                  position: PopupMenuPosition.under,
                  offset: Offset(0, 8.h),
                  color: Colors.white,
                  elevation: 10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
                  onSelected: (value) async {
                    if (value == 'signout') {
                      await auth.logout();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, AppRoutes.welcome);
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'signout',
                      child: Row(
                        children: [
                          Icon(Icons.logout_rounded, size: 18.sp),
                          SizedBox(width: 8.w),
                          const Text('Sign out'),
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

  Widget _buildContent(BuildContext context) {
    switch (_selectedNavIndex) {
      case 1:
        return const RegisterScreen();
      case 2:
        return _buildManageInstitutions(context);
      default:
        return _buildDashboardHome(context);
    }
  }

  Widget _buildDashboardHome(BuildContext context) {
    final activeCount = _institutions.where((i) => i['activestatus'] == 1).length;
    return Padding(
      padding: EdgeInsets.all(28.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overview', style: Theme.of(context).textTheme.headlineSmall),
          SizedBox(height: 24.h),
          Row(
            children: [
              _buildStatCard(context, 'Total Institutions', '${_institutions.length}', Icons.business_rounded, AppColors.primary),
              SizedBox(width: 20.w),
              _buildStatCard(context, 'Active Institutions', '$activeCount', Icons.check_circle_rounded, AppColors.success),
              SizedBox(width: 20.w),
              _buildStatCard(context, 'Inactive', '${_institutions.length - activeCount}', Icons.pause_circle_rounded, AppColors.error),
            ],
          ),
          SizedBox(height: 32.h),
          Text('Recent Institutions', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 12.h),
          Expanded(
            child: _loadingInstitutions
                ? const Center(child: CircularProgressIndicator())
                : _institutions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.business_outlined, size: 48.sp, color: AppColors.textLight),
                            SizedBox(height: 12.h),
                            Text('No institutions registered yet', style: Theme.of(context).textTheme.bodyLarge),
                            SizedBox(height: 12.h),
                            ElevatedButton.icon(
                              onPressed: () => setState(() => _selectedNavIndex = 1),
                              icon: const Icon(Icons.add),
                              label: const Text('Register Institution'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _institutions.length > 5 ? 5 : _institutions.length,
                        itemBuilder: (context, index) {
                          final ins = _institutions[index];
                          return Card(
                            margin: EdgeInsets.only(bottom: 8.h),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Text(
                                  (ins['insname'] as String? ?? 'I')[0].toUpperCase(),
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                                ),
                              ),
                              title: Text(ins['insname'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${ins['inscode'] ?? ''} - ${ins['inscity'] ?? ''}'),
                              trailing: Container(
                                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                                decoration: BoxDecoration(
                                  color: ins['activestatus'] == 1
                                      ? AppColors.success.withValues(alpha: 0.1)
                                      : AppColors.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20.r),
                                ),
                                child: Text(
                                  ins['activestatus'] == 1 ? 'Active' : 'Inactive',
                                  style: TextStyle(
                                    color: ins['activestatus'] == 1 ? AppColors.success : AppColors.error,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48.w,
              height: 48.h,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(icon, color: color, size: 24.sp),
            ),
            SizedBox(width: 16.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManageInstitutions(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(28.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('All Institutions', style: Theme.of(context).textTheme.headlineSmall),
              ElevatedButton.icon(
                onPressed: () => setState(() => _selectedNavIndex = 1),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Register New'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Expanded(
            child: _loadingInstitutions
                ? const Center(child: CircularProgressIndicator())
                : _institutions.isEmpty
                    ? const Center(child: Text('No institutions found'))
                    : ListView.builder(
                        itemCount: _institutions.length,
                        itemBuilder: (context, index) {
                          final ins = _institutions[index];
                          return Card(
                            margin: EdgeInsets.only(bottom: 8.h),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Text(
                                  (ins['insname'] as String? ?? 'I')[0].toUpperCase(),
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                                ),
                              ),
                              title: Text(ins['insname'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('Code: ${ins['inscode'] ?? ''} | ${ins['insmail'] ?? ''} | ${ins['inscity'] ?? ''}, ${ins['insstate'] ?? ''}'),
                              trailing: Container(
                                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                                decoration: BoxDecoration(
                                  color: ins['activestatus'] == 1
                                      ? AppColors.success.withValues(alpha: 0.1)
                                      : AppColors.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20.r),
                                ),
                                child: Text(
                                  ins['activestatus'] == 1 ? 'Active' : 'Inactive',
                                  style: TextStyle(
                                    color: ins['activestatus'] == 1 ? AppColors.success : AppColors.error,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SANavItem {
  final IconData icon;
  final String label;
  const _SANavItem(this.icon, this.label);
}
