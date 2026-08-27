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
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
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
            child: Image.asset(
              'assets/images/logo.png',
              height: 32,
            ),
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
  }
}
