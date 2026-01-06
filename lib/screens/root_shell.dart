import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'home_screen.dart';
import 'daily_reports_screen.dart';
import 'reports_screen.dart';
import 'invoices_screen.dart';

class RootShell extends StatefulWidget {
  final int initialIndex;
  final bool isStaff;

  const RootShell({super.key, this.initialIndex = 0, this.isStaff = false});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late int
  currentIndex; // 0 = Home, 1 = Daily Reports, 2 = Reports, 3 = Invoices
  final GlobalKey<HomeScreenState> _homeScreenKey =
      GlobalKey<HomeScreenState>();
  final GlobalKey<DailyReportsScreenState> _dailyReportsScreenKey =
      GlobalKey<DailyReportsScreenState>();
  final GlobalKey<ReportsScreenState> _reportsScreenKey =
      GlobalKey<ReportsScreenState>();
  final GlobalKey<InvoicesScreenState> _invoicesScreenKey =
      GlobalKey<InvoicesScreenState>();

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
  }

  late final List<Widget> pages = [
    HomeScreen(key: _homeScreenKey, isStaff: widget.isStaff),
    if (!widget.isStaff) DailyReportsScreen(key: _dailyReportsScreenKey),
    if (!widget.isStaff) ReportsScreen(key: _reportsScreenKey),
    if (!widget.isStaff) InvoicesScreen(key: _invoicesScreenKey),
  ];

  void _onTap(int index) {
    setState(() => currentIndex = index);
    // Refresh data when navigating to different screens
    if (index == 0) {
      _homeScreenKey.currentState?.refreshData();
    } else if (!widget.isStaff) {
      if (index == 1) {
        // Refresh daily reports when navigating to it
        _dailyReportsScreenKey.currentState?.refreshCalendarData();
      } else if (index == 2) {
        // Refresh reports when navigating to it (especially after daily reports changes)
        _reportsScreenKey.currentState?.refreshCalendarData();
      } else if (index == 3) {
        // Refresh invoices when navigating to it
        _invoicesScreenKey.currentState?.refreshData();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(index: currentIndex, children: pages),
      bottomNavigationBar: widget.isStaff
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0x66717171), width: 3),
                  ),
                  color: Colors.white,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _NavItem(
                      icon: Icons.home_filled,
                      label: 'Home',
                      selected: currentIndex == 0,
                      onTap: () => _onTap(0),
                    ),
                    _NavItem(
                      icon: Icons.calendar_month,
                      label: 'Daily Reports',
                      selected: currentIndex == 1,
                      onTap: () => _onTap(1),
                    ),
                    _NavItem(
                      icon: Icons.pie_chart,
                      label: 'Reports',
                      selected: currentIndex == 2,
                      onTap: () => _onTap(2),
                    ),
                    _NavItem(
                      icon: Icons.receipt_long,
                      label: 'Invoices',
                      selected: currentIndex == 3,
                      onTap: () => _onTap(3),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: Colors.black),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.quicksand(
              fontSize: 16,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: Colors.black,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
