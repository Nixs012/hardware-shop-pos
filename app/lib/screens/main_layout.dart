import 'package:flutter/material.dart';

import 'billing/billing_screen.dart';
import 'products/products_screen.dart';
import 'reports/reports_screen.dart';
import 'settings/settings_screen.dart';
import '../models/staff.dart';
import '../utils/theme.dart';

class MainLayout extends StatefulWidget {
  final Staff currentStaff;

  const MainLayout({super.key, required this.currentStaff});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      BillingScreen(currentStaff: widget.currentStaff),
      ProductsScreen(currentStaff: widget.currentStaff),
      ReportsScreen(currentStaff: widget.currentStaff),
      SettingsScreen(currentStaff: widget.currentStaff),
    ];
  }

  static const _navItems = [
    _NavItem(
      title: 'Billing',
      subtitle: 'POS Register',
      icon: Icons.point_of_sale,
    ),
    _NavItem(
      title: 'Products',
      subtitle: 'Inventory Management',
      icon: Icons.inventory_2,
    ),
    _NavItem(
      title: 'Reports',
      subtitle: 'Sales & Analytics',
      icon: Icons.bar_chart,
    ),
    _NavItem(
      title: 'Settings',
      subtitle: 'Staff & Setup',
      icon: Icons.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        if (isDesktop) {
          return Scaffold(
            backgroundColor: AppTheme.backgroundColor,
            body: Row(
              children: [
                _buildDesktopSidebar(),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _buildDesktopHeader(),
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
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.point_of_sale),
                label: 'Billing',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.inventory_2),
                label: 'Products',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.bar_chart),
                label: 'Reports',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopSidebar() {
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
                itemCount: _navItems.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final item = _navItems[index];
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
                  Text(
                    'Desktop Portal',
                    style: TextStyle(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.7),
                      fontSize: 11,
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

  Widget _buildDesktopHeader() {
    final current = _navItems[_currentIndex];

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
          Row(
            children: [
              Icon(current.icon, color: AppTheme.primaryColor, size: 22),
              const SizedBox(width: 12),
              Text(
                current.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '•  ${current.subtitle}',
                style: const TextStyle(
                  color: AppTheme.secondaryColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.circle, color: Colors.green, size: 8),
                SizedBox(width: 6),
                Text(
                  'Connected',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String title;
  final String subtitle;
  final IconData icon;

  const _NavItem({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
