import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:google_fonts/google_fonts.dart';

class InvoiceService {
  static const String _baseUrl =
      'https://generate-invoice-cwo6krsusa-uc.a.run.app';

  /// Generates an invoice for a vendor and downloads/opens the PDF
  static Future<void> generateInvoice({
    required String idToken,
    required String vendorName,
    required String date,
    required Map<String, dynamic> items,
    required int total,
    required BuildContext context,
  }) async {
    // Check if context is still mounted before proceeding
    if (!context.mounted) return;

    // Show confirmation dialog first
    final Map<String, dynamic>? dialogResult = await _showConfirmationDialog(
      context,
      vendorName,
    );
    if (dialogResult == null) {
      return; // User cancelled
    }

    final double? pendingAmount = dialogResult['pending_amount'];

    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Text(
                  'Generating invoice...',
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        },
      );

      // Prepare request data (without uid)
      final Map<String, dynamic> requestData = {
        'vendor_name': vendorName,
        'date': date,
        'items': items,
        'total': total,
      };

      // Add pending amount if provided
      if (pendingAmount != null && pendingAmount > 0) {
        requestData['pending_amount'] = pendingAmount;
      }

      // Debug: Print request data for verification
      print('Invoice request data:');
      print('Vendor: $vendorName');
      print('Date: $date');
      print('Total: $total');
      print('Pending Amount: $pendingAmount');
      print('Items: $items');
      print('JSON payload: ${jsonEncode(requestData)}');

      // Make HTTP POST request with Bearer token
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(requestData),
      );

      // Check if context is still mounted before closing dialog
      if (!context.mounted) return;

      // Close loading dialog
      Navigator.of(context).pop();

      if (response.statusCode == 200) {
        // Print successful response to console for debugging
        print('Invoice generation successful:');
        print('Response Body: ${response.body}');

        // The server returns the PDF URL directly as a string, not as JSON
        final String responseBody = response.body.trim();

        if (responseBody.isNotEmpty && responseBody.startsWith('http')) {
          print('PDF URL received: $responseBody');
          // Download and open the PDF
          await _downloadAndOpenPdf(responseBody, context);
        } else {
          print('Invalid PDF URL in response: $responseBody');
          if (context.mounted) {
            _showErrorDialog(context, 'Invalid PDF URL received from server');
          }
        }
      } else {
        // Print server response to console for debugging
        print('Server error response:');
        print('Status Code: ${response.statusCode}');
        print('Response Body: ${response.body}');
        print('Response Headers: ${response.headers}');

        if (context.mounted) {
          _showErrorDialog(
            context,
            'Failed to generate invoice. Server returned status: ${response.statusCode}',
          );
        }
      }
    } catch (e) {
      // Check if context is still mounted before closing dialog
      if (context.mounted) {
        // Close loading dialog if it's still open
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showErrorDialog(context, 'Error generating invoice: $e');
      }
    }
  }

  /// Downloads PDF from URL and opens it
  static Future<void> _downloadAndOpenPdf(
    String pdfUrl,
    BuildContext context,
  ) async {
    // Check if context is still mounted before proceeding
    if (!context.mounted) return;

    try {
      // Show downloading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Text(
                  'Downloading PDF...',
                  style: GoogleFonts.quicksand(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        },
      );

      // Download the PDF
      final response = await http.get(Uri.parse(pdfUrl));

      if (response.statusCode == 200) {
        // Get the documents directory
        final Directory appDocDir = await getApplicationDocumentsDirectory();
        final String fileName =
            'invoice_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final String filePath = '${appDocDir.path}/$fileName';

        // Save the PDF file
        final File file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        print('PDF downloaded successfully to: $filePath');

        // Check if context is still mounted before closing dialog
        if (!context.mounted) return;

        // Close downloading dialog
        Navigator.of(context).pop();

        // Open the PDF file
        final result = await OpenFile.open(filePath);

        print('PDF open result: ${result.type} - ${result.message}');

        if (result.type != ResultType.done && context.mounted) {
          _showErrorDialog(context, 'Failed to open PDF: ${result.message}');
        }
      } else {
        // Print PDF download error to console for debugging
        print('PDF download error:');
        print('Status Code: ${response.statusCode}');
        print('Response Body: ${response.body}');
        print('Response Headers: ${response.headers}');

        if (context.mounted) {
          Navigator.of(context).pop();
          _showErrorDialog(
            context,
            'Failed to download PDF. Status: ${response.statusCode}',
          );
        }
      }
    } catch (e) {
      // Check if context is still mounted before closing dialog
      if (context.mounted) {
        // Close downloading dialog if it's still open
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showErrorDialog(context, 'Error downloading PDF: $e');
      }
    }
  }

  /// Shows confirmation dialog before generating invoice
  static Future<Map<String, dynamic>?> _showConfirmationDialog(
    BuildContext context,
    String vendorName,
  ) {
    final TextEditingController pendingAmountController =
        TextEditingController();

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Generate Invoice',
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to generate an invoice for $vendorName?',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pending Amount (Optional):',
                style: GoogleFonts.quicksand(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pendingAmountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter pending amount (e.g., 150.50)',
                  hintStyle: GoogleFonts.quicksand(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF6A5AE0),
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                style: GoogleFonts.quicksand(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
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
              onPressed: () {
                final String pendingAmountText = pendingAmountController.text
                    .trim();
                double? pendingAmount;

                if (pendingAmountText.isNotEmpty) {
                  try {
                    pendingAmount = double.parse(pendingAmountText);
                    if (pendingAmount < 0) {
                      pendingAmount = null; // Invalid negative amount
                    }
                  } catch (e) {
                    pendingAmount = null; // Invalid format
                  }
                }

                Navigator.of(
                  context,
                ).pop({'confirmed': true, 'pending_amount': pendingAmount});
              },
              child: Text(
                'Generate',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6A5AE0),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Shows error dialog
  static void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Error',
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            message,
            style: GoogleFonts.quicksand(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'OK',
                style: GoogleFonts.quicksand(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6A5AE0),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
