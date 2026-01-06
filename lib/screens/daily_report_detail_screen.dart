import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pie_chart/pie_chart.dart';
import 'daily_report_edit_screen.dart';
import '../firestore_service.dart';
import '../invoice_service.dart';
import '../auth_service.dart';

class DailyReportDetailScreen extends StatefulWidget {
  final DateTime date;

  const DailyReportDetailScreen({super.key, required this.date});

  @override
  State<DailyReportDetailScreen> createState() =>
      _DailyReportDetailScreenState();
}

class _DailyReportDetailScreenState extends State<DailyReportDetailScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _dailyReport;
  Map<String, dynamic>? _userConfig;
  bool _hidePieCharts = false;
  Map<String, int> _priceMismatches = {}; // itemCode -> currentConfigPrice
  Map<String, bool> _useNewPrices = {}; // itemCode -> useNewPrice
  bool _hasPriceMismatches = false; // Track if we have price mismatches
  Map<String, Map<String, double>> _specialPriceMismatches =
      {}; // vendor -> {itemCode -> currentSpecialPrice}
  Map<String, Map<String, bool>> _useNewSpecialPrices =
      {}; // vendor -> {itemCode -> useNewSpecialPrice}
  String? _reportAddedBy; // Name of who added the report
  String? _reportAddedAt; // When the report was added

  String get _dateLabel =>
      '${widget.date.day.toString().padLeft(2, '0')}/${widget.date.month.toString().padLeft(2, '0')}/${widget.date.year}';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Load user config for item names
      final config = await FirestoreService.getUserConfig();
      // Load daily report data
      final report = await FirestoreService.getDailyReport(widget.date);
      // Load metadata to get who added the report
      final metadata = await FirestoreService.getDailyReportMetadata(
        widget.date,
      );

      if (mounted) {
        setState(() {
          _userConfig = config;
          _dailyReport = report;
          _isLoading = false;
        });

        // Process metadata to get who added the report
        if (metadata != null) {
          await _processMetadata(metadata);
        }

        // Check for deprecated items (items in report but not in config)
        if (report != null && config != null) {
          _checkForDeprecatedItems(report, config);
          _checkForPriceMismatches(report, config);
          _checkForSpecialPriceMismatches(report, config);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _processMetadata(Map<String, dynamic> metadata) async {
    try {
      final String? addedByUid = metadata['added_by'] as String?;

      // Handle both String and Timestamp formats for added_at
      String? addedAt;
      if (metadata['added_at'] is String) {
        addedAt = metadata['added_at'] as String?;
      } else if (metadata['added_at_local'] is String) {
        // Fallback to added_at_local if available
        addedAt = metadata['added_at_local'] as String?;
      } else if (metadata['added_at'] != null) {
        // If it's a Timestamp, convert it to a readable string
        final timestamp = metadata['added_at'] as dynamic;
        if (timestamp.toDate != null) {
          final date = timestamp.toDate() as DateTime;
          addedAt = _formatDateTime(date);
        }
      }

      if (addedByUid != null) {
        // Get current user to check if it's the admin
        final currentUser = AuthService.currentUser;
        if (currentUser != null) {
          // Check if current user is staff
          final isStaff = await FirestoreService.isUserStaff();
          if (isStaff) {
            // Current user is staff, check if the added_by is the admin
            final adminUid = await FirestoreService.getStaffAdminUid();
            if (adminUid != null && addedByUid == adminUid) {
              // It's the admin who added the report
              setState(() {
                _reportAddedBy = 'Admin';
                _reportAddedAt = addedAt;
              });
            } else {
              // It's another staff member, get their name
              final staffName = await FirestoreService.getStaffNameByUid(
                addedByUid,
              );
              setState(() {
                _reportAddedBy = staffName ?? 'Unknown Staff';
                _reportAddedAt = addedAt;
              });
            }
          } else {
            // Current user is admin
            if (currentUser.uid == addedByUid) {
              // It's the admin who added the report
              setState(() {
                _reportAddedBy = 'Admin';
                _reportAddedAt = addedAt;
              });
            } else {
              // It's a staff member, get their name
              final staffName = await FirestoreService.getStaffNameByUid(
                addedByUid,
              );
              setState(() {
                _reportAddedBy = staffName ?? 'Unknown Staff';
                _reportAddedAt = addedAt;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error processing metadata: $e');
    }
  }

  /// Helper method to get month name from month number
  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  /// Formats DateTime with relative dates and normal time format
  String _formatDateTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final reportDate = DateTime(date.year, date.month, date.day);

    String dateStr;
    if (reportDate == today) {
      dateStr = 'Today';
    } else if (reportDate == yesterday) {
      dateStr = 'Yesterday';
    } else {
      dateStr = '${date.day} ${_getMonthName(date.month)} ${date.year}';
    }

    // Format time in normal format (12-hour with AM/PM)
    final hour = date.hour;
    final minute = date.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final timeStr = '$displayHour:${minute.toString().padLeft(2, '0')} $period';

    return '$dateStr at $timeStr';
  }

  void _checkForDeprecatedItems(
    Map<String, dynamic> report,
    Map<String, dynamic> config,
  ) {
    final Map<String, dynamic> itemsSales =
        report['items_sales'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> vendorSales =
        report['vendor_sales'] as Map<String, dynamic>? ?? {};

    // Get current config items
    final Set<String> configItemCodes = {};
    if (config['items'] != null) {
      final List<dynamic> configItems = config['items'] as List<dynamic>;
      for (var item in configItems) {
        if (item is Map<String, dynamic>) {
          final String code = item['code'] ?? '';
          if (code.isNotEmpty) {
            configItemCodes.add(code);
          }
        }
      }
    }

    // Get current config vendors
    final Set<String> configVendorNames = {};
    if (config['vendors'] != null) {
      final List<dynamic> configVendors = config['vendors'] as List<dynamic>;
      for (var vendor in configVendors) {
        if (vendor is String && vendor.isNotEmpty) {
          configVendorNames.add(vendor);
        }
      }
    }

    // Find deprecated items
    final Set<String> deprecatedItems = {};
    itemsSales.forEach((code, quantity) {
      if (!configItemCodes.contains(code)) {
        deprecatedItems.add(code);
      }
    });

    // Find deprecated vendors
    final Set<String> deprecatedVendors = {};
    vendorSales.forEach((vendorName, vendorData) {
      if (!configVendorNames.contains(vendorName)) {
        deprecatedVendors.add(vendorName);
      }
    });

    // Show warning if deprecated items or vendors found
    if (deprecatedItems.isNotEmpty || deprecatedVendors.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          String message = 'Note: This report contains ';
          final List<String> parts = [];

          if (deprecatedItems.isNotEmpty) {
            parts.add(
              '${deprecatedItems.length} item(s) not in current config: ${deprecatedItems.join(", ")}',
            );
          }
          if (deprecatedVendors.isNotEmpty) {
            parts.add(
              '${deprecatedVendors.length} vendor(s) not in current config: ${deprecatedVendors.join(", ")}',
            );
          }

          message += parts.join(' and ');
          message += '. Historical data shown.';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      });
    }
  }

  void _checkForPriceMismatches(
    Map<String, dynamic> report,
    Map<String, dynamic> config,
  ) {
    final Map<String, dynamic> itemPricesSnapshot =
        report['item_prices_snapshot'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> itemsSales =
        report['items_sales'] as Map<String, dynamic>? ?? {};

    // Get current config prices
    final Map<String, int> configPrices = {};
    if (config['items'] != null) {
      final List<dynamic> configItems = config['items'] as List<dynamic>;
      for (var item in configItems) {
        if (item is Map<String, dynamic>) {
          final String code = item['code'] ?? '';
          final int price = (item['price'] is num)
              ? (item['price'] as num).toInt()
              : 0;
          if (code.isNotEmpty) {
            configPrices[code] = price;
          }
        }
      }
    }

    // Find price mismatches
    final Map<String, int> mismatches = {};
    itemsSales.forEach((itemCode, quantity) {
      final int qty = (quantity is num) ? quantity.toInt() : 0;
      if (qty > 0 &&
          itemPricesSnapshot.containsKey(itemCode) &&
          configPrices.containsKey(itemCode)) {
        final int snapshotPrice = (itemPricesSnapshot[itemCode] is num)
            ? (itemPricesSnapshot[itemCode] as num).toInt()
            : 0;
        final int configPrice = configPrices[itemCode] ?? 0;

        if (snapshotPrice != configPrice) {
          mismatches[itemCode] = configPrice;
        }
      }
    });

    if (mismatches.isNotEmpty) {
      _priceMismatches = mismatches;
      _hasPriceMismatches = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showPriceMismatchDialog(mismatches, itemPricesSnapshot);
        }
      });
    }
  }

  void _showPriceMismatchDialog(
    Map<String, int> mismatches,
    Map<String, dynamic> itemPricesSnapshot,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Price Mismatch Detected',
                style: GoogleFonts.quicksand(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Some item prices have changed since this report was created. Choose which prices to use:',
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...mismatches.entries.map((entry) {
                      final String itemCode = entry.key;
                      final int newPrice = entry.value;
                      final double oldPrice =
                          (itemPricesSnapshot[itemCode] is num)
                          ? (itemPricesSnapshot[itemCode] as num).toDouble()
                          : 0.0;
                      final bool useNewPrice = _useNewPrices[itemCode] ?? false;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                itemCode,
                                style: GoogleFonts.quicksand(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Original Price: ₹$oldPrice',
                                          style: GoogleFonts.quicksand(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                        Text(
                                          'Current Price: ₹$newPrice',
                                          style: GoogleFonts.quicksand(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.blue[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: useNewPrice,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        _useNewPrices[itemCode] = value;
                                      });
                                    },
                                    activeColor: Colors.blue,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      // Trigger rebuild to recalculate totals with current selections
                      _recalculateTotals();
                    });
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Apply Selection',
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  double _getNormalPriceForItem(String itemCode) {
    // Get normal price from config items
    if (_userConfig != null && _userConfig!['items'] != null) {
      final List<dynamic> configItems = _userConfig!['items'] as List<dynamic>;
      for (var item in configItems) {
        if (item is Map<String, dynamic> && item['code'] == itemCode) {
          return (item['price'] is num) ? item['price'].toDouble() : 0.0;
        }
      }
    }
    return 0.0;
  }

  /// Resolve price for an item, considering mismatches and special prices
  _PriceResolution _resolvePriceForVendor(
    String itemCode, {
    String? vendorName,
  }) {
    double price = 0.0;
    bool usedSpecialPrice = false;

    // Handle normal price mismatches first
    if (_priceMismatches.containsKey(itemCode) &&
        _useNewPrices.containsKey(itemCode)) {
      if (_useNewPrices[itemCode] == true) {
        price = _priceMismatches[itemCode]?.toDouble() ?? 0.0;
      } else {
        final snapshotPrice =
            _dailyReport?['item_prices_snapshot'] as Map<String, dynamic>? ??
            {};
        price = (snapshotPrice[itemCode] is num)
            ? (snapshotPrice[itemCode] as num).toDouble()
            : 0.0;
      }
      return _PriceResolution(price: price, usedSpecialPrice: usedSpecialPrice);
    }

    // Special price handling (only if vendor is known)
    if (vendorName != null) {
      // Special price mismatches (changed/removed)
      if (_specialPriceMismatches.containsKey(vendorName) &&
          _specialPriceMismatches[vendorName]!.containsKey(itemCode) &&
          _useNewSpecialPrices.containsKey(vendorName) &&
          _useNewSpecialPrices[vendorName]!.containsKey(itemCode)) {
        if (_useNewSpecialPrices[vendorName]![itemCode] == true) {
          price = _specialPriceMismatches[vendorName]![itemCode]!.toDouble();
          usedSpecialPrice = true;
        } else {
          final specialPricesSnapshot =
              _dailyReport?['special_prices'] as Map<String, dynamic>? ?? {};
          if (specialPricesSnapshot.containsKey(vendorName)) {
            final vendorSpecialPrices =
                specialPricesSnapshot[vendorName] as Map<String, dynamic>? ??
                {};
            if (vendorSpecialPrices.containsKey(itemCode)) {
              price = (vendorSpecialPrices[itemCode] is num)
                  ? (vendorSpecialPrices[itemCode] as num).toDouble()
                  : 0.0;
              usedSpecialPrice = true;
            }
          }
        }
      } else {
        // Check for configured special prices for this vendor
        if (_userConfig != null && _userConfig!['special_prices'] != null) {
          final specialPrices =
              _userConfig!['special_prices'] as Map<String, dynamic>;
          if (specialPrices.containsKey(vendorName)) {
            final vendorSpecialPrices =
                specialPrices[vendorName] as Map<String, dynamic>? ?? {};
            if (vendorSpecialPrices.containsKey(itemCode)) {
              final specialPrice = vendorSpecialPrices[itemCode];
              if (specialPrice is num) {
                price = specialPrice.toDouble();
                usedSpecialPrice = true;
              }
            }
          }
        }

        // Fallback to snapshot special prices if present
        if (price == 0.0) {
          final specialPricesSnapshot =
              _dailyReport?['special_prices'] as Map<String, dynamic>? ?? {};
          if (specialPricesSnapshot.containsKey(vendorName)) {
            final vendorSpecialPrices =
                specialPricesSnapshot[vendorName] as Map<String, dynamic>? ??
                {};
            if (vendorSpecialPrices.containsKey(itemCode)) {
              price = (vendorSpecialPrices[itemCode] is num)
                  ? (vendorSpecialPrices[itemCode] as num).toDouble()
                  : 0.0;
              usedSpecialPrice = true;
            }
          }
        }
      }
    }

    // Default fallback: snapshot price, then config price
    if (price == 0.0) {
      final itemPricesSnapshot =
          _dailyReport?['item_prices_snapshot'] as Map<String, dynamic>? ?? {};
      if (itemPricesSnapshot.containsKey(itemCode)) {
        price = (itemPricesSnapshot[itemCode] is num)
            ? (itemPricesSnapshot[itemCode] as num).toDouble()
            : 0.0;
      } else if (_userConfig != null && _userConfig!['items'] != null) {
        final List<dynamic> configItems =
            _userConfig!['items'] as List<dynamic>;
        for (var item in configItems) {
          if (item is Map<String, dynamic> && item['code'] == itemCode) {
            price = (item['price'] is num) ? item['price'].toDouble() : 0.0;
            break;
          }
        }
      }
    }

    return _PriceResolution(price: price, usedSpecialPrice: usedSpecialPrice);
  }

  void _checkForSpecialPriceMismatches(
    Map<String, dynamic> report,
    Map<String, dynamic> config,
  ) {
    final Map<String, dynamic> specialPricesSnapshot =
        report['special_prices'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> vendorSales =
        report['vendor_sales'] as Map<String, dynamic>? ?? {};

    // Get current config special prices
    final Map<String, Map<String, double>> configSpecialPrices = {};
    if (config['special_prices'] != null) {
      final specialPrices = config['special_prices'] as Map<String, dynamic>;
      specialPrices.forEach((vendorName, vendorPrices) {
        if (vendorPrices is Map<String, dynamic>) {
          final Map<String, double> parsed = {};
          vendorPrices.forEach((itemCode, price) {
            if (price is num) {
              parsed[itemCode] = price.toDouble();
            }
          });
          if (parsed.isNotEmpty) {
            configSpecialPrices[vendorName] = parsed;
          }
        }
      });
    }

    // Find special price mismatches
    final Map<String, Map<String, double>> mismatches = {};
    vendorSales.forEach((vendorName, vendorData) {
      if (vendorData is Map<String, dynamic>) {
        final vendorItems = vendorData['items'] as Map<String, dynamic>? ?? {};
        final Map<String, double> vendorMismatches = {};

        vendorItems.forEach((itemCode, quantity) {
          final int qty = (quantity is num) ? quantity.toInt() : 0;
          if (qty > 0 && specialPricesSnapshot.containsKey(vendorName)) {
            final snapshotSpecialPrices =
                specialPricesSnapshot[vendorName] as Map<String, dynamic>? ??
                {};

            if (snapshotSpecialPrices.containsKey(itemCode)) {
              final double snapshotPrice =
                  (snapshotSpecialPrices[itemCode] is num)
                  ? (snapshotSpecialPrices[itemCode] as num).toDouble()
                  : 0.0;

              // Check if config has special prices for this vendor and item
              if (configSpecialPrices.containsKey(vendorName)) {
                final configSpecialPricesForVendor =
                    configSpecialPrices[vendorName]!;
                if (configSpecialPricesForVendor.containsKey(itemCode)) {
                  // Both have special prices - check if they differ
                  final double configPrice =
                      configSpecialPricesForVendor[itemCode] ?? 0.0;
                  if (snapshotPrice != configPrice) {
                    vendorMismatches[itemCode] = configPrice;
                  }
                } else {
                  // Snapshot has special price but config doesn't - use normal price
                  final normalPrice = _getNormalPriceForItem(itemCode);
                  vendorMismatches[itemCode] = normalPrice;
                }
              } else {
                // Snapshot has special price but config doesn't have special prices for this vendor - use normal price
                final normalPrice = _getNormalPriceForItem(itemCode);
                vendorMismatches[itemCode] = normalPrice;
              }
            }
          }
        });

        if (vendorMismatches.isNotEmpty) {
          mismatches[vendorName] = vendorMismatches;
        }
      }
    });

    if (mismatches.isNotEmpty) {
      _specialPriceMismatches = mismatches;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showSpecialPriceMismatchDialog(mismatches, specialPricesSnapshot);
        }
      });
    }
  }

  void _showSpecialPriceMismatchDialog(
    Map<String, Map<String, double>> mismatches,
    Map<String, dynamic> specialPricesSnapshot,
  ) {
    // Initialize default choices (all set to true - use current prices)
    for (final vendorName in mismatches.keys) {
      _useNewSpecialPrices[vendorName] = {};
      for (final itemCode in mismatches[vendorName]!.keys) {
        _useNewSpecialPrices[vendorName]![itemCode] =
            true; // Default to current price
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Special Price Mismatch Detected',
                style: GoogleFonts.quicksand(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Some special prices have changed or been removed since this report was created. Choose which prices to use:',
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...mismatches.entries.map((vendorEntry) {
                      final String vendorName = vendorEntry.key;
                      final Map<String, double> vendorMismatches =
                          vendorEntry.value;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vendor: $vendorName',
                                style: GoogleFonts.quicksand(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.blue[700],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...vendorMismatches.entries.map((itemEntry) {
                                final String itemCode = itemEntry.key;
                                final double newPrice = itemEntry.value;
                                final double oldPrice =
                                    (specialPricesSnapshot[vendorName]
                                        is Map<String, dynamic>)
                                    ? ((specialPricesSnapshot[vendorName]
                                                  as Map<
                                                    String,
                                                    dynamic
                                                  >)[itemCode]
                                              is num)
                                          ? ((specialPricesSnapshot[vendorName]
                                                        as Map<
                                                          String,
                                                          dynamic
                                                        >)[itemCode]
                                                    as num)
                                                .toDouble()
                                          : 0.0
                                    : 0.0;
                                final bool useNewPrice =
                                    _useNewSpecialPrices[vendorName]?[itemCode] ??
                                    false;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  color: Colors.grey[50],
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          itemCode,
                                          style: GoogleFonts.quicksand(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Original Price: ₹${oldPrice.toStringAsFixed(2)}',
                                                    style:
                                                        GoogleFonts.quicksand(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color:
                                                              Colors.grey[700],
                                                        ),
                                                  ),
                                                  Text(
                                                    'Current Price: ₹${newPrice.toStringAsFixed(2)}',
                                                    style:
                                                        GoogleFonts.quicksand(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color:
                                                              Colors.blue[700],
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Switch(
                                              value: useNewPrice,
                                              onChanged: (value) {
                                                setDialogState(() {
                                                  _useNewSpecialPrices[vendorName] ??=
                                                      {};
                                                  _useNewSpecialPrices[vendorName]![itemCode] =
                                                      value;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _recalculateTotals();
                  },
                  child: Text(
                    'Apply Changes',
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _recalculateTotals() {
    // This method will be called when user applies price selections
    // Trigger a rebuild to recalculate totals with new price selections
    setState(() {
      // The state change will trigger a rebuild and recalculation
      // The _calculateTotals() method will be called in the build method
      // and will use the updated _useNewSpecialPrices selections
    });
  }

  // Calculate totals based on current price selections (preserve decimals)
  Map<String, num> _calculateRecalculatedTotals() {
    if (!_hasPriceMismatches || _dailyReport == null) {
      // No price mismatches, return original values with proper type conversion
      return {
        'total_sales': (_dailyReport!['total_sales'] is num)
            ? (_dailyReport!['total_sales'] as num).toInt()
            : 0,
        'total_revenue': (_dailyReport!['total_revenue'] is num)
            ? (_dailyReport!['total_revenue'] as num).toDouble()
            : 0.0,
        'total_expenses': (_dailyReport!['total_expenses'] is num)
            ? (_dailyReport!['total_expenses'] as num).toDouble()
            : 0.0,
        'addition_revenue': (_dailyReport!['addition_revenue'] is num)
            ? (_dailyReport!['addition_revenue'] as num).toDouble()
            : 0.0,
        'net_profit': (_dailyReport!['net_profit'] is num)
            ? (_dailyReport!['net_profit'] as num).toDouble()
            : 0.0,
      };
    }

    final Map<String, dynamic> itemsSales =
        _dailyReport!['items_sales'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> itemPricesSnapshot =
        _dailyReport!['item_prices_snapshot'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> expenses =
        _dailyReport!['expenses'] as Map<String, dynamic>? ?? {};

    int totalSales = 0;
    double totalRevenue = 0.0;

    // Recalculate based on user's price selections
    itemsSales.forEach((itemCode, quantity) {
      final int qty = (quantity is num) ? quantity.toInt() : 0;
      if (qty > 0) {
        totalSales += qty;

        // Get price based on user's choice
        double pricePerItem = 0.0;

        // FIRST: Check for regular price mismatches (snapshot vs config)
        if (_priceMismatches.containsKey(itemCode) &&
            _useNewPrices.containsKey(itemCode)) {
          if (_useNewPrices[itemCode] == true) {
            // Use current config price
            pricePerItem = _priceMismatches[itemCode]?.toDouble() ?? 0.0;
          } else {
            // Use original snapshot price
            pricePerItem = (itemPricesSnapshot[itemCode] is num)
                ? (itemPricesSnapshot[itemCode] as num).toDouble()
                : 0.0;
          }
        } else {
          // No price mismatch - check for special prices
          // Find which vendor sold this item
          String? sellingVendor;
          final vendorSales =
              _dailyReport?['vendor_sales'] as Map<String, dynamic>? ?? {};
          for (final vendorName in vendorSales.keys) {
            final vendorData =
                vendorSales[vendorName] as Map<String, dynamic>? ?? {};
            final vendorItems =
                vendorData['items'] as Map<String, dynamic>? ?? {};
            if (vendorItems.containsKey(itemCode)) {
              sellingVendor = vendorName;
              break;
            }
          }

          // Check for special price mismatches for the selling vendor
          bool hasSpecialPriceMismatch = false;
          if (sellingVendor != null &&
              _specialPriceMismatches.containsKey(sellingVendor)) {
            if (_specialPriceMismatches[sellingVendor]!.containsKey(itemCode) &&
                _useNewSpecialPrices.containsKey(sellingVendor) &&
                _useNewSpecialPrices[sellingVendor]!.containsKey(itemCode)) {
              final useNewPrice =
                  _useNewSpecialPrices[sellingVendor]![itemCode];
              if (useNewPrice == true) {
                // Use current special price
                pricePerItem =
                    _specialPriceMismatches[sellingVendor]![itemCode]!
                        .toDouble();
                hasSpecialPriceMismatch = true;
              } else {
                // Use original special price from snapshot
                final specialPricesSnapshot =
                    _dailyReport?['special_prices'] as Map<String, dynamic>? ??
                    {};
                if (specialPricesSnapshot.containsKey(sellingVendor)) {
                  final vendorSpecialPrices =
                      specialPricesSnapshot[sellingVendor]
                          as Map<String, dynamic>? ??
                      {};
                  if (vendorSpecialPrices.containsKey(itemCode)) {
                    pricePerItem = (vendorSpecialPrices[itemCode] is num)
                        ? (vendorSpecialPrices[itemCode] as num).toDouble()
                        : 0.0;
                    hasSpecialPriceMismatch = true;
                  }
                }
              }
            }
          }

          if (!hasSpecialPriceMismatch) {
            // Check for special prices for the selling vendor
            bool foundSpecialPrice = false;
            if (sellingVendor != null &&
                _userConfig != null &&
                _userConfig!['special_prices'] != null) {
              final specialPrices =
                  _userConfig!['special_prices'] as Map<String, dynamic>;
              if (specialPrices.containsKey(sellingVendor)) {
                final vendorSpecialPrices =
                    specialPrices[sellingVendor] as Map<String, dynamic>? ?? {};
                if (vendorSpecialPrices.containsKey(itemCode)) {
                  final specialPrice = vendorSpecialPrices[itemCode];
                  if (specialPrice is num) {
                    pricePerItem = specialPrice.toDouble();
                    foundSpecialPrice = true;
                  }
                }
              }
            }

            if (!foundSpecialPrice) {
              // Default behavior: use snapshot first, then fall back to config
              if (itemPricesSnapshot.containsKey(itemCode)) {
                pricePerItem = (itemPricesSnapshot[itemCode] is num)
                    ? (itemPricesSnapshot[itemCode] as num).toDouble()
                    : 0.0;
              } else if (_userConfig != null && _userConfig!['items'] != null) {
                final List<dynamic> configItems =
                    _userConfig!['items'] as List<dynamic>;
                for (var item in configItems) {
                  if (item is Map<String, dynamic> &&
                      item['code'] == itemCode) {
                    pricePerItem = (item['price'] is num)
                        ? item['price'].toDouble()
                        : 0.0;
                    break;
                  }
                }
              }
            }
          }
        }

        totalRevenue += qty * pricePerItem;
      }
    });

    final double totalExpenses = expenses.values
        .fold(0.0, (num acc, val) => acc + (val is num ? val.toDouble() : 0.0))
        .toDouble();
    final double additionRevenue = (_dailyReport!['addition_revenue'] is num)
        ? (_dailyReport!['addition_revenue'] as num).toDouble()
        : 0.0;
    final double totalRevenueWithAddition = totalRevenue + additionRevenue;
    final double netProfit = totalRevenueWithAddition - totalExpenses;

    return {
      'total_sales': totalSales,
      'total_revenue': totalRevenueWithAddition,
      'total_expenses': totalExpenses,
      'addition_revenue': additionRevenue,
      'net_profit': netProfit,
    };
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

  // Generate invoice for a specific vendor
  Future<void> _generateInvoiceForVendor(
    String vendorName,
    Map<String, dynamic> vendorItems,
    Map<String, dynamic> itemPricesSnapshot,
  ) async {
    // Get current user and ID token
    final user = AuthService.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User not authenticated'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get the ID token
    String? idToken;
    try {
      idToken = await user.getIdToken();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to get authentication token: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (idToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to get authentication token'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Prepare items data for the invoice
    final Map<String, dynamic> items = {};
    int itemIndex = 1;
    int totalAmount = 0; // Track total amount

    vendorItems.forEach((itemCode, quantity) {
      final int qty = (quantity is num) ? quantity.toInt() : 0;
      if (qty > 0) {
        // Get item name from config
        String itemName = itemCode; // fallback to code
        if (_userConfig != null && _userConfig!['items'] != null) {
          final List<dynamic> configItems =
              _userConfig!['items'] as List<dynamic>;
          for (var item in configItems) {
            if (item is Map<String, dynamic> && item['code'] == itemCode) {
              final String? name = item['name'];
              if (name != null && name.isNotEmpty) {
                itemName = name;
                break;
              }
            }
          }
        }

        // Get price based on user's choice
        double price = 0.0;

        // FIRST: Check for regular price mismatches (snapshot vs config)
        if (_priceMismatches.containsKey(itemCode) &&
            _useNewPrices.containsKey(itemCode)) {
          if (_useNewPrices[itemCode] == true) {
            // Use current config price
            price = _priceMismatches[itemCode]?.toDouble() ?? 0.0;
          } else {
            // Use original snapshot price
            price = (itemPricesSnapshot[itemCode] is num)
                ? (itemPricesSnapshot[itemCode] as num).toDouble()
                : 0.0;
          }
        } else {
          // No price mismatch - check for special prices
          // Check for special price mismatches for this vendor
          bool hasSpecialPriceMismatch = false;
          if (_specialPriceMismatches.containsKey(vendorName)) {
            if (_specialPriceMismatches[vendorName]!.containsKey(itemCode) &&
                _useNewSpecialPrices.containsKey(vendorName) &&
                _useNewSpecialPrices[vendorName]!.containsKey(itemCode)) {
              if (_useNewSpecialPrices[vendorName]![itemCode] == true) {
                // Use current special price
                price = _specialPriceMismatches[vendorName]![itemCode]!
                    .toDouble();
                hasSpecialPriceMismatch = true;
              } else {
                // Use original special price from snapshot
                final specialPricesSnapshot =
                    _dailyReport?['special_prices'] as Map<String, dynamic>? ??
                    {};
                if (specialPricesSnapshot.containsKey(vendorName)) {
                  final vendorSpecialPrices =
                      specialPricesSnapshot[vendorName]
                          as Map<String, dynamic>? ??
                      {};
                  if (vendorSpecialPrices.containsKey(itemCode)) {
                    price = (vendorSpecialPrices[itemCode] is num)
                        ? (vendorSpecialPrices[itemCode] as num).toDouble()
                        : 0;
                    hasSpecialPriceMismatch = true;
                  }
                }
              }
            }
          }

          if (!hasSpecialPriceMismatch) {
            // Check for special prices for this vendor
            bool foundSpecialPrice = false;
            if (_userConfig != null && _userConfig!['special_prices'] != null) {
              final specialPrices =
                  _userConfig!['special_prices'] as Map<String, dynamic>;
              if (specialPrices.containsKey(vendorName)) {
                final vendorSpecialPrices =
                    specialPrices[vendorName] as Map<String, dynamic>? ?? {};
                if (vendorSpecialPrices.containsKey(itemCode)) {
                  final specialPrice = vendorSpecialPrices[itemCode];
                  if (specialPrice is num) {
                    price = specialPrice.toDouble();
                    foundSpecialPrice = true;
                  }
                }
              }
            }

            if (!foundSpecialPrice) {
              // Default behavior: use snapshot first, then fall back to config
              if (itemPricesSnapshot.containsKey(itemCode)) {
                price = (itemPricesSnapshot[itemCode] is num)
                    ? (itemPricesSnapshot[itemCode] as num).toDouble()
                    : 0.0;
              } else if (_userConfig != null && _userConfig!['items'] != null) {
                final List<dynamic> configItems =
                    _userConfig!['items'] as List<dynamic>;
                for (var item in configItems) {
                  if (item is Map<String, dynamic> &&
                      item['code'] == itemCode) {
                    price = (item['price'] is num)
                        ? item['price'].toDouble()
                        : 0.0;
                    break;
                  }
                }
              }
            }
          }
        }

        // Calculate line total and add to overall total
        final double lineTotal = qty * price;
        totalAmount += lineTotal.toInt();

        items[itemIndex.toString()] = {
          'name': itemName,
          'quantity': qty,
          'rate': price,
        };
        itemIndex++;
      }
    });

    // Debug: Print total calculation for verification
    print('Invoice total calculation:');
    print('Total amount: $totalAmount');
    print('Items count: ${items.length}');
    print('Items: $items');

    // Generate the invoice with total amount
    await InvoiceService.generateInvoice(
      idToken: idToken,
      vendorName: vendorName,
      date: _dateLabel,
      items: items,
      total: totalAmount,
      context: context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    const double _scrollBarReserve =
        88; // reserve space for bottom bar + spacing

    // Show loading state
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Report of $_dateLabel',
            style: GoogleFonts.quicksand(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Show no data state
    if (_dailyReport == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Report of $_dateLabel',
            style: GoogleFonts.quicksand(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No data available',
                  style: GoogleFonts.quicksand(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'No report found for this date. Please check if the data has been entered.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A5AE0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      final updated = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) =>
                              DailyReportEditScreen(date: widget.date),
                        ),
                      );
                      if (updated == true) {
                        // Force reload of this report after edit
                        _loadData();
                        // Return true to parent screen to trigger calendar refresh
                        Navigator.of(context).pop(true);
                        return;
                      }
                    },
                    child: Text(
                      'Report Data',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Process dynamic data
    final Map<String, dynamic> itemsSales =
        _dailyReport!['items_sales'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> vendorSales =
        _dailyReport!['vendor_sales'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> expenses =
        _dailyReport!['expenses'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> itemPricesSnapshot =
        _dailyReport!['item_prices_snapshot'] as Map<String, dynamic>? ?? {};

    // Define color palette for pie charts
    const List<Color> colorPalette = [
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

    // Create items list from dynamic data
    // First, build a set of current config item codes for deprecated check
    final Set<String> configItemCodes = {};
    if (_userConfig != null && _userConfig!['items'] != null) {
      final List<dynamic> configItems = _userConfig!['items'] as List<dynamic>;
      for (var item in configItems) {
        if (item is Map<String, dynamic>) {
          final String itemCode = item['code'] ?? '';
          if (itemCode.isNotEmpty) {
            configItemCodes.add(itemCode);
          }
        }
      }
    }

    final List<_ItemData> items = [];
    itemsSales.forEach((code, quantity) {
      final int qty = (quantity is num) ? quantity.toInt() : 0;

      // Only include items with quantity > 0
      if (qty > 0) {
        String displayName = _getItemDisplayName(code);

        // Check if item is deprecated (not in current config)
        final bool isDeprecated = !configItemCodes.contains(code);
        if (isDeprecated && !displayName.contains('(Deprecated)')) {
          displayName = '$displayName (Deprecated)';
        }

        double totalRevenueForItem = 0.0;
        bool hasSpecialPrice = false;
        final List<String> specialVendors = [];

        // Get vendor breakdown for this item (with price info)
        final List<String> vendorBreakdown = [];
        vendorSales.forEach((vendorName, vendorData) {
          if (vendorData is Map<String, dynamic> &&
              vendorData['items'] != null) {
            final Map<String, dynamic> vendorItems =
                vendorData['items'] as Map<String, dynamic>;
            if (vendorItems.containsKey(code)) {
              final int vendorQty = (vendorItems[code] is num)
                  ? vendorItems[code].toInt()
                  : 0;
              if (vendorQty > 0) {
                final priceResolution = _resolvePriceForVendor(
                  code,
                  vendorName: vendorName,
                );
                final double vendorPrice = priceResolution.price;
                totalRevenueForItem += vendorQty * vendorPrice;
                if (priceResolution.usedSpecialPrice) {
                  hasSpecialPrice = true;
                  specialVendors.add(vendorName);
                }
                vendorBreakdown.add(
                  '$vendorName - $vendorQty @ ${_rupee(vendorPrice)}'
                  '${priceResolution.usedSpecialPrice ? " (special)" : ""}',
                );
              }
            }
          }
        });

        // Get color for this item
        final int itemIndex = items.length;
        final Color itemColor = colorPalette[itemIndex % colorPalette.length];

        items.add(
          _ItemData(
            title: displayName,
            quantity: qty,
            averagePrice: qty > 0 ? (totalRevenueForItem / qty) : 0.0,
            totalRevenue: totalRevenueForItem,
            hasSpecialPrice: hasSpecialPrice,
            specialVendors: specialVendors,
            vendors: vendorBreakdown,
            color: itemColor,
          ),
        );
      }
    });

    // Sort items by quantity (highest first)
    items.sort((a, b) => b.quantity.compareTo(a.quantity));

    final int totalQty = items.fold(0, (acc, it) => acc + it.quantity);
    final Map<String, double> dataMap = {
      for (final it in items)
        it.title: totalQty == 0 ? 0 : (it.quantity / totalQty) * 100.0,
    };

    // Create color lists for charts - with safety check
    final List<Color> itemColors = dataMap.keys
        .toList()
        .asMap()
        .entries
        .map((entry) => colorPalette[entry.key % colorPalette.length])
        .toList();

    // Create vendor data map for pie chart (based on revenue, not quantity)
    final Map<String, double> vendorDataMap = {};
    double totalRevenueForPieChart = 0.0;

    // First, calculate total revenue from all vendors
    vendorSales.forEach((vendorName, vendorData) {
      if (vendorData is Map<String, dynamic> && vendorData['sale'] != null) {
        final int vendorQty = (vendorData['sale'] is num)
            ? vendorData['sale'].toInt()
            : 0;
        if (vendorQty > 0) {
          // Calculate revenue for this vendor
          double vendorRevenue = 0.0;
          final Map<String, dynamic> vendorItems =
              vendorData['items'] as Map<String, dynamic>? ?? {};

          vendorItems.forEach((itemCode, quantity) {
            final int qty = (quantity is num) ? quantity.toInt() : 0;
            if (qty > 0) {
              // Get price based on user's choice for mismatched items, otherwise use snapshot
              double price = 0.0;

              // FIRST: Check for regular price mismatches (snapshot vs config)
              if (_priceMismatches.containsKey(itemCode) &&
                  _useNewPrices.containsKey(itemCode)) {
                if (_useNewPrices[itemCode] == true) {
                  // Use current config price
                  price = _priceMismatches[itemCode]?.toDouble() ?? 0.0;
                } else {
                  // Use original snapshot price
                  price = (itemPricesSnapshot[itemCode] is num)
                      ? (itemPricesSnapshot[itemCode] as num).toDouble()
                      : 0.0;
                }
              } else {
                // No price mismatch - check for special prices
                // Check for special price mismatches for this vendor
                bool hasSpecialPriceMismatch = false;
                if (_specialPriceMismatches.containsKey(vendorName)) {
                  if (_specialPriceMismatches[vendorName]!.containsKey(
                        itemCode,
                      ) &&
                      _useNewSpecialPrices.containsKey(vendorName) &&
                      _useNewSpecialPrices[vendorName]!.containsKey(itemCode)) {
                    if (_useNewSpecialPrices[vendorName]![itemCode] == true) {
                      // Use current special price
                      price = _specialPriceMismatches[vendorName]![itemCode]!
                          .toDouble();
                      hasSpecialPriceMismatch = true;
                    } else {
                      // Use original special price from snapshot
                      final specialPricesSnapshot =
                          _dailyReport?['special_prices']
                              as Map<String, dynamic>? ??
                          {};
                      if (specialPricesSnapshot.containsKey(vendorName)) {
                        final vendorSpecialPrices =
                            specialPricesSnapshot[vendorName]
                                as Map<String, dynamic>? ??
                            {};
                        if (vendorSpecialPrices.containsKey(itemCode)) {
                          price = (vendorSpecialPrices[itemCode] is num)
                              ? (vendorSpecialPrices[itemCode] as num)
                                    .toDouble()
                              : 0.0;
                          hasSpecialPriceMismatch = true;
                        }
                      }
                    }
                  }
                }

                if (!hasSpecialPriceMismatch) {
                  // Check for special prices for this vendor
                  bool foundSpecialPrice = false;
                  if (_userConfig != null &&
                      _userConfig!['special_prices'] != null) {
                    final specialPrices =
                        _userConfig!['special_prices'] as Map<String, dynamic>;
                    if (specialPrices.containsKey(vendorName)) {
                      final vendorSpecialPrices =
                          specialPrices[vendorName] as Map<String, dynamic>? ??
                          {};
                      if (vendorSpecialPrices.containsKey(itemCode)) {
                        final specialPrice = vendorSpecialPrices[itemCode];
                        if (specialPrice is num) {
                          price = specialPrice.toDouble();
                          foundSpecialPrice = true;
                        }
                      }
                    }
                  }

                  if (!foundSpecialPrice) {
                    // Default behavior: use snapshot first, then fall back to config
                    if (itemPricesSnapshot.containsKey(itemCode)) {
                      price = (itemPricesSnapshot[itemCode] is num)
                          ? (itemPricesSnapshot[itemCode] as num).toDouble()
                          : 0;
                    } else if (_userConfig != null &&
                        _userConfig!['items'] != null) {
                      final List<dynamic> configItems =
                          _userConfig!['items'] as List<dynamic>;
                      for (var item in configItems) {
                        if (item is Map<String, dynamic> &&
                            item['code'] == itemCode) {
                          price = (item['price'] is num)
                              ? item['price'].toDouble()
                              : 0.0;
                          break;
                        }
                      }
                    }
                  }
                }
              }
              final double itemRevenue = qty * price;
              vendorRevenue += itemRevenue;
            }
          });

          totalRevenueForPieChart += vendorRevenue;
        }
      }
    });

    // Now calculate percentages based on revenue
    vendorSales.forEach((vendorName, vendorData) {
      if (vendorData is Map<String, dynamic> && vendorData['sale'] != null) {
        final int vendorQty = (vendorData['sale'] is num)
            ? vendorData['sale'].toInt()
            : 0;
        if (vendorQty > 0) {
          // Calculate revenue for this vendor (same logic as above)
          double vendorRevenue = 0.0;
          final Map<String, dynamic> vendorItems =
              vendorData['items'] as Map<String, dynamic>? ?? {};

          vendorItems.forEach((itemCode, quantity) {
            final int qty = (quantity is num) ? quantity.toInt() : 0;
            if (qty > 0) {
              // Get price based on user's choice for mismatched items, otherwise use snapshot
              double price = 0.0;

              // FIRST: Check for regular price mismatches (snapshot vs config)
              if (_priceMismatches.containsKey(itemCode) &&
                  _useNewPrices.containsKey(itemCode)) {
                if (_useNewPrices[itemCode] == true) {
                  // Use current config price
                  price = _priceMismatches[itemCode]?.toDouble() ?? 0.0;
                } else {
                  // Use original snapshot price
                  price = (itemPricesSnapshot[itemCode] is num)
                      ? (itemPricesSnapshot[itemCode] as num).toDouble()
                      : 0.0;
                }
              } else {
                // No price mismatch - check for special prices
                // Check for special price mismatches for this vendor
                bool hasSpecialPriceMismatch = false;
                if (_specialPriceMismatches.containsKey(vendorName)) {
                  if (_specialPriceMismatches[vendorName]!.containsKey(
                        itemCode,
                      ) &&
                      _useNewSpecialPrices.containsKey(vendorName) &&
                      _useNewSpecialPrices[vendorName]!.containsKey(itemCode)) {
                    if (_useNewSpecialPrices[vendorName]![itemCode] == true) {
                      // Use current special price
                      price = _specialPriceMismatches[vendorName]![itemCode]!
                          .toDouble();
                      hasSpecialPriceMismatch = true;
                    } else {
                      // Use original special price from snapshot
                      final specialPricesSnapshot =
                          _dailyReport?['special_prices']
                              as Map<String, dynamic>? ??
                          {};
                      if (specialPricesSnapshot.containsKey(vendorName)) {
                        final vendorSpecialPrices =
                            specialPricesSnapshot[vendorName]
                                as Map<String, dynamic>? ??
                            {};
                        if (vendorSpecialPrices.containsKey(itemCode)) {
                          price = (vendorSpecialPrices[itemCode] is num)
                              ? (vendorSpecialPrices[itemCode] as num)
                                    .toDouble()
                              : 0.0;
                          hasSpecialPriceMismatch = true;
                        }
                      }
                    }
                  }
                }

                if (!hasSpecialPriceMismatch) {
                  // Check for special prices for this vendor
                  bool foundSpecialPrice = false;
                  if (_userConfig != null &&
                      _userConfig!['special_prices'] != null) {
                    final specialPrices =
                        _userConfig!['special_prices'] as Map<String, dynamic>;
                    if (specialPrices.containsKey(vendorName)) {
                      final vendorSpecialPrices =
                          specialPrices[vendorName] as Map<String, dynamic>? ??
                          {};
                      if (vendorSpecialPrices.containsKey(itemCode)) {
                        final specialPrice = vendorSpecialPrices[itemCode];
                        if (specialPrice is num) {
                          price = specialPrice.toDouble();
                          foundSpecialPrice = true;
                        }
                      }
                    }
                  }

                  if (!foundSpecialPrice) {
                    // Default behavior: use snapshot first, then fall back to config
                    if (itemPricesSnapshot.containsKey(itemCode)) {
                      price = (itemPricesSnapshot[itemCode] is num)
                          ? (itemPricesSnapshot[itemCode] as num).toDouble()
                          : 0;
                    } else if (_userConfig != null &&
                        _userConfig!['items'] != null) {
                      final List<dynamic> configItems =
                          _userConfig!['items'] as List<dynamic>;
                      for (var item in configItems) {
                        if (item is Map<String, dynamic> &&
                            item['code'] == itemCode) {
                          price = (item['price'] is num)
                              ? item['price'].toDouble()
                              : 0.0;
                          break;
                        }
                      }
                    }
                  }
                }
              }
              final double itemRevenue = qty * price;
              vendorRevenue += itemRevenue;
            }
          });

          // Calculate percentage based on revenue
          vendorDataMap[vendorName] = totalRevenueForPieChart == 0
              ? 0
              : (vendorRevenue / totalRevenueForPieChart) * 100.0;
        }
      }
    });

    // Sort vendor data by revenue percentage
    final sortedVendorEntries = vendorDataMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final Map<String, double> sortedVendorDataMap = Map.fromEntries(
      sortedVendorEntries,
    );

    final List<Color> vendorColors = sortedVendorDataMap.keys
        .toList()
        .asMap()
        .entries
        .map((entry) => colorPalette[entry.key % colorPalette.length])
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            size.width * 0.06,
            0,
            size.width * 0.06,
            MediaQuery.of(context).padding.bottom + _scrollBarReserve,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: size.height * 0.025),
              // Report added by information
              if (_reportAddedBy != null && _reportAddedAt != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFE0E0E0),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        color: const Color(0xFF6A5AE0),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Report added by $_reportAddedBy',
                              style: GoogleFonts.quicksand(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'on $_reportAddedAt',
                              style: GoogleFonts.quicksand(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // Quantity Produced heading above chart
              Text(
                'Quantity Produced:-',
                style: GoogleFonts.quicksand(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              // Pie chart (same style as Home) - only show if there are items
              if (!_hidePieCharts && dataMap.isNotEmpty)
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      SizedBox(
                        width: size.width * 0.7,
                        height: size.width * 0.7,
                        child: PieChart(
                          dataMap: dataMap,
                          animationDuration: const Duration(milliseconds: 800),
                          chartType: ChartType.disc,
                          baseChartColor: const Color(0xFFD9D9D9),
                          colorList: itemColors,
                          chartValuesOptions: const ChartValuesOptions(
                            showChartValues: true,
                            showChartValuesInPercentage: true,
                            showChartValuesOutside: true,
                            chartValueStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          legendOptions: const LegendOptions(
                            showLegends: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              // Quantity Produced & Vendors
              ...items
                  .map(
                    (item) => Column(
                      children: [
                        _ExpandableItemCard(item: item),
                        const SizedBox(height: 16),
                      ],
                    ),
                  )
                  .toList(),
              const SizedBox(height: 24),
              // Vendors section
              Text(
                'Vendors:-',
                style: GoogleFonts.quicksand(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              if (!_hidePieCharts && sortedVendorDataMap.isNotEmpty)
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      SizedBox(
                        width: size.width * 0.7,
                        height: size.width * 0.7,
                        child: PieChart(
                          dataMap: sortedVendorDataMap,
                          animationDuration: const Duration(milliseconds: 800),
                          chartType: ChartType.disc,
                          baseChartColor: const Color(0xFFD9D9D9),
                          colorList: vendorColors,
                          chartValuesOptions: const ChartValuesOptions(
                            showChartValues: true,
                            showChartValuesInPercentage: true,
                            showChartValuesOutside: true,
                            chartValueStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          legendOptions: const LegendOptions(
                            showLegends: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              ...sortedVendorDataMap.entries.toList().asMap().entries.map((
                entry,
              ) {
                final int vendorIndex = entry.key;
                final MapEntry<String, double> vendorEntry = entry.value;
                final String vendorName = vendorEntry.key;
                final Map<String, dynamic> vendorData =
                    vendorSales[vendorName] as Map<String, dynamic>;
                final int totalQuantity = (vendorData['sale'] is num)
                    ? vendorData['sale'].toInt()
                    : 0;
                // Calculate total revenue based on current price selections
                double totalRevenue = 0.0;
                final Map<String, dynamic> vendorItems =
                    vendorData['items'] as Map<String, dynamic>? ?? {};

                final List<String> lines = [];
                vendorItems.forEach((itemCode, quantity) {
                  final int qty = (quantity is num) ? quantity.toInt() : 0;
                  if (qty > 0) {
                    final String displayName = _getItemDisplayName(itemCode);
                    // Get price based on user's choice for mismatched items, otherwise use snapshot
                    double price = 0.0;

                    // FIRST: Check for regular price mismatches (snapshot vs config)
                    if (_priceMismatches.containsKey(itemCode) &&
                        _useNewPrices.containsKey(itemCode)) {
                      if (_useNewPrices[itemCode] == true) {
                        // Use current config price
                        price = _priceMismatches[itemCode]?.toDouble() ?? 0.0;
                      } else {
                        // Use original snapshot price
                        price = (itemPricesSnapshot[itemCode] is num)
                            ? (itemPricesSnapshot[itemCode] as num).toDouble()
                            : 0.0;
                      }
                    } else {
                      // No price mismatch - check for special prices
                      // Check for special price mismatches for this vendor
                      bool hasSpecialPriceMismatch = false;
                      if (_specialPriceMismatches.containsKey(vendorName)) {
                        if (_specialPriceMismatches[vendorName]!.containsKey(
                              itemCode,
                            ) &&
                            _useNewSpecialPrices.containsKey(vendorName) &&
                            _useNewSpecialPrices[vendorName]!.containsKey(
                              itemCode,
                            )) {
                          if (_useNewSpecialPrices[vendorName]![itemCode] ==
                              true) {
                            // Use current special price
                            price =
                                _specialPriceMismatches[vendorName]![itemCode]!
                                    .toDouble();
                            hasSpecialPriceMismatch = true;
                          } else {
                            // Use original special price from snapshot
                            final specialPricesSnapshot =
                                _dailyReport?['special_prices']
                                    as Map<String, dynamic>? ??
                                {};
                            if (specialPricesSnapshot.containsKey(vendorName)) {
                              final vendorSpecialPrices =
                                  specialPricesSnapshot[vendorName]
                                      as Map<String, dynamic>? ??
                                  {};
                              if (vendorSpecialPrices.containsKey(itemCode)) {
                                price = (vendorSpecialPrices[itemCode] is num)
                                    ? (vendorSpecialPrices[itemCode] as num)
                                          .toDouble()
                                    : 0.0;
                                hasSpecialPriceMismatch = true;
                              }
                            }
                          }
                        }
                      }

                      if (!hasSpecialPriceMismatch) {
                        // Check for special prices for this vendor
                        bool foundSpecialPrice = false;
                        if (_userConfig != null &&
                            _userConfig!['special_prices'] != null) {
                          final specialPrices =
                              _userConfig!['special_prices']
                                  as Map<String, dynamic>;
                          if (specialPrices.containsKey(vendorName)) {
                            final vendorSpecialPrices =
                                specialPrices[vendorName]
                                    as Map<String, dynamic>? ??
                                {};
                            if (vendorSpecialPrices.containsKey(itemCode)) {
                              final specialPrice =
                                  vendorSpecialPrices[itemCode];
                              if (specialPrice is num) {
                                price = specialPrice.toDouble();
                                foundSpecialPrice = true;
                              }
                            }
                          }
                        }

                        if (!foundSpecialPrice) {
                          // Default behavior: use snapshot first, then fall back to config
                          if (itemPricesSnapshot.containsKey(itemCode)) {
                            price = (itemPricesSnapshot[itemCode] is num)
                                ? (itemPricesSnapshot[itemCode] as num)
                                      .toDouble()
                                : 0;
                          } else if (_userConfig != null &&
                              _userConfig!['items'] != null) {
                            final List<dynamic> configItems =
                                _userConfig!['items'] as List<dynamic>;
                            for (var item in configItems) {
                              if (item is Map<String, dynamic> &&
                                  item['code'] == itemCode) {
                                price = (item['price'] is num)
                                    ? item['price'].toDouble()
                                    : 0;
                                break;
                              }
                            }
                          }
                        }
                      }
                    }
                    final double itemRevenue = qty * price;
                    totalRevenue += itemRevenue; // Add to total vendor revenue
                    lines.add(
                      '$displayName - $qty X ${price.toStringAsFixed(2)} = ${_rupee(itemRevenue)}',
                    );
                  }
                });

                // Check if vendor is deprecated (not in current config)
                bool isDeprecated = true;
                if (_userConfig != null && _userConfig!['vendors'] != null) {
                  final List<dynamic> configVendors =
                      _userConfig!['vendors'] as List<dynamic>;
                  for (var vendor in configVendors) {
                    if (vendor is String && vendor == vendorName) {
                      isDeprecated = false;
                      break;
                    }
                  }
                }

                // Get color for this vendor (same order as pie chart)
                final Color vendorColor = vendorColors[vendorIndex];

                return Column(
                  children: [
                    _VendorCard(
                      name: vendorName,
                      amountText: _rupee(totalRevenue),
                      lines: lines,
                      totalQuantityText: 'Total Quantity:- $totalQuantity',
                      onGenerateReceipt: () => _generateInvoiceForVendor(
                        vendorName,
                        vendorItems,
                        itemPricesSnapshot,
                      ),
                      color: vendorColor,
                      isDeprecated: isDeprecated,
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              }).toList(),
              const SizedBox(height: 24),
              // Expenses section
              Text(
                'Expenses:-',
                style: GoogleFonts.quicksand(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              ...expenses.entries
                  .map(
                    (entry) => _ExpenseRow(
                      label: '${entry.key} - ',
                      value: '₹${entry.value}',
                    ),
                  )
                  .toList(),
              const Divider(thickness: 2),
              const SizedBox(height: 8),
              _ExpenseRow(
                label: 'Total Expenses',
                value: _rupee(
                  (_dailyReport!['total_expenses'] is num)
                      ? (_dailyReport!['total_expenses'] as num)
                      : 0,
                ),
              ),
              const SizedBox(height: 24),
              // Totals section
              Text(
                'Totals:-',
                style: GoogleFonts.quicksand(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final recalculatedTotals = _calculateRecalculatedTotals();
                  return Column(
                    children: [
                      _SummaryRow(
                        label: 'Total Sales',
                        value: '${recalculatedTotals['total_sales'] ?? 0}',
                      ),
                      const SizedBox(height: 12),
                      _SummaryRow(
                        label: 'Total Revenue',
                        value: _rupee(recalculatedTotals['total_revenue'] ?? 0),
                      ),
                      const SizedBox(height: 12),
                      _SummaryRow(
                        label: 'Total Expenses',
                        value: _rupee(
                          recalculatedTotals['total_expenses'] ?? 0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SummaryRow(
                        label: 'Addition Revenue',
                        value: _rupee(
                          recalculatedTotals['addition_revenue'] ?? 0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SummaryRow(
                        label: 'NET Profit',
                        value: _rupee(recalculatedTotals['net_profit'] ?? 0),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              // Edit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A5AE0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final updated = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) =>
                            DailyReportEditScreen(date: widget.date),
                      ),
                    );
                    if (updated == true) {
                      // Force reload of this report after edit
                      _loadData();
                      // Return true to parent screen to trigger calendar refresh
                      Navigator.of(context).pop(true);
                      return;
                    }
                  },
                  child: Text(
                    'Edit',
                    style: GoogleFonts.quicksand(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Report of $_dateLabel',
          style: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onSelected: (String value) {
              if (value == 'hide_pie_charts') {
                setState(() {
                  _hidePieCharts = !_hidePieCharts;
                });
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'hide_pie_charts',
                child: Row(
                  children: [
                    Icon(
                      _hidePieCharts ? Icons.visibility : Icons.visibility_off,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _hidePieCharts ? 'Show Pie Charts' : 'Hide Pie Charts',
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
    );
  }
}

// _ItemCard removed; replaced with _ExpandableItemCard

class _ItemData {
  final String title;
  final int quantity;
  final double averagePrice;
  final double totalRevenue;
  final bool hasSpecialPrice;
  final List<String> specialVendors;
  final List<String> vendors;
  final Color color;

  const _ItemData({
    required this.title,
    required this.quantity,
    required this.averagePrice,
    required this.totalRevenue,
    required this.hasSpecialPrice,
    required this.specialVendors,
    required this.vendors,
    required this.color,
  });
}

class _ExpandableItemCard extends StatefulWidget {
  final _ItemData item;
  const _ExpandableItemCard({required this.item});

  @override
  State<_ExpandableItemCard> createState() => _ExpandableItemCardState();
}

class _ExpandableItemCardState extends State<_ExpandableItemCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final _ItemData item = widget.item;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE9E9E9),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.black, width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Color indicator
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: item.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    style: GoogleFonts.quicksand(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      height: 1.25,
                    ),
                  ),
                ),
                Text(
                  '${item.quantity}',
                  style: GoogleFonts.quicksand(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    height: 1.25,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.black,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              const Divider(thickness: 2),
              const SizedBox(height: 8),
              // Vendors list
              if (item.hasSpecialPrice) ...[
                Text(
                  'Special price applied for: ${item.specialVendors.join(", ")}',
                  style: GoogleFonts.quicksand(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.green[700],
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              for (final v in item.vendors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          v,
                          style: GoogleFonts.quicksand(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                            height: 1.25,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              // Revenue details inside the item box
              Text(
                'Item Revenue:- ${_rupee(item.totalRevenue)}',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  height: 1.25,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _rupee(num value) => '₹${value.toStringAsFixed(2)}';

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black,
              height: 1.25,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.quicksand(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final String label;
  final String value;
  const _ExpenseRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black,
              height: 1.25,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.quicksand(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _VendorCard extends StatefulWidget {
  final String name;
  final String amountText;
  final List<String> lines;
  final String totalQuantityText;
  final VoidCallback onGenerateReceipt;
  final Color color;
  final bool isDeprecated;

  const _VendorCard({
    required this.name,
    required this.amountText,
    required this.lines,
    required this.totalQuantityText,
    required this.onGenerateReceipt,
    required this.color,
    this.isDeprecated = false,
  });

  @override
  State<_VendorCard> createState() => _VendorCardState();
}

class _VendorCardState extends State<_VendorCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE9E9E9),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.black, width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Color indicator
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        widget.name,
                        style: GoogleFonts.quicksand(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                          height: 1.25,
                        ),
                      ),
                      if (widget.isDeprecated) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Not in config',
                            style: GoogleFonts.quicksand(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  '—',
                  style: GoogleFonts.quicksand(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF333333),
                    height: 1.25,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  widget.amountText,
                  style: GoogleFonts.quicksand(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    height: 1.25,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.black,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              const Divider(thickness: 2),
              const SizedBox(height: 8),
              for (final line in widget.lines)
                Text(
                  line,
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    height: 1.25,
                  ),
                ),
              const SizedBox(height: 8),
              const Divider(thickness: 2),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.totalQuantityText,
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                        height: 1.25,
                      ),
                    ),
                  ),
                  Text(
                    widget.amountText,
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD9D9D9),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: widget.onGenerateReceipt,
                  icon: const Icon(Icons.receipt_long, size: 20),
                  label: Text(
                    'Generate Invoice',
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PriceResolution {
  final double price;
  final bool usedSpecialPrice;

  const _PriceResolution({required this.price, required this.usedSpecialPrice});
}
