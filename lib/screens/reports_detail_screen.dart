import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pie_chart/pie_chart.dart';
import '../firestore_service.dart';
import '../pdf_service.dart';

class ReportsDetailScreen extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;

  const ReportsDetailScreen({
    super.key,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<ReportsDetailScreen> createState() => _ReportsDetailScreenState();
}

class _ReportsDetailScreenState extends State<ReportsDetailScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _aggregatedReport;
  Map<String, dynamic>? _userConfig;
  String? _errorMessage;
  bool _hidePieCharts = false;

  String get _dateRangeLabel =>
      '${widget.startDate.day.toString().padLeft(2, '0')}/${widget.startDate.month.toString().padLeft(2, '0')}/${widget.startDate.year} to ${widget.endDate.day.toString().padLeft(2, '0')}/${widget.endDate.month.toString().padLeft(2, '0')}/${widget.endDate.year}';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Validate date range
      if (widget.endDate.isBefore(widget.startDate)) {
        if (mounted) {
          setState(() {
            _errorMessage =
                'Invalid date range: End date cannot be before start date';
            _isLoading = false;
          });
        }
        return;
      }

      // Load user config for item names
      final config = await FirestoreService.getUserConfig();
      // Load aggregated report data
      final report = await FirestoreService.getReportsByDateRange(
        widget.startDate,
        widget.endDate,
      );

      if (mounted) {
        setState(() {
          _userConfig = config;
          _aggregatedReport = report;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading report data: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
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

  // Helper method to get normal price for item
  double _getNormalPriceForItem(String itemCode) {
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

  // Helper method to calculate the correct price for a vendor and item
  double _getCorrectPriceForVendorAndItem(String vendorName, String itemCode) {
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

    // Fall back to normal price
    return _getNormalPriceForItem(itemCode);
  }

  // Helper method to format currency values with decimals
  String _formatCurrency(dynamic value) {
    if (value is num) {
      return '₹${value.toDouble().toStringAsFixed(2)}';
    }
    return '₹0.00';
  }

  // Generate and save PDF report
  void _generatePdfReport() {
    _saveReport();
  }

  // Save the report as PDF
  Future<void> _saveReport() async {
    if (_aggregatedReport == null) return;

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Center(child: CircularProgressIndicator());
        },
      );

      await PdfService.generateAndSaveReport(
        reportData: _aggregatedReport!,
        userConfig: _userConfig,
        startDate: widget.startDate,
        endDate: widget.endDate,
        getItemDisplayName: _getItemDisplayName,
        getNormalPriceForItem: _getNormalPriceForItem,
        getCorrectPriceForVendorAndItem: _getCorrectPriceForVendorAndItem,
      );

      // Hide loading indicator
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Report saved as PDF successfully',
              style: GoogleFonts.quicksand(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: Colors.green[600],
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      // Hide loading indicator
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error saving report: ${e.toString()}',
              style: GoogleFonts.quicksand(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: Colors.red[600],
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    const double _scrollBarReserve = 88;

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
            'Report $_dateRangeLabel',
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

    // Show error state
    if (_errorMessage != null) {
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
            'Report $_dateRangeLabel',
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
                Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  'Error',
                  style: GoogleFonts.quicksand(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.red[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loadData,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show no data state
    if (_aggregatedReport == null) {
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
            'Report $_dateRangeLabel',
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
                  'No reports found for the selected date range. Please check if data has been entered for these dates.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Safety check - this should not happen since we check for null above
    if (_aggregatedReport == null) {
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
            'Report $_dateRangeLabel',
            style: GoogleFonts.quicksand(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
        ),
        body: const Center(child: Text('Unexpected error: No data available')),
      );
    }

    // Process dynamic data
    final Map<String, dynamic> itemsSales =
        _aggregatedReport!['items_sales'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> vendorSales =
        _aggregatedReport!['vendor_sales'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> expenses =
        _aggregatedReport!['expenses'] as Map<String, dynamic>? ?? {};

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
    final List<_ItemData> items = [];
    itemsSales.forEach((code, quantity) {
      final String displayName = _getItemDisplayName(code);
      final int qty = (quantity is num) ? quantity.toInt() : 0;

      // Get price from config (use normal price for items list display)
      double pricePerItem = _getNormalPriceForItem(code);

      // Get vendor breakdown for this item and calculate actual revenue
      final List<String> vendorBreakdown = [];
      double calculatedTotalRevenue = 0.0;

      vendorSales.forEach((vendorName, vendorData) {
        if (vendorData is Map<String, dynamic> && vendorData['items'] != null) {
          final Map<String, dynamic> vendorItems =
              vendorData['items'] as Map<String, dynamic>;
          if (vendorItems.containsKey(code)) {
            final int vendorQty = (vendorItems[code] is num)
                ? vendorItems[code].toInt()
                : 0;
            if (vendorQty > 0) {
              // Get the correct price for this vendor and item (special price if available)
              final double vendorPrice = _getCorrectPriceForVendorAndItem(
                vendorName,
                code,
              );
              final double vendorRevenue = vendorQty * vendorPrice;
              calculatedTotalRevenue += vendorRevenue;

              vendorBreakdown.add('$vendorName - $vendorQty');
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
          pricePerItem: pricePerItem,
          totalRevenue: calculatedTotalRevenue,
          vendors: vendorBreakdown,
          color: itemColor,
        ),
      );
    });

    // Sort items by quantity (highest first)
    items.sort((a, b) => b.quantity.compareTo(a.quantity));

    // Update item colors to match pie chart order (after sorting)
    for (int i = 0; i < items.length; i++) {
      items[i] = _ItemData(
        title: items[i].title,
        quantity: items[i].quantity,
        pricePerItem: items[i].pricePerItem,
        totalRevenue: items[i].totalRevenue,
        vendors: items[i].vendors,
        color: colorPalette[i % colorPalette.length],
      );
    }

    final int totalQty = items.fold(0, (acc, it) => acc + it.quantity);
    final Map<String, double> dataMap = {
      for (final it in items)
        it.title: totalQty == 0 ? 0 : (it.quantity / totalQty) * 100.0,
    };

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
              // Get correct price (special price if available, otherwise normal price)
              final double price = _getCorrectPriceForVendorAndItem(
                vendorName,
                itemCode,
              );
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
              // Get correct price (special price if available, otherwise normal price)
              final double price = _getCorrectPriceForVendorAndItem(
                vendorName,
                itemCode,
              );
              final double itemRevenue = qty * price;
              vendorRevenue += itemRevenue;
            }
          });

          // Calculate percentage based on revenue
          vendorDataMap[vendorName] = totalRevenueForPieChart == 0
              ? 0.0
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

    // Create color lists for charts
    final List<Color> itemColors = dataMap.keys
        .toList()
        .asMap()
        .entries
        .map((entry) => colorPalette[entry.key % colorPalette.length])
        .toList();

    final List<Color> vendorColors = sortedVendorDataMap.keys
        .toList()
        .asMap()
        .entries
        .map((entry) => colorPalette[entry.key % colorPalette.length])
        .toList();

    // Find best performing item and vendor
    String bestItem = 'N/A';
    String bestVendor = 'N/A';
    if (items.isNotEmpty) {
      bestItem = items.first.title;
    }
    if (sortedVendorDataMap.isNotEmpty) {
      bestVendor = sortedVendorDataMap.keys.first;
    }

    // Recalculate totals from individual items/expenses to ensure accuracy
    // Total revenue is already calculated as totalRevenueForPieChart
    double calculatedTotalRevenue = totalRevenueForPieChart;

    // Calculate total expenses from individual expense entries
    double calculatedTotalExpenses = 0.0;
    expenses.forEach((category, amount) {
      calculatedTotalExpenses += (amount is num) ? amount.toDouble() : 0.0;
    });

    // Get addition revenue from aggregated report
    final double additionRevenue =
        (_aggregatedReport!['addition_revenue'] is num)
        ? (_aggregatedReport!['addition_revenue'] as num).toDouble()
        : 0.0;

    // Calculate net profit
    final double calculatedNetProfit =
        calculatedTotalRevenue + additionRevenue - calculatedTotalExpenses;

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

              // Report Header
              Text(
                'Report from $_dateRangeLabel:-',
                style: GoogleFonts.quicksand(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 24),

              // Summary Section
              Text(
                'Summary:-',
                style: GoogleFonts.quicksand(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),

              // Summary metrics
              _SummaryRow(
                label: 'Total Sales',
                value: '${_aggregatedReport!['total_sales'] ?? 0}',
              ),
              _SummaryRow(
                label: 'Total Revenue',
                value: _formatCurrency(calculatedTotalRevenue),
              ),
              _SummaryRow(
                label: 'Total Expense',
                value: _formatCurrency(calculatedTotalExpenses),
              ),
              _SummaryRow(
                label: 'Addition Revenue',
                value: _formatCurrency(additionRevenue),
              ),
              _SummaryRow(
                label: 'Net Profit',
                value: _formatCurrency(calculatedNetProfit),
              ),
              _SummaryRow(label: 'Best Performing Item', value: bestItem),
              _SummaryRow(label: 'Best Performing Vendor', value: bestVendor),

              const SizedBox(height: 24),

              const SizedBox(height: 16),

              // Two pie charts side by side
              if (!_hidePieCharts)
                Row(
                  children: [
                    // Items pie chart
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Items',
                            style: GoogleFonts.quicksand(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: size.width * 0.35,
                            height: size.width * 0.35,
                            child: PieChart(
                              dataMap: dataMap,
                              animationDuration: const Duration(
                                milliseconds: 800,
                              ),
                              chartType: ChartType.disc,
                              baseChartColor: const Color(0xFFD9D9D9),
                              colorList: itemColors,
                              chartValuesOptions: const ChartValuesOptions(
                                showChartValues: true,
                                showChartValuesInPercentage: true,
                                showChartValuesOutside: true,
                                chartValueStyle: TextStyle(
                                  fontSize: 10,
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
                    const SizedBox(width: 16),
                    // Vendors pie chart
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Vendors',
                            style: GoogleFonts.quicksand(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: size.width * 0.35,
                            height: size.width * 0.35,
                            child: PieChart(
                              dataMap: sortedVendorDataMap,
                              animationDuration: const Duration(
                                milliseconds: 800,
                              ),
                              chartType: ChartType.disc,
                              baseChartColor: const Color(0xFFD9D9D9),
                              colorList: vendorColors,
                              chartValuesOptions: const ChartValuesOptions(
                                showChartValues: true,
                                showChartValuesInPercentage: true,
                                showChartValuesOutside: true,
                                chartValueStyle: TextStyle(
                                  fontSize: 10,
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
                  ],
                ),

              const SizedBox(height: 50),

              // Quantity Produced heading
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
                final Map<String, dynamic> vendorItems =
                    vendorData['items'] as Map<String, dynamic>? ?? {};

                final List<String> lines = [];
                double calculatedTotalRevenue = 0.0;
                vendorItems.forEach((itemCode, quantity) {
                  final int qty = (quantity is num) ? quantity.toInt() : 0;
                  if (qty > 0) {
                    final String displayName = _getItemDisplayName(itemCode);
                    // Get correct price (special price if available, otherwise normal price)
                    final double price = _getCorrectPriceForVendorAndItem(
                      vendorName,
                      itemCode,
                    );
                    final double itemRevenue = qty * price;
                    calculatedTotalRevenue += itemRevenue;
                    lines.add(
                      '$displayName - $qty X ${price.toStringAsFixed(2)} = ₹${itemRevenue.toStringAsFixed(2)}',
                    );
                  }
                });

                // Get color for this vendor (same order as pie chart)
                final Color vendorColor = vendorColors[vendorIndex];

                return Column(
                  children: [
                    _VendorCard(
                      name: vendorName,
                      amountText:
                          '₹${calculatedTotalRevenue.toStringAsFixed(2)}',
                      lines: lines,
                      totalQuantityText: 'Total Quantity:- $totalQuantity',
                      onGenerateReceipt: () {},
                      color: vendorColor,
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
                      value: _formatCurrency(entry.value),
                    ),
                  )
                  .toList(),
              const Divider(thickness: 2),
              const SizedBox(height: 8),
              _ExpenseRow(
                label: 'Total Expenses',
                value: _formatCurrency(calculatedTotalExpenses),
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
              _SummaryRow(
                label: 'Total Sales',
                value: '${_aggregatedReport!['total_sales'] ?? 0}',
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Total Revenue',
                value: _formatCurrency(calculatedTotalRevenue),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Total Expenses',
                value: _formatCurrency(calculatedTotalExpenses),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'Addition Revenue',
                value: _formatCurrency(additionRevenue),
              ),
              const SizedBox(height: 12),
              _SummaryRow(
                label: 'NET Profit',
                value: _formatCurrency(calculatedNetProfit),
              ),
              const SizedBox(height: 24),

              // Print button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A5AE0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _generatePdfReport(),
                  icon: const Icon(Icons.download, size: 20),
                  label: Text(
                    'Download PDF',
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
          'Report $_dateRangeLabel',
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

// Reuse the same helper classes from daily_report_detail_screen.dart
class _ItemData {
  final String title;
  final int quantity;
  final double pricePerItem;
  final double totalRevenue;
  final List<String> vendors;
  final Color color;

  const _ItemData({
    required this.title,
    required this.quantity,
    required this.pricePerItem,
    required this.totalRevenue,
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
              Text(
                'Total Quantity: ${item.quantity}',
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

  const _VendorCard({
    required this.name,
    required this.amountText,
    required this.lines,
    required this.totalQuantityText,
    required this.onGenerateReceipt,
    required this.color,
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
            ],
          ],
        ),
      ),
    );
  }
}
