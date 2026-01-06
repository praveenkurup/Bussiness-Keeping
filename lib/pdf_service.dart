import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

class PdfService {
  static Future<void> generateAndSaveReport({
    required Map<String, dynamic> reportData,
    required Map<String, dynamic>? userConfig,
    required DateTime startDate,
    required DateTime endDate,
    required String Function(String) getItemDisplayName,
    required double Function(String) getNormalPriceForItem,
    required double Function(String, String) getCorrectPriceForVendorAndItem,
  }) async {
    try {
      // Generate PDF
      final pdf = await _generateReportPdf(
        reportData: reportData,
        userConfig: userConfig,
        startDate: startDate,
        endDate: endDate,
        getItemDisplayName: getItemDisplayName,
        getNormalPriceForItem: getNormalPriceForItem,
        getCorrectPriceForVendorAndItem: getCorrectPriceForVendorAndItem,
      );

      // Save to file
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'Business_Report_${startDate.day}_${startDate.month}_${startDate.year}_to_${endDate.day}_${endDate.month}_${endDate.year}.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      // Open the file
      await OpenFile.open(file.path);
    } catch (e) {
      print('Error saving PDF: $e');
      rethrow;
    }
  }

  static Future<pw.Document> _generateReportPdf({
    required Map<String, dynamic> reportData,
    required Map<String, dynamic>? userConfig,
    required DateTime startDate,
    required DateTime endDate,
    required String Function(String) getItemDisplayName,
    required double Function(String) getNormalPriceForItem,
    required double Function(String, String) getCorrectPriceForVendorAndItem,
  }) async {
    final pdf = pw.Document();

    // Process data
    final Map<String, dynamic> itemsSales =
        reportData['items_sales'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> vendorSales =
        reportData['vendor_sales'] as Map<String, dynamic>? ?? {};
    final Map<String, dynamic> expenses =
        reportData['expenses'] as Map<String, dynamic>? ?? {};

    // Create items list
    final List<Map<String, dynamic>> items = [];
    itemsSales.forEach((code, quantity) {
      final String displayName = getItemDisplayName(code);
      final int qty = (quantity is num) ? quantity.toInt() : 0;
      final double pricePerItem = getNormalPriceForItem(code);

      // Calculate actual revenue using vendor-specific prices
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
              final double vendorPrice = getCorrectPriceForVendorAndItem(
                vendorName,
                code,
              );
              final double vendorRevenue = vendorQty * vendorPrice;
              calculatedTotalRevenue += vendorRevenue;
            }
          }
        }
      });

      items.add({
        'name': displayName,
        'quantity': qty,
        'price': pricePerItem,
        'revenue': calculatedTotalRevenue,
      });
    });

    // Sort items by quantity
    items.sort((a, b) => b['quantity'].compareTo(a['quantity']));

    // Create vendor list with detailed item breakdown
    final List<Map<String, dynamic>> vendors = [];
    vendorSales.forEach((vendorName, vendorData) {
      if (vendorData is Map<String, dynamic> && vendorData['sale'] != null) {
        final int totalQuantity = (vendorData['sale'] is num)
            ? vendorData['sale'].toInt()
            : 0;

        if (totalQuantity > 0) {
          // Get detailed item breakdown for this vendor
          final Map<String, dynamic> vendorItems =
              vendorData['items'] as Map<String, dynamic>? ?? {};
          final List<Map<String, dynamic>> itemBreakdown = [];
          double calculatedTotalRevenue = 0.0;

          vendorItems.forEach((itemCode, quantity) {
            final int qty = (quantity is num) ? quantity.toInt() : 0;
            if (qty > 0) {
              final String displayName = getItemDisplayName(itemCode);
              final double price = getCorrectPriceForVendorAndItem(
                vendorName,
                itemCode,
              );
              final double itemRevenue = qty * price;
              calculatedTotalRevenue += itemRevenue;

              itemBreakdown.add({
                'itemName': displayName,
                'itemCode': itemCode,
                'quantity': qty,
                'price': price,
                'revenue': itemRevenue,
              });
            }
          });

          // Sort items by revenue (highest first)
          itemBreakdown.sort(
            (a, b) =>
                (b['revenue'] as double).compareTo(a['revenue'] as double),
          );

          vendors.add({
            'name': vendorName,
            'quantity': totalQuantity,
            'revenue': calculatedTotalRevenue,
            'items': itemBreakdown,
          });
        }
      }
    });

    // Sort vendors by revenue
    vendors.sort(
      (a, b) => (b['revenue'] as num).compareTo(a['revenue'] as num),
    );

    // Create expenses list
    final List<Map<String, dynamic>> expensesList = [];
    double calculatedTotalExpenses = 0.0;
    expenses.forEach((key, value) {
      final double amount = (value is num) ? value.toDouble() : 0.0;
      if (amount > 0) {
        calculatedTotalExpenses += amount;
        expensesList.add({'name': key, 'amount': amount});
      }
    });

    // Recalculate totals from individual items/expenses to ensure accuracy
    double calculatedTotalRevenue = 0.0;
    vendors.forEach((vendor) {
      calculatedTotalRevenue += (vendor['revenue'] as num).toDouble();
    });

    // Get addition revenue from report data
    final double additionRevenue = (reportData['addition_revenue'] is num)
        ? (reportData['addition_revenue'] as num).toDouble()
        : 0.0;

    // Calculate net profit
    final double calculatedNetProfit =
        calculatedTotalRevenue + additionRevenue - calculatedTotalExpenses;

    // Add pages to PDF with better page break handling
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            _buildHeader(startDate, endDate, userConfig),
            pw.SizedBox(height: 20),

            // Summary Section
            _buildSummarySection(
              calculatedTotalRevenue,
              calculatedTotalExpenses,
              additionRevenue,
              calculatedNetProfit,
              reportData['total_sales'] ?? 0,
            ),
            pw.SizedBox(height: 20),

            // Items Section
            _buildItemsSection(items),
            pw.SizedBox(height: 20),

            // Vendors Section
            _buildVendorsSection(vendors),
            pw.SizedBox(height: 20),

            // Expenses Section
            _buildExpensesSection(expensesList, calculatedTotalExpenses),
            pw.SizedBox(height: 20),

            // Totals Section
            _buildTotalsSection(
              calculatedTotalRevenue,
              calculatedTotalExpenses,
              additionRevenue,
              calculatedNetProfit,
              reportData['total_sales'] ?? 0,
            ),
          ];
        },
        // Enable automatic page breaks
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        header: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 20),
            child: pw.Text(
              'Page ${context.pageNumber}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          );
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _buildHeader(
    DateTime startDate,
    DateTime endDate,
    Map<String, dynamic>? userConfig,
  ) {
    final String dateRange =
        '${startDate.day.toString().padLeft(2, '0')}/${startDate.month.toString().padLeft(2, '0')}/${startDate.year} to ${endDate.day.toString().padLeft(2, '0')}/${endDate.month.toString().padLeft(2, '0')}/${endDate.year}';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // Business Name
        pw.Text(
          userConfig?['business_name'] ?? 'BUSINESS REPORT',
          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),

        // Business Address
        if (userConfig?['address'] != null &&
            (userConfig!['address'] as String).isNotEmpty)
          pw.Text(
            userConfig['address'] as String,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.normal),
            textAlign: pw.TextAlign.center,
          ),

        // Business Contact Info
        if (userConfig != null) ...[
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              if (userConfig['phone'] != null &&
                  (userConfig['phone'] as String).isNotEmpty)
                pw.Text(
                  'Phone: ${userConfig['phone']}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.normal,
                  ),
                ),
              if (userConfig['phone'] != null && userConfig['email'] != null)
                pw.Text(' | ', style: pw.TextStyle(fontSize: 12)),
              if (userConfig['email'] != null &&
                  (userConfig['email'] as String).isNotEmpty)
                pw.Text(
                  'Email: ${userConfig['email']}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.normal,
                  ),
                ),
            ],
          ),
        ],

        pw.SizedBox(height: 16),
        pw.Divider(thickness: 1),
        pw.SizedBox(height: 8),

        // Report Title
        pw.Text(
          'SALES REPORT',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Period: $dateRange',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.normal),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated on: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.normal),
        ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 2),
      ],
    );
  }

  static pw.Widget _buildSummarySection(
    double totalRevenue,
    double totalExpenses,
    double additionRevenue,
    double netProfit,
    dynamic totalSales,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'SUMMARY',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        _buildSummaryRow('Total Sales', '${totalSales}'),
        _buildSummaryRow(
          'Total Revenue',
          'Rs.${totalRevenue.toStringAsFixed(2)}',
        ),
        _buildSummaryRow(
          'Total Expenses',
          'Rs.${totalExpenses.toStringAsFixed(2)}',
        ),
        _buildSummaryRow(
          'Additional Revenue',
          'Rs.${additionRevenue.toStringAsFixed(2)}',
        ),
        _buildSummaryRow('Net Profit', 'Rs.${netProfit.toStringAsFixed(2)}'),
      ],
    );
  }

  static pw.Widget _buildItemsSection(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'ITEMS PRODUCED',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Text('No items produced in this period.'),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ITEMS PRODUCED',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Table(
          border: pw.TableBorder.all(),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2),
          },
          children: [
            // Header
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _buildTableCell('Item Name', isHeader: true),
                _buildTableCell('Qty', isHeader: true),
                _buildTableCell('Total Revenue', isHeader: true),
              ],
            ),
            // Data rows
            ...items.map(
              (item) => pw.TableRow(
                children: [
                  _buildTableCell(item['name']),
                  _buildTableCell(item['quantity'].toString()),
                  _buildTableCell(
                    'Rs.${(item['revenue'] as num).toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildVendorsSection(List<Map<String, dynamic>> vendors) {
    if (vendors.isEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'VENDORS',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Text('No vendor data available.'),
        ],
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'VENDORS',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),

        // Vendor summary table
        pw.Table(
          border: pw.TableBorder.all(),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(1),
            2: const pw.FlexColumnWidth(1.5),
          },
          children: [
            // Header
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _buildTableCell('Vendor Name', isHeader: true),
                _buildTableCell('Total Qty', isHeader: true),
                _buildTableCell('Total Revenue', isHeader: true),
              ],
            ),
            // Data rows
            ...vendors.map(
              (vendor) => pw.TableRow(
                children: [
                  _buildTableCell(vendor['name']),
                  _buildTableCell(vendor['quantity'].toString()),
                  _buildTableCell(
                    'Rs.${(vendor['revenue'] as num).toStringAsFixed(2)}',
                  ),
                ],
              ),
            ),
          ],
        ),

        pw.SizedBox(height: 20),

        // Detailed vendor breakdown
        pw.Text(
          'VENDOR DETAILS',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),

        // Individual vendor details
        ...vendors.map((vendor) => _buildVendorDetailCard(vendor)),
      ],
    );
  }

  static pw.Widget _buildVendorDetailCard(Map<String, dynamic> vendor) {
    final List<Map<String, dynamic>> items =
        vendor['items'] as List<Map<String, dynamic>>? ?? [];

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Vendor header
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                vendor['name'],
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Total: ${vendor['quantity']} items | Rs.${(vendor['revenue'] as num).toStringAsFixed(2)}',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.normal,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),

          if (items.isEmpty)
            pw.Text(
              'No items purchased',
              style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.2),
              },
              children: [
                // Sub-header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _buildTableCell('Item', isHeader: true, fontSize: 10),
                    _buildTableCell('Qty', isHeader: true, fontSize: 10),
                    _buildTableCell('Price', isHeader: true, fontSize: 10),
                    _buildTableCell('Total', isHeader: true, fontSize: 10),
                  ],
                ),
                // Item rows
                ...items.map(
                  (item) => pw.TableRow(
                    children: [
                      _buildTableCell(item['itemName'], fontSize: 10),
                      _buildTableCell(
                        item['quantity'].toString(),
                        fontSize: 10,
                      ),
                      _buildTableCell(
                        'Rs.${(item['price'] as num).toStringAsFixed(2)}',
                        fontSize: 10,
                      ),
                      _buildTableCell(
                        'Rs.${(item['revenue'] as num).toStringAsFixed(2)}',
                        fontSize: 10,
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

  static pw.Widget _buildExpensesSection(
    List<Map<String, dynamic>> expenses,
    double totalExpenses,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'EXPENSES',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        if (expenses.isEmpty)
          pw.Text('No expenses recorded.')
        else
          pw.Table(
            border: pw.TableBorder.all(),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(1.5),
            },
            children: [
              // Header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _buildTableCell('Expense Category', isHeader: true),
                  _buildTableCell('Amount', isHeader: true),
                ],
              ),
              // Data rows
              ...expenses.map(
                (expense) => pw.TableRow(
                  children: [
                    _buildTableCell(expense['name']),
                    _buildTableCell(
                      'Rs.${(expense['amount'] as num).toStringAsFixed(2)}',
                    ),
                  ],
                ),
              ),
              // Total row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _buildTableCell('TOTAL EXPENSES', isHeader: true),
                  _buildTableCell(
                    'Rs.${totalExpenses.toStringAsFixed(2)}',
                    isHeader: true,
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _buildTotalsSection(
    double totalRevenue,
    double totalExpenses,
    double additionRevenue,
    double netProfit,
    dynamic totalSales,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'FINAL TOTALS',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 2),
          ),
          child: pw.Column(
            children: [
              _buildSummaryRow('Total Sales', '${totalSales}'),
              _buildSummaryRow(
                'Total Revenue',
                'Rs.${totalRevenue.toStringAsFixed(2)}',
              ),
              _buildSummaryRow(
                'Total Expenses',
                'Rs.${totalExpenses.toStringAsFixed(2)}',
              ),
              _buildSummaryRow(
                'Additional Revenue',
                'Rs.${additionRevenue.toStringAsFixed(2)}',
              ),
              pw.Divider(thickness: 1),
              _buildSummaryRow(
                'NET PROFIT',
                'Rs.${netProfit.toStringAsFixed(2)}',
                isBold: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    double? fontSize,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize ?? 12,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }
}
