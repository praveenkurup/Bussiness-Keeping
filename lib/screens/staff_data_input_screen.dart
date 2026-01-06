import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../auth_service.dart';
import '../firestore_service.dart';

class StaffDataInputScreen extends StatefulWidget {
  const StaffDataInputScreen({super.key});

  @override
  State<StaffDataInputScreen> createState() => _StaffDataInputScreenState();
}

class _StaffDataInputScreenState extends State<StaffDataInputScreen> {
  bool _isLoading = true;
  List<String> _vendors = [];
  List<Map<String, dynamic>> _items = [];
  Map<String, Map<String, TextEditingController>> _controllers = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadStaffData();
  }

  @override
  void dispose() {
    // Dispose all text controllers
    for (var vendorControllers in _controllers.values) {
      for (var controller in vendorControllers.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadStaffData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await FirestoreService.getStaffVendorsAndItems();

      if (data != null) {
        final vendors = data['vendors'] as List<String>;
        final items = data['items'] as List<Map<String, dynamic>>;

        setState(() {
          _vendors = vendors;
          _items = items;
          _initializeControllers();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to load staff data'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error loading staff data: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _initializeControllers() {
    _controllers.clear();
    for (String vendor in _vendors) {
      _controllers[vendor] = {};
      for (var item in _items) {
        final itemCode = item.keys.first;
        _controllers[vendor]![itemCode] = TextEditingController();
      }
    }
  }

  Future<void> _submitData() async {
    setState(() {
      _isSubmitting = true;
    });

    try {
      // Prepare the data in the required format
      Map<String, Map<String, int>> dataToSend = {};

      for (String vendor in _vendors) {
        dataToSend[vendor] = {};
        for (var item in _items) {
          final itemCode = item.keys.first;
          final controller = _controllers[vendor]![itemCode]!;
          final text = controller.text.trim();

          if (text.isNotEmpty) {
            final quantity = int.tryParse(text);
            if (quantity != null && quantity > 0) {
              dataToSend[vendor]![itemCode] = quantity;
            }
          }
        }

        // Remove vendor if no items were entered
        if (dataToSend[vendor]!.isEmpty) {
          dataToSend.remove(vendor);
        }
      }

      if (dataToSend.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter at least one item quantity'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() {
          _isSubmitting = false;
        });
        return;
      }

      // Get the user's ID token
      final user = AuthService.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final idToken = await user.getIdToken();

      // Send data to Firebase function
      final response = await http.post(
        Uri.parse('https://staff-add-data-cwo6krsusa-uc.a.run.app'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode(dataToSend),
      );

      // Print the server response
      print('Server response status: ${response.statusCode}');
      print('Server response body: ${response.body}');

      if (mounted) {
        // Show popup with server response
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(
                response.statusCode == 200 ? 'Success' : 'Error',
                style: GoogleFonts.quicksand(
                  fontWeight: FontWeight.w600,
                  color: response.statusCode == 200 ? Colors.green : Colors.red,
                ),
              ),
              content: Text(
                response.statusCode == 200
                    ? 'Data submitted successfully!\n\nServer response:\n${response.body}'
                    : 'Server error (${response.statusCode}):\n${response.body}',
                style: GoogleFonts.quicksand(
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(
                      context,
                    ).pop(true); // Go back to home with success indicator
                  },
                  child: Text(
                    'OK',
                    style: GoogleFonts.quicksand(
                      fontWeight: FontWeight.w600,
                      color: response.statusCode == 200
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      print('Error submitting data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _clearAllFields() {
    for (var vendorControllers in _controllers.values) {
      for (var controller in vendorControllers.values) {
        controller.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Daily Report',
          style: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _vendors.isEmpty || _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, size: 64, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text(
                    'No vendors or items found',
                    style: GoogleFonts.quicksand(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please contact your admin to set up vendors and items',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.quicksand(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    'Enter quantities for each vendor:',
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ..._vendors.map((vendor) => _buildVendorCard(vendor)),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Submit Report',
                              style: GoogleFonts.quicksand(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildVendorCard(String vendor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            vendor,
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          ..._items.map((item) => _buildItemRow(vendor, item)),
        ],
      ),
    );
  }

  Widget _buildItemRow(String vendor, Map<String, dynamic> item) {
    // The item structure is {code: name}, so we need to get the first (and only) entry
    final itemCode = item.keys.first;
    final itemName = item.values.first as String;
    final controller = _controllers[vendor]![itemCode]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '$itemName ($itemCode)',
              style: GoogleFonts.quicksand(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.quicksand(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: GoogleFonts.quicksand(
                  fontSize: 14,
                  color: Colors.grey[400],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
