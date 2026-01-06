import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pie_chart/pie_chart.dart';
import 'settings_screen.dart';
import 'daily_report_edit_screen.dart';
import 'staff_data_input_screen.dart';
import '../auth_service.dart';
import '../firestore_service.dart';
import '../fcm_service.dart';
// Bottom navigation is centralized in RootShell

class HomeScreen extends StatefulWidget {
  final bool isStaff;

  const HomeScreen({super.key, this.isStaff = false});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  bool _hasConfig = false;
  String _businessName = 'Business Handling';
  Map<String, dynamic>? _totalReport; // holds fetched total report
  Map<String, dynamic>? _userConfig; // holds user config for item lookup
  Set<String> _datesWithData = {}; // holds dates that have reports filed

  // Staff-specific state
  String? _adminUid;
  bool? _isTodayReportFiled;

  @override
  void initState() {
    super.initState();
    if (!widget.isStaff) {
      _checkUserConfig();
    } else {
      _checkStaffReportStatus();
    }
  }

  Future<void> _checkUserConfig() async {
    final config = await FirestoreService.getUserConfig();
    Map<String, dynamic>? totalReport;
    Set<String> datesWithData = {};

    if (config != null) {
      totalReport = await FirestoreService.getTotalReport();
      if (totalReport != null && totalReport['dates_with_data'] != null) {
        final List<dynamic> dates =
            totalReport['dates_with_data'] as List<dynamic>;
        datesWithData = dates.map((date) => date.toString()).toSet();
      }

      // Validate and update FCM token
      await FCMService.validateAndUpdateToken();
    }

    if (mounted) {
      setState(() {
        _hasConfig = config != null;
        if (config != null && config['business_name'] != null) {
          _businessName = config['business_name'] as String;
        }
        _userConfig = config;
        _totalReport = totalReport;
        _datesWithData = datesWithData;
        _isLoading = false;
      });
    }
  }

  // Public method to refresh data - called when navigating to home
  Future<void> refreshData() async {
    if (!widget.isStaff) {
      setState(() {
        _isLoading = true;
      });
      await _checkUserConfig();
    } else {
      await _checkStaffReportStatus();
    }
  }

  Future<void> _checkStaffReportStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get admin UID
      final adminUid = await FirestoreService.getStaffAdminUid();

