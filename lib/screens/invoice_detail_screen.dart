import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class InvoiceDetailScreen extends StatelessWidget {
  final Map<String, dynamic> invoice;

  const InvoiceDetailScreen({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
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
          'Invoice Details',
          style: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invoice Information',
                    style: GoogleFonts.quicksand(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A5AE0),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (invoice['bill_number'] != null) ...[
                    _buildProminentInfoRow(
                      'Bill Number',
                      '${invoice['bill_number']}',
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildInfoRow(
                    'Vendor',
                    invoice['vendor_name'] ?? 'Unknown Vendor',
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Date', invoice['date'] ?? 'No Date'),
                  const SizedBox(height: 12),
                  _buildInfoRow('Invoice ID', invoice['id'] ?? 'Unknown ID'),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Items Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Items',
                    style: GoogleFonts.quicksand(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A5AE0),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._buildItemsList(invoice['items'] ?? {}),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Summary Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF6A5AE0).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF6A5AE0).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invoice Summary',
                    style: GoogleFonts.quicksand(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A5AE0),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSummaryRow(
                    'Total Items',
                    _getTotalItemsCount(invoice['items'] ?? {}).toString(),
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'Total Amount',
                    '₹${_getTotalAmount(invoice['items'] ?? {})}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: GoogleFonts.quicksand(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.quicksand(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProminentInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            '$label:',
            style: GoogleFonts.quicksand(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A5AE0),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.quicksand(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF6A5AE0),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.quicksand(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: GoogleFonts.quicksand(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF6A5AE0),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildItemsList(Map<String, dynamic> items) {
    if (items.isEmpty) {
      return [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Text(
            'No items found',
            style: GoogleFonts.quicksand(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }

    return items.entries.map((entry) {
      final item = entry.value as Map<String, dynamic>;
      final quantity = item['quantity'] ?? 0;
      final rate = item['rate'] ?? 0.0;
      final total = quantity * rate;

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.05),
              spreadRadius: 1,
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item Name
            Text(
              item['name'] ?? 'Unknown Item',
              style: GoogleFonts.quicksand(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 8),

            // Item Details Row
            Row(
              children: [
                Expanded(
                  child: _buildItemDetail('Quantity', quantity.toString()),
                ),
                Expanded(child: _buildItemDetail('Rate', '₹$rate')),
                Expanded(
                  child: _buildItemDetail('Total', '₹$total', isTotal: true),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildItemDetail(String label, String value, {bool isTotal = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.quicksand(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.quicksand(
            fontSize: 14,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
            color: isTotal ? const Color(0xFF6A5AE0) : Colors.black,
          ),
        ),
      ],
    );
  }

  int _getTotalItemsCount(Map<String, dynamic> items) {
    int totalCount = 0;
    for (final item in items.values) {
      if (item is Map<String, dynamic>) {
        totalCount += (item['quantity'] ?? 0) as int;
      }
    }
    return totalCount;
  }

  double _getTotalAmount(Map<String, dynamic> items) {
    double totalAmount = 0.0;
    for (final item in items.values) {
      if (item is Map<String, dynamic>) {
        final quantity = item['quantity'] ?? 0;
        final rate = (item['rate'] ?? 0.0).toDouble();
        totalAmount += quantity * rate;
      }
    }
    return totalAmount;
  }
}
