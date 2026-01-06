import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pie_chart/pie_chart.dart';
import '../firestore_service.dart';
import 'root_shell.dart';
import '../auth_service.dart';

class DailyReportEditScreen extends StatefulWidget {
  final DateTime date;

  const DailyReportEditScreen({super.key, required this.date});

  @override
  State<DailyReportEditScreen> createState() => _DailyReportEditScreenState();
}

class _DailyReportEditScreenState extends State<DailyReportEditScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _dailyReport;
  Map<String, dynamic>? _userConfig;
  bool _hidePieCharts = false;

  // Editable data
  late List<_EditableItemData> items;
  late Map<String, int> expenses;
  late Map<String, Map<String, int>> vendorItems; // vendor -> item -> quantity
  late Set<String> deprecatedVendors; // vendors not in config
  Map<String, double> _priceMismatches = {}; // itemCode -> currentConfigPrice
  Map<String, bool> _useNewPrices = {}; // itemCode -> useNewPrice
  Map<String, Map<String, double>> _specialPriceMismatches =
      {}; // vendor -> {itemCode -> currentSpecialPrice}
  Map<String, Map<String, bool>> _useNewSpecialPrices =
      {}; // vendor -> {itemCode -> useNewSpecialPrice}
  // Fixed prices chosen for each item code (base, before vendor special overlay)
  final Map<String, double> _fixedItemPrices = {};
  // Editable totals
  int? _editTotalSales; // quantity
  double? _editTotalRevenue; // money
  double? _editTotalExpenses; // money
  double? _editNetProfit; // money
  double? _editAdditionRevenue; // money

  final ImagePicker _imagePicker = ImagePicker();

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

      if (mounted) {
        setState(() {
          _userConfig = config;
          _dailyReport = report;
          _initializeEditableData();
          _isLoading = false;
        });

        // Check for price mismatches after initialization
        if (report != null && config != null) {
          _checkForPriceMismatches(report, config);
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

  Future<void> _refreshData() async {
    try {
      // Reload user config and daily report data
      final config = await FirestoreService.getUserConfig();
      final report = await FirestoreService.getDailyReport(widget.date);

      if (mounted) {
        setState(() {
          _userConfig = config;
          _dailyReport = report;
          _initializeEditableData();
        });
      }
    } catch (e) {
      print('Error refreshing data: $e');
    }
  }

  void _initializeEditableData() {
    if (_userConfig == null) return;

    // Get report data (may be null or empty)
    final Map<String, dynamic> itemsSales =
        _dailyReport?['items_sales'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> vendorSales =
        _dailyReport?['vendor_sales'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> expensesData =
        _dailyReport?['expenses'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> itemPricesSnapshot =
        _dailyReport?['item_prices_snapshot'] as Map<String, dynamic>? ?? {};

    items = [];
    vendorItems = {};
    deprecatedVendors = {};

    // Track which items are in config
    final Set<String> configItemCodes = {};

    // STEP 1: Generate ALL items from config
    if (_userConfig!['items'] != null) {
      final List<dynamic> configItems = _userConfig!['items'] as List<dynamic>;

      for (var configItem in configItems) {
        if (configItem is Map<String, dynamic>) {
          final String code = configItem['code'] ?? '';
          final String name = configItem['name'] ?? '';
          final double price = (configItem['price'] is num)
              ? (configItem['price'] as num).toDouble()
              : 0.0;

          if (code.isEmpty) continue;

          configItemCodes.add(code);

          // Get quantity from report data, or 0 if not present
          final int qty = (itemsSales[code] is num)
              ? (itemsSales[code] as num).toInt()
              : 0;

          final String displayName = name.isNotEmpty ? '$name ($code)' : code;

          // Use snapshot price if available, otherwise use config price
          double itemPrice = price; // Default to config price
          if (itemPricesSnapshot.containsKey(code)) {
            itemPrice = (itemPricesSnapshot[code] is num)
                ? (itemPricesSnapshot[code] as num).toDouble()
                : price;
          }

          items.add(
            _EditableItemData(
              code: code,
              title: displayName,
              quantity: qty,
              pricePerItem: itemPrice,
              vendors: [], // Will be updated below
              isPriceEditable: false,
              isDeprecated: false,
            ),
          );
        }
      }
    }

    // STEP 1.5: Check for items in report that aren't in config (deprecated items)
    final Set<String> deprecatedItems = {};
    itemsSales.forEach((code, quantity) {
      if (!configItemCodes.contains(code)) {
        deprecatedItems.add(code);

        // Get price from snapshot, default to 0 if not found
        final double price = (itemPricesSnapshot[code] is num)
            ? (itemPricesSnapshot[code] as num).toDouble()
            : 0.0;

        final int qty = (quantity is num) ? quantity.toInt() : 0;

        items.add(
          _EditableItemData(
            code: code,
            title: '$code (Deprecated)',
            quantity: qty,
            pricePerItem: price,
            vendors: [], // Will be updated below
            isPriceEditable: true,
            isDeprecated: true,
          ),
        );
      }
    });

    // Show message if there are deprecated items
    if (deprecatedItems.isNotEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Warning: This report contains ${deprecatedItems.length} item(s) not in current config: ${deprecatedItems.join(", ")}. You can edit their prices.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      });
    }

    // STEP 2: Generate ALL vendors from config with ALL items
    final Set<String> configVendorNames = {};
    if (_userConfig!['vendors'] != null) {
      final List<dynamic> configVendors =
          _userConfig!['vendors'] as List<dynamic>;

      for (var vendorName in configVendors) {
        if (vendorName is String && vendorName.isNotEmpty) {
          configVendorNames.add(vendorName);
          vendorItems[vendorName] = {};

          // Initialize all items for this vendor with quantity 0
          // Use config items directly to ensure all items are included
          if (_userConfig!['items'] != null) {
            final List<dynamic> configItems =
                _userConfig!['items'] as List<dynamic>;
            for (var configItem in configItems) {
              if (configItem is Map<String, dynamic>) {
                final String code = configItem['code'] ?? '';
                if (code.isNotEmpty) {
                  vendorItems[vendorName]![code] = 0;
                }
              }
            }
          }

          // Fill in actual quantities from report data
          if (vendorSales.containsKey(vendorName)) {
            final vendorData = vendorSales[vendorName];
            if (vendorData is Map<String, dynamic> &&
                vendorData['items'] != null) {
              final Map<String, dynamic> vendorItemsData =
                  vendorData['items'] as Map<String, dynamic>;

              vendorItemsData.forEach((itemCode, quantity) {
                final int qty = (quantity is num) ? quantity.toInt() : 0;
                if (vendorItems[vendorName]!.containsKey(itemCode)) {
                  vendorItems[vendorName]![itemCode] = qty;
                }
              });
            }
          }
        }
      }
    }

    // STEP 2.5: Check for vendors in report that aren't in config (deprecated vendors)
    final Set<String> foundDeprecatedVendors = {};
    vendorSales.forEach((vendorName, vendorData) {
      if (!configVendorNames.contains(vendorName)) {
        foundDeprecatedVendors.add(vendorName);
        deprecatedVendors.add(vendorName);
        vendorItems[vendorName] = {};

        // Initialize all items for this deprecated vendor with quantity 0
        // Use config items directly to ensure all items are included
        if (_userConfig!['items'] != null) {
          final List<dynamic> configItems =
              _userConfig!['items'] as List<dynamic>;
          for (var configItem in configItems) {
            if (configItem is Map<String, dynamic>) {
              final String code = configItem['code'] ?? '';
              if (code.isNotEmpty) {
                vendorItems[vendorName]![code] = 0;
              }
            }
          }
        }

        // Fill in actual quantities from report data
        if (vendorData is Map<String, dynamic> && vendorData['items'] != null) {
          final Map<String, dynamic> vendorItemsData =
              vendorData['items'] as Map<String, dynamic>;

          vendorItemsData.forEach((itemCode, quantity) {
            final int qty = (quantity is num) ? quantity.toInt() : 0;
            if (vendorItems[vendorName]!.containsKey(itemCode)) {
              vendorItems[vendorName]![itemCode] = qty;
            }
          });
        }
      }
    });

    // Show message if there are deprecated vendors
    if (foundDeprecatedVendors.isNotEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Warning: This report contains ${foundDeprecatedVendors.length} vendor(s) not in current config: ${foundDeprecatedVendors.join(", ")}.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      });
    }

    // STEP 3: Update vendor breakdown in items
    for (int i = 0; i < items.length; i++) {
      final List<String> vendorBreakdown = [];
      vendorItems.forEach((vendorName, vendorItemsData) {
        final int vendorQty = vendorItemsData[items[i].code] ?? 0;
        if (vendorQty > 0) {
          vendorBreakdown.add('$vendorName - $vendorQty');
        }
      });

      items[i] = items[i].copyWith(vendors: vendorBreakdown);
    }

    // Sort items by quantity (highest first)
    items.sort((a, b) => b.quantity.compareTo(a.quantity));

    // STEP 4: Generate ALL expenses from config
    expenses = {};
    if (_userConfig!['expenses'] != null) {
      final List<dynamic> configExpenses =
          _userConfig!['expenses'] as List<dynamic>;

      for (var expenseName in configExpenses) {
        if (expenseName is String && expenseName.isNotEmpty) {
          // Get value from report data, or 0 if not present
          final int value = (expensesData[expenseName] is num)
              ? (expensesData[expenseName] as num).toInt()
              : 0;
          expenses[expenseName] = value;
        }
      }
    }

    // Initialize fixed base prices per item
    _initializeFixedItemPrices(itemPricesSnapshot);

    // Initialize editable totals from vendor data + prices
    int calcSales = 0;
    double calcRevenue = 0.0;
    vendorItems.forEach((vendorName, vendorItemsData) {
      vendorItemsData.forEach((itemCode, quantity) {
        calcSales += quantity;
        final double itemPrice = _getCorrectPriceForVendorAndItem(
          vendorName,
          itemCode,
        );
        calcRevenue += quantity * itemPrice;
      });
    });
    final double calcExpenses = expenses.values
        .fold(0.0, (num acc, v) => acc + (v is num ? v.toDouble() : 0.0))
        .toDouble();
    final double additionRevenue =
        (_dailyReport?['addition_revenue'] as num?)?.toDouble() ?? 0.0;
    final double totalRevenueWithAddition = calcRevenue + additionRevenue;
    final double calcNetProfit = totalRevenueWithAddition - calcExpenses;

    _editTotalSales = calcSales;
    _editTotalRevenue = totalRevenueWithAddition;
    _editTotalExpenses = calcExpenses;
    _editNetProfit = calcNetProfit;
    _editAdditionRevenue = additionRevenue;
  }

  // Initialize fixed item prices using config and snapshot, deferring mismatches to dialog
  void _initializeFixedItemPrices(Map<String, dynamic> itemPricesSnapshot) {
    // Build a quick lookup of config prices
    final Map<String, double> configPrices = {};
    if (_userConfig != null && _userConfig!['items'] != null) {
      for (final it in (_userConfig!['items'] as List<dynamic>)) {
        if (it is Map<String, dynamic>) {
          final String code = it['code'] ?? '';
          final double price = (it['price'] is num)
              ? (it['price'] as num).toDouble()
              : 0.0;
          if (code.isNotEmpty) configPrices[code] = price;
        }
      }
    }

    for (final item in items) {
      final String code = item.code;
      final double configPrice = configPrices[code] ?? 0.0;
      if (_dailyReport == null) {
        // New report -> use config price
        _fixedItemPrices[code] = configPrice;
      } else {
        // Existing report: use snapshot if matches config; mismatches handled by dialog later
        if (itemPricesSnapshot.containsKey(code)) {
          final double snapshotPrice = (itemPricesSnapshot[code] is num)
              ? (itemPricesSnapshot[code] as num).toDouble()
              : 0.0;
          _fixedItemPrices[code] = snapshotPrice;
        } else {
          _fixedItemPrices[code] = configPrice;
        }
      }
    }

    // Ensure item models reflect the chosen fixed prices initially
    for (int i = 0; i < items.length; i++) {
      final String code = items[i].code;
      if (_fixedItemPrices.containsKey(code)) {
        items[i] = items[i].copyWith(
          pricePerItem: _fixedItemPrices[code] ?? items[i].pricePerItem,
        );
      }
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
    final Map<String, double> configPrices = {};
    if (config['items'] != null) {
      final List<dynamic> configItems = config['items'] as List<dynamic>;
      for (var item in configItems) {
        if (item is Map<String, dynamic>) {
          final String code = item['code'] ?? '';
          final double price = (item['price'] is num)
              ? (item['price'] as num).toDouble()
              : 0.0;
          if (code.isNotEmpty) {
            configPrices[code] = price;
          }
        }
      }
    }

    // Find price mismatches
    final Map<String, double> mismatches = {};
    itemsSales.forEach((itemCode, quantity) {
      final int qty = (quantity is num) ? quantity.toInt() : 0;
      if (qty > 0 &&
          itemPricesSnapshot.containsKey(itemCode) &&
          configPrices.containsKey(itemCode)) {
        final double snapshotPrice = (itemPricesSnapshot[itemCode] is num)
            ? (itemPricesSnapshot[itemCode] as num).toDouble()
            : 0.0;
        final double configPrice = configPrices[itemCode] ?? 0.0;

        if (snapshotPrice != configPrice) {
          mismatches[itemCode] = configPrice;
        }
      }
    });

    if (mismatches.isNotEmpty) {
      _priceMismatches = mismatches;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showPriceMismatchDialog(mismatches, itemPricesSnapshot);
        }
      });
    }

    // Check for special price mismatches
    _checkForSpecialPriceMismatches(report, config);
  }

  void _showPriceMismatchDialog(
    Map<String, double> mismatches,
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
                      'Some item prices have changed since this report was created. Choose which prices to use for editing:',
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...mismatches.entries.map((entry) {
                      final String itemCode = entry.key;
                      final double newPrice = entry.value;
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
                                        // Immediately apply the price change
                                        _updateItemPriceInDialog(
                                          itemCode,
                                          value,
                                          mismatches,
                                          itemPricesSnapshot,
                                        );
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
                    _recalculateTotals();
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

  void _updateItemPriceInDialog(
    String itemCode,
    bool useNewPrice,
    Map<String, double> mismatches,
    Map<String, dynamic> itemPricesSnapshot,
  ) {
    // Find the item and update its price immediately
    for (int i = 0; i < items.length; i++) {
      if (items[i].code == itemCode) {
        double newPrice;
        if (useNewPrice) {
          // Use current config price
          newPrice = mismatches[itemCode] ?? items[i].pricePerItem;
        } else {
          // Use original snapshot price
          newPrice = (itemPricesSnapshot[itemCode] is num)
              ? (itemPricesSnapshot[itemCode] as num).toDouble()
              : items[i].pricePerItem;
        }

        items[i] = items[i].copyWith(pricePerItem: newPrice);
        _fixedItemPrices[itemCode] = newPrice; // lock fixed base price
        break;
      }
    }

    // Recalculate totals after price change
    _recalculateTotalsFromVendorAndExpenses();
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
                      'Some special prices have changed or been removed since this report was created. Choose which prices to use for editing:',
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
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Continue',
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

  Future<bool?> _showSavePriceConfirmationDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Save Price Confirmation',
            style: GoogleFonts.quicksand(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          content: Text(
            'You have items with price mismatches. Which prices should be saved to the report?\n\n'
            '• Original Prices: Keep the prices from when the report was created\n'
            '• Current Prices: Update to the current configuration prices',
            style: GoogleFonts.quicksand(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null), // Cancel
              child: Text(
                'Cancel',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper method to get the correct price for an item (config vs snapshot)
  double _getItemPrice(String itemCode) {
    // Always prefer fixed chosen price if available
    if (_fixedItemPrices.containsKey(itemCode)) {
      return _fixedItemPrices[itemCode] ?? 0.0;
    }
    // Fallbacks for legacy paths
    if (_dailyReport == null) {
      return _getPriceForItemCode(itemCode);
    }
    final Map<String, dynamic> itemPricesSnapshot =
        _dailyReport!['item_prices_snapshot'] as Map<String, dynamic>? ?? {};
    if (itemPricesSnapshot.containsKey(itemCode)) {
      return (itemPricesSnapshot[itemCode] is num)
          ? (itemPricesSnapshot[itemCode] as num).toDouble()
          : 0.0;
    }
    return _getPriceForItemCode(itemCode);
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

  double _getPriceForItemCode(String code) {
    if (_userConfig == null || _userConfig!['items'] == null) return 0.0;
    final List<dynamic> cfgItems = _userConfig!['items'] as List<dynamic>;
    for (var item in cfgItems) {
      if (item is Map<String, dynamic> && item['code'] == code) {
        return (item['price'] is num) ? (item['price'] as num).toDouble() : 0.0;
      }
    }
    return 0.0;
  }

  void _recalculateTotals() {
    // This method will be called when user applies price selections
    // Trigger a rebuild to recalculate totals with new price selections
    setState(() {
      // The state change will trigger a rebuild and recalculation
      // The _recalculateTotalsFromVendorAndExpenses() method will be called
      // and will use the updated _useNewSpecialPrices selections
    });
  }

  // Helper method to calculate the correct price for a vendor and item
  double _getCorrectPriceForVendorAndItem(String vendorName, String itemCode) {
    // Check for special price mismatches first
    if (_specialPriceMismatches.containsKey(vendorName) &&
        _specialPriceMismatches[vendorName]!.containsKey(itemCode) &&
        _useNewSpecialPrices.containsKey(vendorName) &&
        _useNewSpecialPrices[vendorName]!.containsKey(itemCode)) {
      final useNewPrice = _useNewSpecialPrices[vendorName]![itemCode];
      if (useNewPrice == true) {
        // Use current special price
        return _specialPriceMismatches[vendorName]![itemCode]!.toDouble();
      } else {
        // Use original special price from snapshot
        final specialPricesSnapshot =
            _dailyReport?['special_prices'] as Map<String, dynamic>? ?? {};
        if (specialPricesSnapshot.containsKey(vendorName)) {
          final vendorSpecialPrices =
              specialPricesSnapshot[vendorName] as Map<String, dynamic>? ?? {};
          if (vendorSpecialPrices.containsKey(itemCode)) {
            return (vendorSpecialPrices[itemCode] is num)
                ? (vendorSpecialPrices[itemCode] as num).toDouble()
                : 0.0;
          }
        }
      }
    }

    // Check for special prices for this vendor
    if (_userConfig != null && _userConfig!['special_prices'] != null) {
      final specialPrices =
          _userConfig!['special_prices'] as Map<String, dynamic>;
      if (specialPrices.containsKey(vendorName)) {
        final vendorSpecialPrices =
            specialPrices[vendorName] as Map<String, dynamic>? ?? {};
        if (vendorSpecialPrices.containsKey(itemCode)) {
          final specialPrice = vendorSpecialPrices[itemCode];
          if (specialPrice is num) {
            return specialPrice.toDouble();
          }
        }
      }
    }

    // Use the fixed chosen base price for this item
    if (_fixedItemPrices.containsKey(itemCode)) {
      return _fixedItemPrices[itemCode] ?? 0.0;
    }
    // Fallback to legacy base price resolution
    return _getItemPrice(itemCode);
  }

  // Simple method to update a single vendor item and recalculate everything
  void _updateVendorItem(String vendorName, String itemCode, int newQuantity) {
    // Compute delta
    final int oldQuantity = vendorItems[vendorName]![itemCode] ?? 0;
    final int delta = newQuantity - oldQuantity;

    // Update stored quantity
    vendorItems[vendorName]![itemCode] = newQuantity;

    // Determine price to apply (fixed base or special for this vendor)
    final double unitPrice = _getCorrectPriceForVendorAndItem(
      vendorName,
      itemCode,
    );

    // Adjust top-level aggregates by delta
    _editTotalSales = (_editTotalSales ?? 0) + delta;
    final double deltaRevenue = delta * unitPrice;
    final double currentAddition = _editAdditionRevenue ?? 0.0;
    final double currentExpenses = expenses.values
        .fold(0.0, (num acc, v) => acc + (v is num ? v.toDouble() : 0.0))
        .toDouble();

    final double currentRevenueExcludingAddition =
        (_editTotalRevenue ?? 0.0) - currentAddition;
    final double nextRevenueExcludingAddition =
        currentRevenueExcludingAddition + deltaRevenue;
    final double nextTotalRevenue =
        nextRevenueExcludingAddition + currentAddition;
    final double nextNetProfit = nextTotalRevenue - currentExpenses;

    _editTotalRevenue = nextTotalRevenue;
    _editNetProfit = nextNetProfit;

    // Sync item-level totals from vendor data to keep items list consistent
    _syncItemsFromVendorItems();
  }

  void _recalculateTotalsFromVendorAndExpenses() {
    int calcSales = 0;
    double calcRevenue = 0.0;
    vendorItems.forEach((vendorName, vendorItemsData) {
      vendorItemsData.forEach((itemCode, quantity) {
        if (quantity > 0) {
          calcSales += quantity;

          // Get the correct price for this item
          double itemPrice = _getItemPrice(itemCode);

          // Check for special prices for this vendor
          if (_userConfig != null && _userConfig!['special_prices'] != null) {
            final specialPrices =
                _userConfig!['special_prices'] as Map<String, dynamic>;
            if (specialPrices.containsKey(vendorName)) {
              final vendorSpecialPrices =
                  specialPrices[vendorName] as Map<String, dynamic>? ?? {};
              if (vendorSpecialPrices.containsKey(itemCode)) {
                final specialPrice = vendorSpecialPrices[itemCode];
                if (specialPrice is num) {
                  itemPrice = specialPrice.toDouble();
                }
              }
            }
          }

          calcRevenue += quantity * itemPrice;
        }
      });
    });

    // Add addition revenue to the total revenue
    final double additionRevenue = _editAdditionRevenue ?? 0.0;
    final double totalRevenueWithAddition = calcRevenue + additionRevenue;

    final double calcExpenses = expenses.values
        .fold(0.0, (num acc, v) => acc + (v is num ? v.toDouble() : 0.0))
        .toDouble();
    final double calcNetProfit = totalRevenueWithAddition - calcExpenses;

    _editTotalSales = calcSales;
    _editTotalRevenue = totalRevenueWithAddition;
    _editTotalExpenses = calcExpenses;
    _editNetProfit = calcNetProfit;
  }

  void _syncItemsFromVendorItems() {
    // Build totals per item code
    final Map<String, int> totalsByCode = {};
    final Map<String, List<String>> breakdownByCode = {};
    vendorItems.forEach((vendorName, itemsMap) {
      itemsMap.forEach((code, qty) {
        totalsByCode[code] = (totalsByCode[code] ?? 0) + qty;
        if (qty > 0) {
          breakdownByCode.putIfAbsent(code, () => <String>[]);
          breakdownByCode[code]!.add('$vendorName - $qty');
        }
      });
    });

    // Map current items by code for easy updates
    final Map<String, _EditableItemData> existing = {
      for (final it in items) it.code: it,
    };

    final List<_EditableItemData> nextItems = [];

    // First, add all existing items (including those with zero quantity)
    for (final existingItem in items) {
      final int totalQty = totalsByCode[existingItem.code] ?? 0;
      final List<String> vendorsList =
          breakdownByCode[existingItem.code] ?? const <String>[];

      nextItems.add(
        existingItem.copyWith(quantity: totalQty, vendors: vendorsList),
      );
    }

    // Then, add any new items that might have been added to vendors but not in the main items list
    totalsByCode.forEach((code, qty) {
      if (!existing.containsKey(code)) {
        final title = _getItemDisplayName(code);
        final price = _getPriceForItemCode(code);
        final vendorsList = breakdownByCode[code] ?? const <String>[];

        nextItems.add(
          _EditableItemData(
            code: code,
            title: title,
            quantity: qty,
            pricePerItem: price,
            vendors: vendorsList,
            isPriceEditable: false,
            isDeprecated: false,
          ),
        );
      }
    });

    // Sort by quantity desc to keep UI consistent
    nextItems.sort((a, b) => b.quantity.compareTo(a.quantity));
    items = nextItems;
  }

  Future<void> _saveChanges() async {
    setState(() {
      _isSaving = true;
    });

    try {
      // Check if this is a new report before saving
      final bool isNewReport = _dailyReport == null;

      // Reload old report to compute deltas against total_report
      final Map<String, dynamic>? oldReport =
          await FirestoreService.getDailyReport(widget.date);

      // Prepare updated data
      final Map<String, dynamic> updatedItemsSales = {};
      final Map<String, dynamic> updatedVendorSales = {};
      final Map<String, dynamic> updatedExpenses = {};

      // Update items sales from vendor data (only include items with quantity > 0)
      final Map<String, int> itemTotals = {};
      vendorItems.forEach((vendorName, vendorItemsData) {
        vendorItemsData.forEach((itemCode, quantity) {
          if (quantity > 0) {
            itemTotals[itemCode] = (itemTotals[itemCode] ?? 0) + quantity;
          }
        });
      });
      updatedItemsSales.addAll(itemTotals);

      // Update vendor sales
      vendorItems.forEach((vendorName, vendorItemsData) {
        final int totalVendorQuantity = vendorItemsData.values
            .where((qty) => qty > 0)
            .fold(0, (acc, qty) => acc + qty);
        double totalVendorRevenue = 0.0;

        final Map<String, dynamic> vendorItemsMap = {};
        vendorItemsData.forEach((itemCode, quantity) {
          if (quantity > 0) {
            vendorItemsMap[itemCode] = quantity;
            final double itemPrice = _getCorrectPriceForVendorAndItem(
              vendorName,
              itemCode,
            );
            totalVendorRevenue += quantity * itemPrice;
          }
        });

        if (totalVendorQuantity > 0) {
          updatedVendorSales[vendorName] = {
            'sale': totalVendorQuantity,
            'revenue': totalVendorRevenue,
            'items': vendorItemsMap,
          };
        }
      });

      // Update expenses
      updatedExpenses.addAll(expenses);

      // Calculate totals from vendor data (only count items with quantity > 0)
      int totalSales = 0;
      double totalRevenue = 0.0;

      vendorItems.forEach((vendorName, vendorItemsData) {
        vendorItemsData.forEach((itemCode, quantity) {
          if (quantity > 0) {
            totalSales += quantity;
            final double itemPrice = _getCorrectPriceForVendorAndItem(
              vendorName,
              itemCode,
            );
            totalRevenue += quantity * itemPrice;
          }
        });
      });

      // Add addition revenue to total revenue
      final double additionRevenue = _editAdditionRevenue ?? 0.0;
      final double totalRevenueWithAddition = totalRevenue + additionRevenue;

      final double totalExpenses = expenses.values
          .fold(
            0.0,
            (num acc, val) => acc + (val is num ? val.toDouble() : 0.0),
          )
          .toDouble();
      final double netProfit = totalRevenueWithAddition - totalExpenses;

      // Check if there are price mismatches and ask user which prices to save
      bool? shouldSaveWithNewPrices;
      if (_priceMismatches.isNotEmpty) {
        shouldSaveWithNewPrices = await _showSavePriceConfirmationDialog();
        if (shouldSaveWithNewPrices == null) {
          // User cancelled
          setState(() {
            _isSaving = false;
          });
          return;
        }
      }

      // Build item_prices_snapshot based on user's choice
      final Map<String, dynamic> itemPricesSnapshot = {};
      final Map<String, dynamic> originalSnapshot =
          _dailyReport?['item_prices_snapshot'] as Map<String, dynamic>? ?? {};

      for (var item in items) {
        if (_priceMismatches.containsKey(item.code) &&
            shouldSaveWithNewPrices != null) {
          if (shouldSaveWithNewPrices == true) {
            // Save current prices (user chose to update)
            itemPricesSnapshot[item.code] = item.pricePerItem;
          } else {
            // Save original prices (user chose to keep original)
            itemPricesSnapshot[item.code] =
                originalSnapshot[item.code] ?? item.pricePerItem;
          }
        } else {
          // No mismatch or no choice made, use current price
          itemPricesSnapshot[item.code] = item.pricePerItem;
        }
      }

      // Collect special prices used at the time of saving
      final Map<String, dynamic> specialPricesUsed = {};
      if (_userConfig != null) {
        final specialPricingVendors =
            _userConfig!['special_pricing_vendors'] as List<dynamic>? ?? [];
        final specialPrices =
            _userConfig!['special_prices'] as Map<String, dynamic>? ?? {};

        for (final vendorName in specialPricingVendors) {
          final vendorStr = vendorName.toString();
          if (vendorItems.containsKey(vendorStr) &&
              specialPrices.containsKey(vendorStr)) {
            final vendorSpecialPrices =
                specialPrices[vendorStr] as Map<String, dynamic>? ?? {};
            final Map<String, double> usedSpecialPrices = {};

            // Only include special prices for items that were actually sold
            vendorItems[vendorStr]!.forEach((itemCode, quantity) {
              if (quantity > 0 && vendorSpecialPrices.containsKey(itemCode)) {
                final price = vendorSpecialPrices[itemCode];
                if (price is num) {
                  usedSpecialPrices[itemCode] = price.toDouble();
                }
              }
            });

            if (usedSpecialPrices.isNotEmpty) {
              specialPricesUsed[vendorStr] = usedSpecialPrices;
            }
          }
        }
      }

      // Update the daily report payload
      final Map<String, dynamic> updatedReport = {
        ...(_dailyReport ?? {}),
        'items_sales': updatedItemsSales,
        'vendor_sales': updatedVendorSales,
        'expenses': updatedExpenses,
        'total_sales': totalSales,
        'total_revenue': totalRevenueWithAddition,
        'total_expenses': totalExpenses,
        'net_profit': netProfit,
        'addition_revenue': _editAdditionRevenue ?? 0.0,
        'item_prices_snapshot': itemPricesSnapshot,
        'special_prices': specialPricesUsed,
      };

      // Fetch current total_report
      final Map<String, dynamic> currentTotal =
          (await FirestoreService.getTotalReport()) ??
          {
            'items_sales': <String, int>{},
            'vendor_sales': <String, int>{},
            'total_sales': 0,
            'total_revenue': 0,
            'total_expenses': 0,
            'net_profit': 0,
            'dates_with_data': <String>[],
          };

      // Build mutable copies
      final Map<String, int> trItems = {
        for (final e
            in (currentTotal['items_sales'] as Map<String, dynamic>?)
                    ?.entries ??
                <MapEntry<String, dynamic>>[])
          e.key: (e.value is num) ? (e.value as num).toInt() : 0,
      };
      final Map<String, int> trVendors = {
        for (final e
            in (currentTotal['vendor_sales'] as Map<String, dynamic>?)
                    ?.entries ??
                <MapEntry<String, dynamic>>[])
          e.key: (e.value is num) ? (e.value as num).toInt() : 0,
      };
      int trTotalSales = (currentTotal['total_sales'] as num?)?.toInt() ?? 0;
      double trTotalRevenue =
          (currentTotal['total_revenue'] as num?)?.toDouble() ?? 0.0;
      double trTotalExpenses =
          (currentTotal['total_expenses'] as num?)?.toDouble() ?? 0.0;
      double trNetProfit =
          (currentTotal['net_profit'] as num?)?.toDouble() ?? 0.0;

      // Subtract old report contribution if exists
      if (oldReport != null) {
        final Map<String, dynamic> oldItems =
            oldReport['items_sales'] as Map<String, dynamic>? ?? {};
        final Map<String, dynamic> oldVendorSales =
            oldReport['vendor_sales'] as Map<String, dynamic>? ?? {};
        final int oldTotalSales =
            (oldReport['total_sales'] as num?)?.toInt() ?? 0;
        final int oldTotalRevenue =
            (oldReport['total_revenue'] as num?)?.toInt() ?? 0;
        final int oldTotalExpenses =
            (oldReport['total_expenses'] as num?)?.toInt() ?? 0;
        final int oldNetProfit =
            (oldReport['net_profit'] as num?)?.toInt() ?? 0;

        oldItems.forEach((code, qty) {
          final int q = (qty is num) ? qty.toInt() : 0;
          trItems[code] = (trItems[code] ?? 0) - q;
        });
        oldVendorSales.forEach((name, v) {
          // total_report stores vendor_sales as vendor -> total count
          if (v is Map<String, dynamic>) {
            final int sale = (v['sale'] as num?)?.toInt() ?? 0;
            trVendors[name] = (trVendors[name] ?? 0) - sale;
          }
        });
        trTotalSales -= oldTotalSales;
        trTotalRevenue -= oldTotalRevenue;
        trTotalExpenses -= oldTotalExpenses;
        trNetProfit -= oldNetProfit;
      }

      // Add new updated contribution
      updatedItemsSales.forEach((code, qty) {
        final int q = (qty is num) ? qty.toInt() : 0;
        trItems[code] = (trItems[code] ?? 0) + q;
      });
      updatedVendorSales.forEach((name, v) {
        if (v is Map<String, dynamic>) {
          final int sale = (v['sale'] as num?)?.toInt() ?? 0;
          trVendors[name] = (trVendors[name] ?? 0) + sale;
        }
      });
      trTotalSales += totalSales;
      trTotalRevenue += totalRevenueWithAddition;
      trTotalExpenses += totalExpenses;
      trNetProfit += netProfit;

      // Handle dates_with_data field
      final List<dynamic> datesWithData =
          (currentTotal['dates_with_data'] as List<dynamic>?) ?? [];
      final String dateString =
          '${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}';

      // Ensure the date is in dates_with_data (for both new and existing reports)
      if (!datesWithData.contains(dateString)) {
        datesWithData.add(dateString);
      }

      final Map<String, dynamic> newTotalReport = {
        'items_sales': trItems,
        'vendor_sales': trVendors,
        'total_sales': trTotalSales,
        'total_revenue': trTotalRevenue,
        'total_expenses': trTotalExpenses,
        'net_profit': trNetProfit,
        'dates_with_data': datesWithData,
      };

      // Persist: first total_report, then daily report
      await FirestoreService.updateTotalReport(newTotalReport);
      await FirestoreService.updateDailyReport(widget.date, updatedReport);

      // Print updated total_report data to console
      print(
        '=== TOTAL REPORT UPDATED AFTER ${isNewReport ? "SAVE" : "EDIT"} ===',
      );
      print('Date: $_dateLabel');
      print('Total Report Data:');
      print('  - Items Sales: ${newTotalReport['items_sales']}');
      print('  - Vendor Sales: ${newTotalReport['vendor_sales']}');
      print('  - Total Sales: ${newTotalReport['total_sales']}');
      print('  - Total Revenue: ${newTotalReport['total_revenue']}');
      print('  - Total Expenses: ${newTotalReport['total_expenses']}');
      print('  - Net Profit: ${newTotalReport['net_profit']}');
      print('  - Dates with Data: ${newTotalReport['dates_with_data']}');
      print('==========================================');

      // Refresh data from database to ensure we have the latest information
      await _refreshData();

      // Refresh user config and total report to ensure home and settings are updated
      await FirestoreService.refreshUserConfig();
      await FirestoreService.refreshTotalReport();

      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isNewReport
                  ? 'Report created successfully!'
                  : 'Report updated successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate back with result to trigger refresh on caller
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteReport() async {
    // Show confirmation dialog
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Delete Report',
            style: GoogleFonts.quicksand(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          content: Text(
            'Are you sure you want to delete this report for $_dateLabel? This action cannot be undone.',
            style: GoogleFonts.quicksand(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Delete',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // Get current total_report
      final Map<String, dynamic> currentTotal =
          (await FirestoreService.getTotalReport()) ??
          {
            'items_sales': <String, int>{},
            'vendor_sales': <String, int>{},
            'total_sales': 0,
            'total_revenue': 0,
            'total_expenses': 0,
            'net_profit': 0,
            'dates_with_data': <String>[],
          };

      // Build mutable copies
      final Map<String, int> trItems = {
        for (final e
            in (currentTotal['items_sales'] as Map<String, dynamic>?)
                    ?.entries ??
                <MapEntry<String, dynamic>>[])
          e.key: (e.value is num) ? (e.value as num).toInt() : 0,
      };
      final Map<String, int> trVendors = {
        for (final e
            in (currentTotal['vendor_sales'] as Map<String, dynamic>?)
                    ?.entries ??
                <MapEntry<String, dynamic>>[])
          e.key: (e.value is num) ? (e.value as num).toInt() : 0,
      };
      int trTotalSales = (currentTotal['total_sales'] as num?)?.toInt() ?? 0;
      int trTotalRevenue =
          (currentTotal['total_revenue'] as num?)?.toInt() ?? 0;
      int trTotalExpenses =
          (currentTotal['total_expenses'] as num?)?.toInt() ?? 0;
      int trNetProfit = (currentTotal['net_profit'] as num?)?.toInt() ?? 0;

      // Subtract current report's contribution from total_report
      if (_dailyReport != null) {
        final Map<String, dynamic> itemsSales =
            _dailyReport!['items_sales'] as Map<String, dynamic>? ?? {};
        final Map<String, dynamic> vendorSales =
            _dailyReport!['vendor_sales'] as Map<String, dynamic>? ?? {};
        final int totalSales =
            (_dailyReport!['total_sales'] as num?)?.toInt() ?? 0;
        final int totalRevenue =
            (_dailyReport!['total_revenue'] as num?)?.toInt() ?? 0;
        final int totalExpenses =
            (_dailyReport!['total_expenses'] as num?)?.toInt() ?? 0;
        final int netProfit =
            (_dailyReport!['net_profit'] as num?)?.toInt() ?? 0;

        // Subtract items sales
        itemsSales.forEach((code, qty) {
          final int q = (qty is num) ? qty.toInt() : 0;
          trItems[code] = (trItems[code] ?? 0) - q;
        });

        // Subtract vendor sales
        vendorSales.forEach((name, v) {
          if (v is Map<String, dynamic>) {
            final int sale = (v['sale'] as num?)?.toInt() ?? 0;
            trVendors[name] = (trVendors[name] ?? 0) - sale;
          }
        });

        // Subtract totals
        trTotalSales -= totalSales;
        trTotalRevenue -= totalRevenue;
        trTotalExpenses -= totalExpenses;
        trNetProfit -= netProfit;
      }

      // Remove the deleted date from dates_with_data array
      final List<dynamic> datesWithData =
          (currentTotal['dates_with_data'] as List<dynamic>?) ?? [];
      final String dateString =
          '${widget.date.year}-${widget.date.month.toString().padLeft(2, '0')}-${widget.date.day.toString().padLeft(2, '0')}';
      final List<dynamic> updatedDatesWithData = datesWithData
          .where((date) => date != dateString)
          .toList();

      final Map<String, dynamic> newTotalReport = {
        'items_sales': trItems,
        'vendor_sales': trVendors,
        'total_sales': trTotalSales,
        'total_revenue': trTotalRevenue,
        'total_expenses': trTotalExpenses,
        'net_profit': trNetProfit,
        'dates_with_data': updatedDatesWithData,
      };

      // Update total_report first, then delete the daily report
      await FirestoreService.updateTotalReport(newTotalReport);
      await FirestoreService.deleteDailyReport(widget.date);

      // Print updated total_report data to console
      print('=== TOTAL REPORT UPDATED AFTER DELETE ===');
      print('Date: $_dateLabel');
      print('Total Report Data:');
      print('  - Items Sales: ${newTotalReport['items_sales']}');
      print('  - Vendor Sales: ${newTotalReport['vendor_sales']}');
      print('  - Total Sales: ${newTotalReport['total_sales']}');
      print('  - Total Revenue: ${newTotalReport['total_revenue']}');
      print('  - Total Expenses: ${newTotalReport['total_expenses']}');
      print('  - Net Profit: ${newTotalReport['net_profit']}');
      print('  - Dates with Data: ${newTotalReport['dates_with_data']}');
      print('==========================================');

      // Refresh user config and total report to ensure home and settings are updated
      await FirestoreService.refreshUserConfig();
      await FirestoreService.refreshTotalReport();

      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate back to daily reports page and force rebuild of root by returning true
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const RootShell(initialIndex: 1),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
            'Edit Report for $_dateLabel',
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

    // Allow editing even when no data exists (for new reports)
    // The _initializeEditableData method handles null _dailyReport properly

    // Calculate totals from vendor data (live base values) - only count items with quantity > 0
    int totalQty = 0;
    int totalRevenue = 0;

    vendorItems.forEach((vendorName, vendorItemsData) {
      vendorItemsData.forEach((itemCode, quantity) {
        if (quantity > 0) {
          totalQty += quantity;
          final double itemPrice = _getCorrectPriceForVendorAndItem(
            vendorName,
            itemCode,
          );
          totalRevenue += (quantity * itemPrice).round();
        }
      });
    });

    final Map<String, double> dataMap = {
      for (final it in items)
        it.title: totalQty == 0 ? 0 : (it.quantity / totalQty) * 100.0,
    };

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

    // Create color lists for charts
    final List<Color> itemColors = dataMap.keys
        .toList()
        .asMap()
        .entries
        .map((entry) => colorPalette[entry.key % colorPalette.length])
        .toList();

    // Create vendor data map for pie chart (based on revenue, not quantity)
    final Map<String, double> vendorDataMap = {};
    int totalRevenueForPieChart = 0;

    // Get item prices snapshot for accurate price calculation
    final Map<String, dynamic> itemPricesSnapshot =
        _dailyReport?['item_prices_snapshot'] as Map<String, dynamic>? ?? {};

    // First, calculate total revenue from all vendors
    vendorItems.forEach((vendorName, items) {
      // Always include vendors in the data map, even if they have 0 quantity
      // This ensures vendor cards are always displayed for new reports
      // Calculate revenue for this vendor
      int vendorRevenue = 0;
      items.forEach((itemCode, quantity) {
        final int qty = quantity;
        if (qty > 0) {
          // Get price based on user's choice for mismatched items, otherwise use snapshot
          double price = 0.0;

          // FIRST: Check for regular price mismatches (snapshot vs config)
          if (_priceMismatches.containsKey(itemCode) &&
              _useNewPrices.containsKey(itemCode)) {
            if (_useNewPrices[itemCode] == true) {
              // Use current config price
              price = _priceMismatches[itemCode] ?? 0.0;
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
                  price = _specialPriceMismatches[vendorName]![itemCode]!;
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
                          ? (vendorSpecialPrices[itemCode] as num).toDouble()
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
          final int itemRevenue = (qty * price).round();
          vendorRevenue += itemRevenue;
        }
      });
      totalRevenueForPieChart += vendorRevenue;
    });

    // Now calculate percentages based on revenue
    vendorItems.forEach((vendorName, items) {
      // Always include vendors in the data map, even if they have 0 quantity
      // Calculate revenue for this vendor (same logic as above)
      int vendorRevenue = 0;
      items.forEach((itemCode, quantity) {
        final int qty = quantity;
        if (qty > 0) {
          // Get price based on user's choice for mismatched items, otherwise use snapshot
          double price = 0.0;

          // FIRST: Check for regular price mismatches (snapshot vs config)
          if (_priceMismatches.containsKey(itemCode) &&
              _useNewPrices.containsKey(itemCode)) {
            if (_useNewPrices[itemCode] == true) {
              // Use current config price
              price = _priceMismatches[itemCode] ?? 0.0;
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
                  price = _specialPriceMismatches[vendorName]![itemCode]!;
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
                          ? (vendorSpecialPrices[itemCode] as num).toDouble()
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
          final int itemRevenue = (qty * price).round();
          vendorRevenue += itemRevenue;
        }
      });

      // Calculate percentage based on revenue
      vendorDataMap[vendorName] = totalRevenueForPieChart == 0
          ? 0
          : (vendorRevenue / totalRevenueForPieChart) * 100.0;
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
              // Auto Fill Using Picture button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD9D9D9),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _autoFillFromImage,
                  icon: const Icon(Icons.camera_alt, size: 20),
                  label: Text(
                    'Auto Fill Using Picture',
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
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
              // Editable Quantity Produced & Vendors
              ...items
                  .asMap()
                  .entries
                  .map(
                    (entry) => Column(
                      children: [
                        _EditableItemCard(
                          item: entry.value,
                          color: itemColors[entry.key],
                          onPriceChanged: (newPrice) {
                            setState(() {
                              items[entry.key] = items[entry.key].copyWith(
                                pricePerItem: newPrice,
                              );
                              // Update fixed base price as well
                              _fixedItemPrices[items[entry.key].code] =
                                  newPrice;
                              // When price is edited, recalculate all totals
                              _recalculateTotalsFromVendorAndExpenses();
                            });
                          },
                        ),
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
                final Map<String, int> vendorItemsData =
                    vendorItems[vendorName] ?? {};

                final int totalQuantity = vendorItemsData.values
                    .where((qty) => qty > 0)
                    .fold(0, (acc, qty) => acc + qty);
                double totalRevenue = 0.0;
                final List<String> lines = [];

                vendorItemsData.forEach((itemCode, quantity) {
                  if (quantity > 0) {
                    // Get the correct price for this item
                    double itemPrice = _getItemPrice(itemCode);

                    // Check for special prices for this vendor
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
                          final specialPrice = vendorSpecialPrices[itemCode];
                          if (specialPrice is num) {
                            itemPrice = specialPrice.toDouble();
                          }
                        }
                      }
                    }

                    final double itemRevenue = quantity * itemPrice;
                    totalRevenue += itemRevenue;
                    final String displayName = _getItemDisplayName(itemCode);
                    lines.add(
                      '$displayName - $quantity X ${itemPrice.toStringAsFixed(2)} = ${_rupee(itemRevenue)}',
                    );
                  }
                });

                // Get color for this vendor (same order as pie chart)
                final Color vendorColor = vendorColors[vendorIndex];

                // Check if this vendor is deprecated
                final bool isDeprecated = deprecatedVendors.contains(
                  vendorName,
                );

                return Column(
                  children: [
                    _EditableVendorCard(
                      key: ValueKey('vendor-card-$vendorName'),
                      name: vendorName,
                      amountText: _rupee(totalRevenue),
                      lines: lines,
                      totalQuantityText: 'Total Quantity:- $totalQuantity',
                      onGenerateReceipt: () {},
                      color: vendorColor,
                      vendorItems: vendorItemsData,
                      isDeprecated: isDeprecated,
                      items: items,
                      getItemDisplayName: _getItemDisplayName,
                      getCorrectPriceForVendorAndItem:
                          _getCorrectPriceForVendorAndItem,
                      onVendorItemChanged: (itemCode, newQuantity) {
                        setState(() {
                          _updateVendorItem(vendorName, itemCode, newQuantity);
                        });
                      },
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
                    (entry) => _EditableExpenseRow(
                      label: '${entry.key} - ',
                      value: entry.value,
                      onChanged: (newValue) {
                        setState(() {
                          expenses[entry.key] = newValue;
                          // When expenses change, only totals should update
                          _recalculateTotalsFromVendorAndExpenses();
                        });
                      },
                    ),
                  )
                  .toList(),
              const Divider(thickness: 2),
              const SizedBox(height: 8),
              _ExpenseRow(
                label: 'Total Expenses',
                value: '₹${expenses.values.fold(0, (acc, val) => acc + val)}',
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
              _EditableSummaryRow(
                label: 'Total Sales',
                value: _editTotalSales ?? totalQty,
                onChanged: (v) {
                  setState(() {
                    _editTotalSales = v;
                  });
                },
              ),
              const SizedBox(height: 12),
              _MoneySummaryRow(
                label: 'Total Revenue',
                value: _editTotalRevenue ?? totalRevenue.toDouble(),
              ),
              const SizedBox(height: 12),
              _MoneySummaryRow(
                label: 'Total Expenses',
                value:
                    _editTotalExpenses ??
                    expenses.values
                        .fold(
                          0.0,
                          (num acc, val) =>
                              acc + (val is num ? val.toDouble() : 0.0),
                        )
                        .toDouble(),
              ),
              const SizedBox(height: 12),
              _EditableMoneyRow(
                label: 'Addition Revenue',
                value: _editAdditionRevenue ?? 0.0,
                onChanged: (v) {
                  setState(() {
                    _editAdditionRevenue = v;
                    _recalculateTotalsFromVendorAndExpenses();
                  });
                },
              ),
              const SizedBox(height: 12),
              _MoneySummaryRow(
                label: 'NET Profit',
                value:
                    _editNetProfit ??
                    (totalRevenue.toDouble() +
                        (_editAdditionRevenue ?? 0.0) -
                        expenses.values
                            .fold(
                              0.0,
                              (num acc, val) =>
                                  acc + (val is num ? val.toDouble() : 0.0),
                            )
                            .toDouble()),
              ),
              const SizedBox(height: 24),
              // Save and Cancel buttons
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD9D9D9),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.quicksand(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Save button
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSaving ? Colors.grey : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isSaving ? null : _saveChanges,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Save Changes',
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
          'Edit Report for $_dateLabel',
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
              if (value == 'delete') {
                _deleteReport();
              } else if (value == 'hide_pie_charts') {
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
              PopupMenuItem<String>(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(
                      'Delete Report',
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
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

  Future<void> _autoFillFromImage() async {
    File? tempFile;
    try {
      // Ask user to choose source
      final String? source = await showModalBottomSheet<String>(
        context: context,
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Take Photo'),
                  onTap: () => Navigator.of(context).pop('camera'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from Gallery'),
                  onTap: () => Navigator.of(context).pop('gallery'),
                ),
                const SizedBox(height: 4),
              ],
            ),
          );
        },
      );

      if (source == null) return;

      final XFile? picked = await _imagePicker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (picked == null) return;

      // Confirm preview
      final bool? confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: Text(
              'Use this image?',
              style: GoogleFonts.quicksand(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
            content: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(picked.path)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.red,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'Use',
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;

      // Get token
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
      final String? idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to get authentication token'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Show preprocessing dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            content: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preprocessing image…',
                        style: GoogleFonts.quicksand(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Uploading and creating extraction job',
                        style: GoogleFonts.quicksand(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

      // Step 1: Prepare multipart request to create extraction job.
      final uri = Uri.parse(
        'https://extract-data-from-image-cwo6krsusa-uc.a.run.app',
      );
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $idToken';

      // Read image as bytes to ensure proper encoding
      final imageBytes = await picked.readAsBytes();

      // Validate image size (optional: limit to reasonable size)
      if (imageBytes.isEmpty) {
        throw Exception('Selected image is empty or corrupted');
      }

      // Determine file extension and content type
      String fileExtension = '.jpg'; // Default to JPEG
      String contentType = 'image/jpeg';
      String originalFileName = picked.name.toLowerCase();

      if (originalFileName.endsWith('.png')) {
        fileExtension = '.png';
        contentType = 'image/png';
      } else if (originalFileName.endsWith('.jpg') ||
          originalFileName.endsWith('.jpeg')) {
        fileExtension = '.jpg';
        contentType = 'image/jpeg';
      }

      // Create a temporary file with proper extension
      final tempDir = Directory.systemTemp;
      tempFile = File(
        '${tempDir.path}/image_${DateTime.now().millisecondsSinceEpoch}$fileExtension',
      );

      // Write the image bytes to the temporary file
      await tempFile.writeAsBytes(imageBytes);

      // Verify the file was created and has content
      if (!await tempFile.exists() || await tempFile.length() == 0) {
        throw Exception('Failed to create temporary image file');
      }

      // Create multipart file from the temporary file path
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          tempFile.path,
          contentType: MediaType.parse(contentType),
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      // Clean up temporary file
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        print('Warning: Failed to delete temporary file: $e');
      }

      // Debug: print initial job creation response
      print('=== Extract Job Response ===');
      print('Status: ${response.statusCode}');
      print('Headers: ${response.headers}');
      print('Body: ${response.body}');

      if (response.statusCode != 200) {
        if (mounted && Navigator.of(context).canPop())
          Navigator.of(context).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to create extraction job. Status: ${response.statusCode}',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final Map<String, dynamic> jobResp = _safeDecodeJson(response.body);
      final String jobId = (jobResp['job_id'] ?? '').toString();
      if (jobId.isEmpty) {
        if (mounted && Navigator.of(context).canPop())
          Navigator.of(context).pop();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid job response from server'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Update dialog to show AI processing progress
      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              content: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Extracting data using AI…',
                          style: GoogleFonts.quicksand(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Job: $jobId',
                          style: GoogleFonts.quicksand(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }

      // Step 2: Poll the process endpoint until completed/failed
      final Map<String, dynamic> processResult = await _pollProcessOpenAIJob(
        jobId,
        idToken,
        timeout: const Duration(minutes: 2),
        interval: const Duration(seconds: 3),
      );

      if (mounted && Navigator.of(context).canPop())
        Navigator.of(context).pop();

      final String status = (processResult['status'] ?? '').toString();
      print('=== Process Job Final ===');
      print('Status: $status');
      print('Body: $processResult');

      if (status != 'completed') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Job not completed: $status'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Fetch final result from Firestore job document using uid/jobId
      Map<String, dynamic> parsed = {};
      dynamic rawResultForUser; // Keep the raw result to show on error
      try {
        final String uid = user.uid;
        final docSnap = await FirebaseFirestore.instance
            .collection('data_extraction_job')
            .doc(uid)
            .collection('jobs')
            .doc(jobId)
            .get(const GetOptions(source: Source.server));
        if (docSnap.exists) {
          final data = docSnap.data();
          if (data != null && data.containsKey('result')) {
            rawResultForUser = data['result'];
            if (rawResultForUser is Map<String, dynamic>) {
              parsed = rawResultForUser;
            } else if (rawResultForUser is String) {
              // Attempt to parse stringified JSON
              try {
                final dynamic maybe = jsonDecode(rawResultForUser);
                if (maybe is Map<String, dynamic>) parsed = maybe;
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        print('Error reading job result from Firestore: $e');
      }
      // Fallback to HTTP response result if Firestore empty
      if (parsed.isEmpty) {
        final dynamic resultJson = processResult['result'];
        rawResultForUser = resultJson;
        if (resultJson is Map<String, dynamic>) {
          parsed = resultJson;
        } else if (resultJson is String) {
          try {
            final dynamic maybe = jsonDecode(resultJson);
            if (maybe is Map<String, dynamic>) parsed = maybe;
          } catch (_) {}
        }
      }

      // Validate parsed content
      if (parsed.isEmpty || parsed['vendors'] == null) {
        // Try to parse raw result as string and strip markdown formatting
        if (rawResultForUser is String) {
          String cleanedJson = rawResultForUser.toString().trim();
          // Remove markdown code blocks
          if (cleanedJson.startsWith('```json')) {
            cleanedJson = cleanedJson.substring(7);
          }
          if (cleanedJson.startsWith('```')) {
            cleanedJson = cleanedJson.substring(3);
          }
          if (cleanedJson.endsWith('```')) {
            cleanedJson = cleanedJson.substring(0, cleanedJson.length - 3);
          }
          cleanedJson = cleanedJson.trim();

          try {
            final dynamic cleaned = jsonDecode(cleanedJson);
            if (cleaned is Map<String, dynamic>) {
              parsed = cleaned;
              print('Successfully parsed cleaned JSON: $parsed');
            }
          } catch (e) {
            print('Failed to parse cleaned JSON: $e');
          }
        }

        if (parsed.isEmpty || parsed['vendors'] == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: LLM result is not valid JSON.'),
              backgroundColor: Colors.red,
            ),
          );
          // Show raw data for user inspection
          // await _showRawResultDialog(rawResultForUser);
          return;
        }
      }

      // Map vendors/items with case-insensitive matching
      final List<dynamic> vendorsJson = (parsed['vendors'] is List)
          ? parsed['vendors'] as List
          : const [];

      print('=== AI EXTRACTION DEBUG ===');
      print('Vendors from AI: $vendorsJson');
      print('Current vendorItems keys: ${vendorItems.keys.toList()}');
      print('Current items codes: ${items.map((e) => e.code).toList()}');
      print('User config vendors: ${_userConfig?['vendors']}');
      print(
        'User config items: ${_userConfig?['items']?.map((e) => e['code']).toList()}',
      );

      // Build base with zeros for all existing vendors/items
      final Map<String, Map<String, int>> nextVendorItems = {
        for (final entry in vendorItems.entries)
          entry.key: {for (final it in entry.value.keys) it: 0},
      };

      // Case-insensitive lookup maps - include all possible vendors from config
      final Map<String, String> upperVendorToActual = {};
      if (_userConfig != null && _userConfig!['vendors'] != null) {
        final List<dynamic> configVendors =
            _userConfig!['vendors'] as List<dynamic>;
        for (final vendor in configVendors) {
          if (vendor is String && vendor.isNotEmpty) {
            upperVendorToActual[vendor.toUpperCase()] = vendor;
          }
        }
      }
      // Also include existing vendors
      for (final name in nextVendorItems.keys) {
        upperVendorToActual[name.toUpperCase()] = name;
      }

      final Map<String, String> upperCodeToActual = {
        for (final it in items) it.code.toUpperCase(): it.code,
      };

      print('upperVendorToActual map: $upperVendorToActual');
      print('upperCodeToActual map: $upperCodeToActual');

      int matchedVendors = 0;
      final Set<String> processedVendors =
          {}; // Track which vendors we've processed
      for (final v in vendorsJson) {
        if (v is! Map) continue;
        final String rawName = (v['name'] ?? '').toString().trim();
        if (rawName.isEmpty) continue;
        final String upperName = rawName.toUpperCase();
        final String actualVendorName =
            upperVendorToActual[upperName] ?? rawName; // fall back to raw

        print(
          'Processing vendor: rawName="$rawName", upperName="$upperName", actualVendorName="$actualVendorName"',
        );
        print('upperVendorToActual keys: ${upperVendorToActual.keys.toList()}');

        // Only count vendor once, not per item
        if (!processedVendors.contains(actualVendorName)) {
          processedVendors.add(actualVendorName);
          matchedVendors++;
          print(
            'Added vendor to processed: $actualVendorName, matchedVendors: $matchedVendors',
          );
        }

        // Ensure vendor entry exists
        nextVendorItems.putIfAbsent(
          actualVendorName,
          () => {for (final it in items) it.code: 0},
        );

        final List<dynamic> its = (v['items'] is List) ? v['items'] : const [];
        print('Items for vendor $rawName: $its');
        for (final it in its) {
          if (it is! Map) continue;
          String code = (it['item_name'] ?? '').toString().trim();
          if (code.startsWith(':')) code = code.substring(1);
          final String upperCode = code.toUpperCase();
          final String? actualCode = upperCodeToActual[upperCode];
          final dynamic qtyRaw = it['quantity'];
          final int? qty = (qtyRaw is num)
              ? qtyRaw.toInt()
              : int.tryParse(qtyRaw?.toString() ?? '');

          print(
            'Processing item: code="$code", upperCode="$upperCode", actualCode="$actualCode", qty=$qty',
          );

          if (qty == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Invalid quantity for $rawName/$code. Fix manually.',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
            continue;
          }

          if (actualCode == null) {
            print('Skipping unknown item code: $code');
            continue; // unknown item code; skip
          }

          nextVendorItems[actualVendorName] ??= {
            for (final it2 in items) it2.code: 0,
          };
          nextVendorItems[actualVendorName]![actualCode] = qty;
          print('Set $actualVendorName[$actualCode] = $qty');
        }
      }

      if (matchedVendors == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No matching vendors found in config to fill.'),
            backgroundColor: Colors.orange,
          ),
        );
        // await _showRawResultDialog(parsed);
        return;
      }

      print('Final nextVendorItems: $nextVendorItems');
      print('matchedVendors: $matchedVendors');
      print('Processed vendors: $processedVendors');

      // Show preview dialog before applying data
      if (!mounted) return;
      final bool? shouldApply = await _showDataPreviewDialog(
        nextVendorItems,
        vendorsJson,
      );

      if (shouldApply == true) {
        setState(() {
          vendorItems = nextVendorItems;
          _syncItemsFromVendorItems();
          _recalculateTotalsFromVendorAndExpenses();
        });

        print('After setState - vendorItems: $vendorItems');
        print(
          'After setState - items quantities: ${items.map((e) => '${e.code}: ${e.quantity}').toList()}',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data auto-filled from image.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data extraction cancelled.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      // Clean up temporary file if it exists
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (cleanupError) {
          print('Warning: Failed to delete temporary file: $cleanupError');
        }
      }

      if (!mounted) return;
      // Close any loader if open
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Map<String, dynamic> _safeDecodeJson(String body) {
    try {
      return body.isNotEmpty ? (jsonDecode(body) as Map<String, dynamic>) : {};
    } catch (_) {
      try {
        // Some backends may double-encode; attempt a second pass
        final dynamic first = jsonDecode(body);
        if (first is String) {
          return (jsonDecode(first) as Map<String, dynamic>);
        }
      } catch (_) {}
      return {};
    }
  }

  Future<bool?> _showDataPreviewDialog(
    Map<String, Map<String, int>> previewData,
    List<dynamic> originalVendorsJson,
  ) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _DataPreviewDialog(
          previewData: previewData,
          getItemDisplayName: _getItemDisplayName,
        );
      },
    );
  }

  // Removed unused debugging dialog _showRawResultDialog

  Future<Map<String, dynamic>> _pollProcessOpenAIJob(
    String jobId,
    String idToken, {
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 3),
  }) async {
    final Uri processUri = Uri.parse(
      'https://process-openai-job-cwo6krsusa-uc.a.run.app',
    );
    final DateTime deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        final resp = await http
            .post(
              processUri,
              headers: {
                'Authorization': 'Bearer $idToken',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'job_id': jobId}),
            )
            .timeout(const Duration(seconds: 30));

        print('=== Process Job Poll ===');
        print('Status: ${resp.statusCode}');
        print('Headers: ${resp.headers}');
        print('Body: ${resp.body}');

        if (resp.statusCode != 200) {
          await Future.delayed(interval);
          continue;
        }

        final Map<String, dynamic> parsed = _safeDecodeJson(resp.body);
        final String status = (parsed['status'] ?? '').toString();
        if (status == 'completed' || status == 'failed') {
          return parsed;
        }
      } catch (e) {
        print('Poll error: $e');
        // continue polling on transient errors
      }
      await Future.delayed(interval);
    }

    return {'status': 'timeout'};
  }
}

class _EditableItemData {
  final String code;
  final String title;
  final int quantity;
  final double pricePerItem;
  final List<String> vendors;
  final bool isPriceEditable; // true if item is not in config (deprecated)
  final bool isDeprecated; // true if item is not in config

  const _EditableItemData({
    required this.code,
    required this.title,
    required this.quantity,
    required this.pricePerItem,
    required this.vendors,
    this.isPriceEditable = false,
    this.isDeprecated = false,
  });

  double get totalRevenue => quantity * pricePerItem;

  _EditableItemData copyWith({
    String? code,
    String? title,
    int? quantity,
    double? pricePerItem,
    List<String>? vendors,
    bool? isPriceEditable,
    bool? isDeprecated,
  }) {
    return _EditableItemData(
      code: code ?? this.code,
      title: title ?? this.title,
      quantity: quantity ?? this.quantity,
      pricePerItem: pricePerItem ?? this.pricePerItem,
      vendors: vendors ?? this.vendors,
      isPriceEditable: isPriceEditable ?? this.isPriceEditable,
      isDeprecated: isDeprecated ?? this.isDeprecated,
    );
  }
}

class _EditableItemCard extends StatefulWidget {
  final _EditableItemData item;
  final Function(double)? onPriceChanged;
  final Color color;

  const _EditableItemCard({
    required this.item,
    this.onPriceChanged,
    required this.color,
  });

  @override
  State<_EditableItemCard> createState() => _EditableItemCardState();
}

class _EditableItemCardState extends State<_EditableItemCard> {
  bool _expanded = false;
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _priceController = TextEditingController(
      text: widget.item.pricePerItem.toString(),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _EditableItemData item = widget.item;
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
              // Read-only quantity display
              Row(
                children: [
                  Text(
                    'Quantity: ',
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      height: 1.25,
                    ),
                  ),
                  Text(
                    '${item.quantity}',
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Show deprecation warning if item is deprecated
              if (item.isDeprecated) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Item not in config - Price is editable',
                          style: GoogleFonts.quicksand(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[900],
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Price field (editable for deprecated items)
              Row(
                children: [
                  Text(
                    'Price per Item: ',
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                      height: 1.25,
                    ),
                  ),
                  if (item.isPriceEditable)
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            '₹',
                            style: GoogleFonts.quicksand(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextField(
                              controller: _priceController,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.quicksand(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              onChanged: (value) {
                                final price = double.tryParse(value);
                                if (price != null &&
                                    widget.onPriceChanged != null) {
                                  widget.onPriceChanged!(price);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      '₹${item.pricePerItem}',
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                        height: 1.25,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Vendors list
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
                'Item Revenue:- ${item.quantity} X ${_rupee(item.pricePerItem)} = ${_rupee(item.totalRevenue)}',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                  height: 1.25,
                ),
              ),
              Text(
                'At a price of ${_rupee(item.pricePerItem)} per Item',
                style: GoogleFonts.quicksand(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF333333),
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

// Removed old integer-based _SummaryRow (superseded by money/int specific rows)

String _rupee(num value) => '₹${value.toStringAsFixed(2)}';

// _SummaryRow removed; replaced with _EditableSummaryRow

class _MoneySummaryRow extends StatelessWidget {
  final String label;
  final double value;

  const _MoneySummaryRow({required this.label, required this.value});

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
          _rupee(value),
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

class _EditableSummaryRow extends StatefulWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _EditableSummaryRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_EditableSummaryRow> createState() => _EditableSummaryRowState();
}

class _EditableSummaryRowState extends State<_EditableSummaryRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant _EditableSummaryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != widget.value.toString()) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.label,
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black,
              height: 1.25,
            ),
          ),
        ),
        // No currency prefix for integer-only row
        SizedBox(
          width: 110,
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
              height: 1.25,
            ),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null) {
                widget.onChanged(parsed);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _EditableMoneyRow extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _EditableMoneyRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_EditableMoneyRow> createState() => _EditableMoneyRowState();
}

class _EditableMoneyRowState extends State<_EditableMoneyRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(covariant _EditableMoneyRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final next = widget.value.toStringAsFixed(2);
      if (_controller.text != next) {
        _controller.text = next;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.label,
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black,
              height: 1.25,
            ),
          ),
        ),
        const Text(
          '₹',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black,
            height: 1.25,
          ),
        ),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(
              signed: false,
              decimal: true,
            ),
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
              height: 1.25,
            ),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
            ),
            onChanged: (value) {
              final parsed = double.tryParse(value);
              if (parsed != null) {
                widget.onChanged(parsed);
              }
            },
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

  const _VendorCard({
    required this.name,
    required this.amountText,
    required this.lines,
    required this.totalQuantityText,
    required this.onGenerateReceipt,
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
                Expanded(
                  child: Text(
                    widget.name,
                    style: GoogleFonts.quicksand(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      height: 1.25,
                    ),
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
                    'Generate Receipt',
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

class _EditableExpenseRow extends StatefulWidget {
  final String label;
  final int value;
  final Function(int) onChanged;

  const _EditableExpenseRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_EditableExpenseRow> createState() => _EditableExpenseRowState();
}

class _EditableExpenseRowState extends State<_EditableExpenseRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            widget.label,
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black,
              height: 1.25,
            ),
          ),
        ),
        SizedBox(
          width: 100,
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
            ),
            onChanged: (value) {
              final amount = int.tryParse(value);
              if (amount != null) {
                widget.onChanged(amount);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _EditableVendorCard extends StatefulWidget {
  final String name;
  final String amountText;
  final List<String> lines;
  final String totalQuantityText;
  final VoidCallback onGenerateReceipt;
  final Color color;
  final Map<String, int> vendorItems;
  final Function(String, int) onVendorItemChanged;
  final bool isDeprecated;
  final List<_EditableItemData> items;
  final Function(String) getItemDisplayName;
  final Function(String, String) getCorrectPriceForVendorAndItem;

  const _EditableVendorCard({
    Key? key,
    required this.name,
    required this.amountText,
    required this.lines,
    required this.totalQuantityText,
    required this.onGenerateReceipt,
    required this.color,
    required this.vendorItems,
    required this.onVendorItemChanged,
    required this.items,
    required this.getItemDisplayName,
    required this.getCorrectPriceForVendorAndItem,
    this.isDeprecated = false,
  }) : super(key: key);

  @override
  State<_EditableVendorCard> createState() => _EditableVendorCardState();
}

class _DataPreviewDialog extends StatefulWidget {
  final Map<String, Map<String, int>> previewData;
  final Function(String) getItemDisplayName;

  const _DataPreviewDialog({
    required this.previewData,
    required this.getItemDisplayName,
  });

  @override
  State<_DataPreviewDialog> createState() => _DataPreviewDialogState();
}

class _DataPreviewDialogState extends State<_DataPreviewDialog> {
  late Map<String, Map<String, int>> editableData;
  late Map<String, Map<String, TextEditingController>> controllers;

  @override
  void initState() {
    super.initState();
    // Create editable copy of the data
    editableData = {};
    widget.previewData.forEach((vendorName, items) {
      editableData[vendorName] = Map<String, int>.from(items);
    });

    // Create controllers for all text fields
    controllers = {};
    editableData.forEach((vendorName, items) {
      controllers[vendorName] = {};
      items.forEach((itemCode, quantity) {
        controllers[vendorName]![itemCode] = TextEditingController(
          text: quantity.toString(),
        );
      });
    });
  }

  @override
  void dispose() {
    // Dispose all controllers
    controllers.forEach((vendor, itemControllers) {
      itemControllers.forEach((item, controller) {
        controller.dispose();
      });
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Review Extracted Data',
        style: GoogleFonts.quicksand(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.black,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Review and edit the extracted data before applying:',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ...editableData.entries.map((vendorEntry) {
                final String vendorName = vendorEntry.key;
                final Map<String, int> vendorItems = vendorEntry.value;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vendorName,
                          style: GoogleFonts.quicksand(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...vendorItems.entries.map((itemEntry) {
                          final String itemCode = itemEntry.key;
                          // quantity local var not needed

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    widget.getItemDisplayName(itemCode),
                                    style: GoogleFonts.quicksand(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 80,
                                  child: TextField(
                                    controller:
                                        controllers[vendorName]![itemCode],
                                    keyboardType: TextInputType.number,
                                    style: GoogleFonts.quicksand(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                      isDense: true,
                                    ),
                                    onChanged: (value) {
                                      final newQuantity =
                                          int.tryParse(value) ?? 0;
                                      setState(() {
                                        editableData[vendorName]![itemCode] =
                                            newQuantity;
                                      });
                                    },
                                  ),
                                ),
                              ],
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: GoogleFonts.quicksand(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            // Update the preview data with edited values
            widget.previewData.clear();
            widget.previewData.addAll(editableData);
            Navigator.of(context).pop(true);
          },
          child: Text(
            'Apply Data',
            style: GoogleFonts.quicksand(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.green,
            ),
          ),
        ),
      ],
    );
  }
}

class _EditableVendorCardState extends State<_EditableVendorCard> {
  bool _expanded = false;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    // Initialize controllers for all vendor items
    widget.vendorItems.forEach((itemCode, quantity) {
      _controllers[itemCode] = TextEditingController(text: quantity.toString());
    });
  }

  @override
  void didUpdateWidget(_EditableVendorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controllers with latest vendorItems values to avoid stale leakage
    // Add missing controllers and update existing text to match current quantities
    widget.vendorItems.forEach((itemCode, quantity) {
      final String textValue = quantity.toString();
      if (!_controllers.containsKey(itemCode)) {
        _controllers[itemCode] = TextEditingController(text: textValue);
      } else if (_controllers[itemCode]!.text != textValue) {
        _controllers[itemCode]!.text = textValue;
      }
    });

    // Remove controllers for items that no longer exist
    final keysToRemove = _controllers.keys
        .where((key) => !widget.vendorItems.containsKey(key))
        .toList();
    for (final key in keysToRemove) {
      _controllers[key]!.dispose();
      _controllers.remove(key);
    }
  }

  @override
  void dispose() {
    // Dispose all controllers
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

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
              // Editable vendor items
              ...widget.vendorItems.entries.map((entry) {
                final String itemCode = entry.key;
                final int quantity = entry.value;

                // Get the item data to find price (not needed as we use pricing helper)

                // Calculate the correct price for this vendor and item
                double itemPrice = widget.getCorrectPriceForVendorAndItem(
                  widget.name,
                  itemCode,
                );

                final double itemRevenue = quantity * itemPrice;
                final String displayName = widget.getItemDisplayName(itemCode);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: GoogleFonts.quicksand(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                                height: 1.25,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: _controllers[itemCode],
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.quicksand(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                              ),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                              ),
                              onChanged: (value) {
                                // Don't update in real-time, just store the value
                                // The actual update will happen on onSubmitted or onEditingComplete
                              },
                              onSubmitted: (value) {
                                // Update when user presses OK/Enter
                                if (value.isEmpty) {
                                  widget.onVendorItemChanged(itemCode, 0);
                                } else {
                                  final qty = int.tryParse(value);
                                  if (qty != null && qty >= 0) {
                                    if ((_controllers[itemCode]?.text ?? '') !=
                                        qty.toString()) {
                                      _controllers[itemCode]?.text = qty
                                          .toString();
                                    }
                                    widget.onVendorItemChanged(itemCode, qty);
                                  }
                                }
                              },
                              onEditingComplete: () {
                                // Update when user finishes editing (moves to another field)
                                final value =
                                    _controllers[itemCode]?.text ?? '';
                                if (value.isEmpty) {
                                  widget.onVendorItemChanged(itemCode, 0);
                                } else {
                                  final qty = int.tryParse(value);
                                  if (qty != null && qty >= 0) {
                                    if ((_controllers[itemCode]?.text ?? '') !=
                                        qty.toString()) {
                                      _controllers[itemCode]?.text = qty
                                          .toString();
                                    }
                                    widget.onVendorItemChanged(itemCode, qty);
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Show the money calculation like in details page
                      Text(
                        '$displayName - $quantity X ${itemPrice.toStringAsFixed(2)} = ${_rupee(itemRevenue)}',
                        style: GoogleFonts.quicksand(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
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
            ],
          ],
        ),
      ),
    );
  }
}