      if (adminUid != null) {
        // Check if today's report is filed
        final isTodayReportFiled =
            await FirestoreService.isTodayReportFiledForAdmin(adminUid);

        // Validate and update FCM token for staff
        await FCMService.validateAndUpdateToken();

        if (mounted) {
          setState(() {
            _adminUid = adminUid;
            _isTodayReportFiled = isTodayReportFiled;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error checking staff report status: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  static Future<void> _handleLogout(BuildContext context) async {
    try {
      await AuthService.signOut();
      // Navigation will be handled automatically by AuthWrapper
      // when the authentication state changes
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper method to check if today's report has been filed (for regular users)
  bool _isTodayReportFiledForRegularUser() {
    final today = DateTime.now();
    final todayString =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return _datesWithData.contains(todayString);
  }

  // Helper method to get display name for item code
  String _getItemDisplayName(String code) {
    if (_userConfig == null || _userConfig!['items'] == null) {
      return code;
    }

    final List<dynamic> items = _userConfig!['items'] as List<dynamic>;
    for (var item in items) {
      if (item is Map<String, dynamic> && item['code'] == code) {
        final String? name = item['name'];
        if (name != null && name.isNotEmpty) {
          return '$name ($code)';
        }
      }
    }
    return code;
  }

  // Define a comprehensive color palette for pie charts
  static const List<Color> _colorPalette = [
    Color(0xFF6A5AE0), // Purple
    Color(0xFF29C7AC), // Teal
    Color(0xFFFFCE56), // Yellow
    Color(0xFFEF5350), // Red
    Color(0xFF4CAF50), // Green
    Color(0xFF2196F3), // Blue
    Color(0xFFFF9800), // Orange
    Color(0xFF9C27B0), // Deep Purple
    Color(0xFF00BCD4), // Cyan
    Color(0xFF8BC34A), // Light Green
    Color(0xFFFFC107), // Amber
    Color(0xFFE91E63), // Pink
    Color(0xFF795548), // Brown
    Color(0xFF607D8B), // Blue Grey
    Color(0xFF3F51B5), // Indigo
  ];

  Widget _buildTotalRow(String label, String value, {bool isProfit = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.quicksand(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
            height: 1.25,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.quicksand(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isProfit ? const Color(0xFF4CAF50) : Colors.black,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    // Show staff-specific UI
    if (widget.isStaff) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
            child: Column(
              children: [
                SizedBox(height: size.height * 0.025),
                // Header with Business Keeping title and logout
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Business Keeping',
                        style: GoogleFonts.quicksand(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                          height: 1.25,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.black,
                        backgroundImage:
                            AuthService.currentUser?.photoURL != null
                            ? NetworkImage(AuthService.currentUser!.photoURL!)
                            : null,
                        onBackgroundImageError: (exception, stackTrace) {
                          // If image fails to load, it will fall back to the black background
                        },
                      ),
                      onSelected: (String value) async {
                        if (value == 'logout') {
                          _handleLogout(context);
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'logout',
                              child: Row(
                                children: [
                                  Icon(Icons.logout, color: Colors.black),
                                  SizedBox(width: 12),
                                  Text(
                                    'Log out',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                    ),
                  ],
                ),
                // Spacer to push content to center
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Daily report status
                        if (_isTodayReportFiled == true)
                          // Report has been filed
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 20),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF4CAF50),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 48,
                                    color: const Color(0xFF4CAF50),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Report has been filed for today',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.quicksand(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF4CAF50),
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () async {
                                      final result = await Navigator.of(context)
                                          .push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const StaffDataInputScreen(),
                                            ),
                                          );
                                      // Refresh status after returning from data input
                                      if (result == true) {
                                        _checkStaffReportStatus();
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4CAF50),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      'Edit Report',
                                      style: GoogleFonts.quicksand(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (_isTodayReportFiled == false)
                          // Report hasn't been filed
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 20),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF975F).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFFF975F),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 48,
                                    color: const Color(0xFFFF975F),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Today\'s report hasn\'t been filed',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.quicksand(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFFF975F),
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () async {
                                      final result = await Navigator.of(context)
                                          .push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const StaffDataInputScreen(),
                                            ),
                                          );
                                      // Refresh status after returning from data input
                                      if (result == true) {
                                        _checkStaffReportStatus();
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF975F),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      'File Now',
                                      style: GoogleFonts.quicksand(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          // Loading or error state
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 20),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.grey[300]!,
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 48,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Unable to check report status',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.quicksand(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Regular user UI
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: size.height * 0.025),
                      // Header
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _businessName,
                              style: GoogleFonts.quicksand(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                                height: 1.25,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.black,
                              backgroundImage:
                                  AuthService.currentUser?.photoURL != null
                                  ? NetworkImage(
                                      AuthService.currentUser!.photoURL!,
                                    )
                                  : null,
                              onBackgroundImageError: (exception, stackTrace) {
                                // If image fails to load, it will fall back to the black background
                              },
                            ),
                            onSelected: (String value) async {
                              if (value == 'settings') {
                                final result = await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                );
                                // If config was saved, reload the config
                                if (result == true) {
                                  _checkUserConfig();
                                }
                              } else if (value == 'logout') {
                                // Implement logout functionality
                                _handleLogout(context);
                              }
                            },
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<String>>[
                                  const PopupMenuItem<String>(
                                    value: 'settings',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.settings,
                                          color: Colors.black,
                                        ),
                                        SizedBox(width: 12),
                                        Text(
                                          'Settings',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'logout',
                                    child: Row(
                                      children: [
                                        Icon(Icons.logout, color: Colors.black),
                                        SizedBox(width: 12),
                                        Text(
                                          'Log out',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Caution card - only show if user has config and today's report hasn't been filed
                      if (_hasConfig && !_isTodayReportFiledForRegularUser())
                        GestureDetector(
                          onTap: () async {
                            // Navigate to daily report edit screen for today's date
                            final today = DateTime.now();
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    DailyReportEditScreen(date: today),
                              ),
                            );
                            // Refresh data if a report was created/edited
                            if (result == true) {
                              _checkUserConfig();
                            }
                          },
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF975F),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 18,
                            ),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Daily report hasn't been Filed!",
                                        style: GoogleFonts.quicksand(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                          height: 1.25,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Click here to file it",
                                        style: GoogleFonts.quicksand(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.white70,
                                          height: 1.25,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (!_hasConfig)
                        const SizedBox(height: 200)
                      else
                        const SizedBox(height: 24),
                      // Show config prompt if no config
                      if (!_hasConfig)
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 40),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.settings_outlined,
                                  size: 48,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Please configure your business by going to settings',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.quicksand(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        _buildFullReportSection(size),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildFullReportSection(Size size) {
    if (_totalReport == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Full Report',
            style: GoogleFonts.quicksand(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.black,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 200),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Center(
              child: Text(
                'No data',
                style: GoogleFonts.quicksand(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      );
    }

    final Map<String, dynamic> rawItemsSales =
        (_totalReport!['items_sales'] as Map<String, dynamic>? ?? {});
    final Map<String, dynamic> rawVendorSales =
        (_totalReport!['vendor_sales'] as Map<String, dynamic>? ?? {});

    // Convert counts to percentage share for pie charts
    Map<String, double> dataMap = {};
    Map<String, double> vendorDataMap = {};
    final double totalItemCount = rawItemsSales.values
        .map((v) => (v is num) ? v.toDouble() : 0.0)
        .fold(0.0, (a, b) => a + b);
    final double totalVendorCount = rawVendorSales.values
        .map((v) => (v is num) ? v.toDouble() : 0.0)
        .fold(0.0, (a, b) => a + b);

    rawItemsSales.forEach((key, value) {
      final double count = (value is num) ? value.toDouble() : 0.0;
      final String displayName = _getItemDisplayName(key);
      dataMap[displayName] = totalItemCount > 0
          ? (count / totalItemCount) * 100
          : 0.0;
    });
    rawVendorSales.forEach((key, value) {
      final double count = (value is num) ? value.toDouble() : 0.0;
      vendorDataMap[key] = totalVendorCount > 0
          ? (count / totalVendorCount) * 100
          : 0.0;
    });

    // Sort data maps by percentage values in descending order
    final sortedItemEntries = dataMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedVendorEntries = vendorDataMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Create sorted data maps
    final Map<String, double> sortedDataMap = Map.fromEntries(
      sortedItemEntries,
    );
    final Map<String, double> sortedVendorDataMap = Map.fromEntries(
      sortedVendorEntries,
    );

    // Create color lists for each chart (colors will be assigned in sorted order)
    final List<Color> itemColors = sortedDataMap.keys
        .toList()
        .asMap()
        .entries
        .map((entry) => _colorPalette[entry.key % _colorPalette.length])
        .toList();

    final List<Color> vendorColors = sortedVendorDataMap.keys
        .toList()
        .asMap()
        .entries
        .map((entry) => _colorPalette[entry.key % _colorPalette.length])
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Full Report',
          style: GoogleFonts.quicksand(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.black,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 16),
        // Product Contribution Section
        Text(
          'Product Contribution (%)',
          style: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1C1C1C),
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        if (sortedDataMap.isNotEmpty)
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: min(280, size.width * 0.6),
                  height: min(280, size.width * 0.6),
                  child: PieChart(
                    dataMap: sortedDataMap,
                    animationDuration: const Duration(milliseconds: 800),
                    chartType: ChartType.disc,
                    baseChartColor: const Color(0xFFD9D9D9),
                    colorList: itemColors,
                    chartValuesOptions: const ChartValuesOptions(
                      showChartValues: false,
                    ),
                    legendOptions: const LegendOptions(showLegends: false),
                  ),
                ),
              ],
            ),
          ),
        if (sortedDataMap.isNotEmpty) const SizedBox(height: 16),
        // Product Legend
        if (sortedDataMap.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: List.generate(sortedDataMap.length, (index) {
                final String key = sortedDataMap.keys.elementAt(index);
                final double value = sortedDataMap[key] ?? 0;
                final Color itemColor = itemColors[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: itemColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          key,
                          style: GoogleFonts.quicksand(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                            height: 1.25,
                          ),
                        ),
                      ),
                      Text(
                        '${value.toStringAsFixed(1)}%',
                        style: GoogleFonts.quicksand(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        if (sortedDataMap.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Center(
              child: Text(
                'No product sales data yet',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        // Vendor Contribution Section
        Text(
          'Vendor Contribution (%)',
          style: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1C1C1C),
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        if (sortedVendorDataMap.isNotEmpty)
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: min(280, size.width * 0.6),
                  height: min(280, size.width * 0.6),
                  child: PieChart(
                    dataMap: sortedVendorDataMap,
                    animationDuration: const Duration(milliseconds: 800),
                    chartType: ChartType.disc,
                    baseChartColor: const Color(0xFFD9D9D9),
                    colorList: vendorColors,
                    chartValuesOptions: const ChartValuesOptions(
                      showChartValues: false,
                    ),
                    legendOptions: const LegendOptions(showLegends: false),
                  ),
                ),
              ],
            ),
          ),
        if (sortedVendorDataMap.isNotEmpty) const SizedBox(height: 16),
        // Vendor Legend
        if (sortedVendorDataMap.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: List.generate(sortedVendorDataMap.length, (index) {
                final String key = sortedVendorDataMap.keys.elementAt(index);
                final double value = sortedVendorDataMap[key] ?? 0;
                final Color vendorColor = vendorColors[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: vendorColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          key,
                          style: GoogleFonts.quicksand(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                            height: 1.25,
                          ),
                        ),
                      ),
                      Text(
                        '${value.toStringAsFixed(1)}%',
                        style: GoogleFonts.quicksand(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        if (sortedVendorDataMap.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Center(
              child: Text(
                'No vendor sales data yet',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        // Totaly Section
        Text(
          'Totaly',
          style: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1C1C1C),
            height: 1.25,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildTotalRow(
                'Total Sales',
                (_totalReport!['total_sales'] is num)
                    ? (_totalReport!['total_sales'] as num).toString()
                    : '${_totalReport!['total_sales'] ?? '0'}',
              ),
              const SizedBox(height: 12),
              _buildTotalRow(
                'Total Revenue',
                '₹${(_totalReport!['total_revenue'] is num) ? (_totalReport!['total_revenue'] as num).toStringAsFixed(2) : (_totalReport!['total_revenue'] ?? '0')}',
              ),
              const SizedBox(height: 12),
              _buildTotalRow(
                'Total Expenses',
                '₹${(_totalReport!['total_expenses'] is num) ? (_totalReport!['total_expenses'] as num).toStringAsFixed(2) : (_totalReport!['total_expenses'] ?? '0')}',
              ),
              const SizedBox(height: 12),
              _buildTotalRow(
                'Total Profit',
                '₹${(_totalReport!['net_profit'] is num) ? (_totalReport!['net_profit'] as num).toStringAsFixed(2) : (_totalReport!['net_profit'] ?? '0')}',
                isProfit: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
