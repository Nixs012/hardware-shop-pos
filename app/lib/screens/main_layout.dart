import 'package:flutter/material.dart';

import 'billing/billing_screen.dart';
import 'products/products_screen.dart';
import 'reports/reports_screen.dart';
import 'settings/settings_screen.dart';
import 'customer_credit/customer_credit_screen.dart';
import '../models/staff.dart';
import '../utils/theme.dart';
import '../widgets/sync_status_indicator.dart';

/// Nav items — shown on mobile bottom nav and desktop sidebar.
/// Admin-only items (Expenses, Customer Credit) are injected after index 2
/// when the current staff member is an admin.
List<NavItem> buildNavItems(bool isAdmin) {
  final baseItems = [
    NavItem(
      title: 'Billing',
      subtitle: 'POS Register',
      icon: Icons.point_of_sale,
    ),
    NavItem(
      title: 'Products',
      subtitle: 'Inventory Management',
      icon: Icons.inventory_2,
    ),
    NavItem(
      title: 'Reports',
      subtitle: 'Sales & Analytics',
      icon: Icons.bar_chart,
    ),
    NavItem(
      title: 'Settings',
      subtitle: 'Staff & Setup',
      icon: Icons.settings,
    ),
  ];

  if (!isAdmin) return baseItems;

  // Admin-only items inserted before Settings
  return [
    ...baseItems.sublist(0, 3),
    NavItem(
      title: 'Customer Credit',
      subtitle: 'Khata Management',
      icon: Icons.account_balance,
    ),
    NavItem(
      title: 'Expenses',
      subtitle: 'Operating Expenses',
      icon: Icons.receipt_long,
    ),
    baseItems.last, // Settings
  ];
}

/// Builds the screen widgets matching the nav item order from [buildNavItems].
List<Widget> buildScreens(Staff currentStaff, bool isAdmin) {
  final List<Widget> screens = [
    BillingScreen(currentStaff: currentStaff),
    ProductsScreen(currentStaff: currentStaff),
    ReportsScreen(currentStaff: currentStaff),
  ];

  if (isAdmin) {
    screens.add(CustomerCreditScreen(currentStaff: currentStaff));
    screens.add(AdminPlaceholderScreen(
      title: 'Expenses',
      icon: Icons.receipt_long,
    ));
  }

  screens.add(SettingsScreen(currentStaff: currentStaff));
  return screens;
}

/// Lightweight placeholder for screens that are wired into nav but
/// implemented within another screen (Expenses lives in the Reports → P&L tab).
class AdminPlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const AdminPlaceholderScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
  body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppTheme.secondaryColor),
            const SizedBox(height: 24),
            Text(
              '$title management is available in the Reports → Profit & Loss tab.',
              style: const TextStyle(
                color: AppTheme.secondaryColor,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class MainLayout extends StatefulWidget {
  final Staff currentStaff;

  const MainLayout({super.key, required this.currentStaff});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late final bool _isAdmin;
  late final List<Widget> _screens;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _isAdmin = widget.currentStaff.role.toLowerCase() == 'admin';
    _screens = buildScreens(widget.currentStaff, _isAdmin);
  }

  static List<NavItem> _navItems(bool isAdmin) => buildNavItems(isAdmin);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final navItems = _navItems(_isAdmin);
        final isDesktop = constraints.maxWidth >= 800;

        if (isDesktop) {
          return Scaffold(
            backgroundColor: AppTheme.backgroundColor,
            body: Row(
              children: [
                _buildDesktopSidebar(navItems),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _buildDesktopHeader(navItems),
                      Expanded(child: _screens[_currentIndex]),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppTheme.backgroundColor,
            elevation: 1,
            title: Text(
              '${widget.currentStaff.name} (${widget.currentStaff.role.toUpperCase()})',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            actions: [
              const Center(child: SyncStatusIndicator(compact: true)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Image.asset('assets/images/logo.png', height: 32),
              ),
            ],
          ),
          body: _screens[_currentIndex],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            type: BottomNavigationBarType.fixed,
            items: [
              for (final item in navItems)
                BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  label: item.title,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopSidebar(List<NavItem> navItems) {
    return Container(
      width: 250,
      color: Colors.black.withValues(alpha: 0.2),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Image.asset('assets/images/logo.png', height: 36),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shamamo POS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Hardware & Supplies',
                          style: TextStyle(
                            color: AppTheme.secondaryColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          AppTheme.primaryColor.withValues(alpha: 0.2),
                      child: const Icon(
                        Icons.person,
                        size: 18,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.currentStaff.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: widget.currentStaff.role.toLowerCase() ==
                                      'admin'
                                  ? Colors.amber.withValues(alpha: 0.2)
                                  : Colors.blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.currentStaff.role.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: widget.currentStaff.role.toLowerCase() ==
                                        'admin'
                                    ? Colors.amber
                                    : Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: navItems.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final item = navItems[index];
                  final isSelected = _currentIndex == index;

                  return InkWell(
                    onTap: () => setState(() => _currentIndex = index),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryColor.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryColor.withValues(alpha: 0.4)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item.icon,
                            color: isSelected
                                ? AppTheme.primaryColor
                                : AppTheme.secondaryColor,
                            size: 22,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                Text(
                                  item.subtitle,
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppTheme.primaryColor
                                            .withValues(alpha: 0.8)
                                        : AppTheme.secondaryColor,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(
                    Icons.laptop_chromebook,
                    size: 16,
                    color: AppTheme.secondaryColor.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Desktop Portal',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.secondaryColor,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHeader(List<NavItem> navItems) {
    final current = navItems[_currentIndex];

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: AppTheme.secondaryColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(current.icon, color: AppTheme.primaryColor, size: 22),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '•  ${current.subtitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.secondaryColor,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SyncStatusIndicator(),
        ],
      ),
    );
  }
}

class NavItem {
  final String title;
  final String subtitle;
  final IconData icon;

  const NavItem({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
