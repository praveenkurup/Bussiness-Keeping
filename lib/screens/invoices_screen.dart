import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'invoice_detail_screen.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => InvoicesScreenState();
}

class InvoicesScreenState extends State<InvoicesScreen> {
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _filteredInvoices = [];
  bool _isLoading = false;
  bool _hasMoreData = true;
  DocumentSnapshot? _lastDocument;
  static const int _pageSize = 10;

  // Search and filter variables
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DateTime? _selectedDate;
  String _currentBillNumber = '0';

  @override
  void initState() {
    super.initState();
    _loadInvoices();
    _loadCurrentBillNumber(); // Load current bill number from Firebase
    _initializeAndTestFirebaseStorage(); // Initialize and test Firebase Storage
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices({bool loadMore = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      Query query = FirebaseFirestore.instance
          .collection('invoices')
          .doc(user.uid)
          .collection('invoices')
          .orderBy('date', descending: true)
          .limit(_pageSize);

      if (loadMore && _lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();

      if (loadMore) {
        setState(() {
          _invoices.addAll(
            snapshot.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return {'id': doc.id, ...data};
            }).toList(),
          );
          _applyFilters();
        });
      } else {
        setState(() {
          _invoices = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {'id': doc.id, ...data};
          }).toList();
          _applyFilters();
        });
      }

      setState(() {
        _hasMoreData = snapshot.docs.length == _pageSize;
        if (snapshot.docs.isNotEmpty) {
          _lastDocument = snapshot.docs.last;
        }
      });
    } catch (e) {
      print('Error loading invoices: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading invoices: $e')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteInvoice(String invoiceId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Delete PDF from Firebase Storage
      try {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('invoices')
            .child('$invoiceId.pdf');
        await storageRef.delete();
      } catch (e) {
        print('Error deleting PDF from storage: $e');
        // Continue with database deletion even if PDF deletion fails
      }

      // Delete invoice document from Firestore
      await FirebaseFirestore.instance
          .collection('invoices')
          .doc(user.uid)
          .collection('invoices')
          .doc(invoiceId)
          .delete();

      // Remove from local lists
      setState(() {
        _invoices.removeWhere((invoice) => invoice['id'] == invoiceId);
        _filteredInvoices.removeWhere((invoice) => invoice['id'] == invoiceId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice deleted successfully')),
        );
      }
    } catch (e) {
      print('Error deleting invoice: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting invoice: $e')));
      }
    }
  }

  Future<void> _downloadInvoice(String invoiceId) async {
    print('Starting download for invoice ID: $invoiceId');
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

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

      // Get download URL from Firebase Storage with proper error handling
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('invoices')
          .child('$invoiceId.pdf');

      String downloadUrl = '';
      try {
        // Try to get download URL with retry mechanism
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            print('Attempt $attempt: Getting download URL for $invoiceId...');
            downloadUrl = await storageRef.getDownloadURL().timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                throw Exception('Timeout while getting download URL');
              },
            );
            print('Download URL obtained: $downloadUrl');
            break; // Success, exit retry loop
          } catch (e) {
            print('Attempt $attempt failed: $e');
            if (attempt < 3) {
              print('Retrying in 2 seconds...');
              await Future.delayed(const Duration(seconds: 2));
            } else {
              rethrow; // Re-throw the error if all attempts failed
            }
          }
        }
      } catch (e) {
        print('Error getting download URL: $e');
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog

          String errorMessage = 'PDF not found in storage.';
          if (e.toString().contains('channel-error')) {
            errorMessage =
                'Connection error. Please check your internet connection and try again.';
          } else if (e.toString().contains('object-not-found')) {
            errorMessage = 'PDF file not found in storage.';
          } else if (e.toString().contains('permission-denied')) {
            errorMessage =
                'Permission denied. Please check your Firebase Storage rules.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // Download the PDF using http package
      final response = await http.get(Uri.parse(downloadUrl));

      if (response.statusCode != 200) {
        throw Exception('Failed to download PDF: ${response.statusCode}');
      }

      final bytes = response.bodyBytes;

      // Save to local storage
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String fileName = 'invoice_$invoiceId.pdf';
      final String filePath = '${appDocDir.path}/$fileName';

      final File file = File(filePath);
      await file.writeAsBytes(bytes);

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF downloaded successfully to: $fileName'),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Open the PDF
      final result = await OpenFile.open(filePath);

      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open PDF: ${result.message}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Error downloading invoice: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading invoice: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _initializeAndTestFirebaseStorage() async {
    try {
      print('Initializing Firebase Storage...');

      // Wait a bit for Firebase to fully initialize
      await Future.delayed(const Duration(seconds: 2));

      // Now test the connection
      await _testFirebaseStorageConnection();
    } catch (e) {
      print('Error initializing Firebase Storage: $e');
    }
  }

  Future<void> _testFirebaseStorageConnection() async {
    try {
      print('Testing Firebase Storage connection...');
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No authenticated user found');
        return;
      }

      print('Current user UID: ${user.uid}');

      // Test basic storage access by trying to get a download URL for a test file
      final testRef = FirebaseStorage.instance
          .ref()
          .child('invoices')
          .child('test.pdf');

      try {
        print('Testing Firebase Storage access by getting download URL...');
        await testRef.getDownloadURL().timeout(const Duration(seconds: 10));
        print(
          'Firebase Storage connection successful - can access invoices folder',
        );
      } catch (e) {
        if (e.toString().contains('object-not-found')) {
          print(
            'Firebase Storage connection successful - test file not found (expected)',
          );
        } else {
          print('Firebase Storage connection test failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Firebase Storage connection issue. Downloads may not work properly.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Firebase Storage connection failed after all attempts: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Firebase Storage connection issue. This may affect PDF downloads. Error: ${e.toString()}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showInvoiceDetails(Map<String, dynamic> invoice) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InvoiceDetailScreen(invoice: invoice),
      ),
    );
  }

  void refreshData() {
    _loadInvoices();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _applyFilters();
    });
  }

  void _applyFilters() {
    _filteredInvoices = _invoices.where((invoice) {
      // Filter by search query (vendor name or invoice number)
      bool matchesSearch = _searchQuery.isEmpty;
      if (!matchesSearch) {
        final vendorName = (invoice['vendor_name'] ?? '').toLowerCase();
        final invoiceNumber = (invoice['bill_number'] ?? '').toString();
        matchesSearch =
            vendorName.contains(_searchQuery) ||
            invoiceNumber.contains(_searchQuery);
      }

      // Filter by selected date
      bool matchesDate = _selectedDate == null;
      if (_selectedDate != null && invoice['date'] != null) {
        try {
          // Parse the date string (assuming format like "15/06/2025")
          final invoiceDateParts = invoice['date'].split('/');
          if (invoiceDateParts.length == 3) {
            final invoiceDate = DateTime(
              int.parse(invoiceDateParts[2]), // year
              int.parse(invoiceDateParts[1]), // month
              int.parse(invoiceDateParts[0]), // day
            );
            matchesDate =
                invoiceDate.year == _selectedDate!.year &&
                invoiceDate.month == _selectedDate!.month &&
                invoiceDate.day == _selectedDate!.day;
          }
        } catch (e) {
          // If date parsing fails, don't filter by date
          matchesDate = true;
        }
      }

      return matchesSearch && matchesDate;
    }).toList();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _applyFilters();
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedDate = null;
      _applyFilters();
    });
  }

  String _getCurrentBillNumber() {
    return _currentBillNumber;
  }

  Future<void> _loadCurrentBillNumber() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user found for loading bill number');
        return;
      }

      print('Loading current bill number for user: ${user.uid}');
      final doc = await FirebaseFirestore.instance
          .collection('invoices')
          .doc(user.uid)
          .get();

      print('Document exists: ${doc.exists}');
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        print('Document data: $data');
        final billNumber = data['bill_number']?.toString() ?? '1';
        print('Current bill number from Firebase: $billNumber');
        if (mounted) {
          setState(() {
            _currentBillNumber = billNumber;
          });
          print('Updated _currentBillNumber to: $_currentBillNumber');
        }
      } else {
        print('Document does not exist or has no data');
      }
    } catch (e) {
      print('Error loading current bill number: $e');
    }
  }

  void _showChangeBillNumberDialog() async {
    final TextEditingController billNumberController = TextEditingController();

    // Load the current bill number before showing the dialog
    await _loadCurrentBillNumber();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Change Invoice Number',
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current bill number info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Invoice Number:',
                      style: GoogleFonts.quicksand(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_getCurrentBillNumber()}',
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6A5AE0),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Enter the new invoice number:',
                style: GoogleFonts.quicksand(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),

              // Help text
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Next invoice will be: (your input + 1). To start from 1, enter 0.',
                        style: GoogleFonts.quicksand(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              TextField(
                controller: billNumberController,
                decoration: InputDecoration(
                  hintText: 'Enter invoice number...',
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
                    borderSide: const BorderSide(color: Color(0xFF6A5AE0)),
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
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
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
                final newBillNumber = billNumberController.text.trim();
                if (newBillNumber.isNotEmpty) {
                  Navigator.of(context).pop();
                  _updateBillNumber(newBillNumber);
                }
              },
              child: Text(
                'Update',
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

  Future<void> _updateBillNumber(String newBillNumber) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

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
                  'Updating invoice number...',
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

      // Update the bill_number in the user's main document
      await FirebaseFirestore.instance
          .collection('invoices')
          .doc(user.uid)
          .update({'bill_number': newBillNumber});

      // Update local state variable
      if (mounted) {
        setState(() {
          _currentBillNumber = newBillNumber;
        });
      }

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice number updated to: $newBillNumber'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error updating bill number: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating invoice number: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Invoices',
          style: GoogleFonts.quicksand(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'change_bill_number') {
                _showChangeBillNumberDialog();
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'change_bill_number',
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Change Invoice Number',
                      style: GoogleFonts.quicksand(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(Icons.more_vert, color: Colors.black),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                // Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by vendor name or invoice number...',
                      hintStyle: GoogleFonts.quicksand(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: GoogleFonts.quicksand(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Filter Row
                Row(
                  children: [
                    // Date Filter Button
                    Expanded(
                      child: InkWell(
                        onTap: _selectDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _selectedDate != null
                                ? const Color(0xFF6A5AE0).withOpacity(0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedDate != null
                                  ? const Color(0xFF6A5AE0)
                                  : Colors.grey[300]!,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: _selectedDate != null
                                    ? const Color(0xFF6A5AE0)
                                    : Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedDate != null
                                      ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                                      : 'Select Date',
                                  style: GoogleFonts.quicksand(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: _selectedDate != null
                                        ? const Color(0xFF6A5AE0)
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                              if (_selectedDate != null)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    setState(() {
                                      _selectedDate = null;
                                      _applyFilters();
                                    });
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Clear Filters Button
                    if (_searchQuery.isNotEmpty || _selectedDate != null)
                      InkWell(
                        onTap: _clearFilters,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.clear_all,
                                size: 16,
                                color: Colors.red[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Clear',
                                style: GoogleFonts.quicksand(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.red[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Divider
          Container(height: 1, color: Colors.grey[200]),

          // Invoices List
          Expanded(
            child: _isLoading && _invoices.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _filteredInvoices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchQuery.isNotEmpty || _selectedDate != null
                              ? Icons.search_off
                              : Icons.receipt_long,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty || _selectedDate != null
                              ? 'No invoices match your search'
                              : 'No invoices found',
                          style: GoogleFonts.quicksand(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty || _selectedDate != null
                              ? 'Try adjusting your search criteria'
                              : 'Your generated invoices will appear here',
                          style: GoogleFonts.quicksand(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _loadInvoices(),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          _filteredInvoices.length +
                          (_hasMoreData &&
                                  _searchQuery.isEmpty &&
                                  _selectedDate == null
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        if (index == _filteredInvoices.length) {
                          return _hasMoreData
                              ? Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(
                                    child: ElevatedButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () => _loadInvoices(loadMore: true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF6A5AE0,
                                        ),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(Colors.white),
                                              ),
                                            )
                                          : Text(
                                              'Load More',
                                              style: GoogleFonts.quicksand(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink();
                        }

                        final invoice = _filteredInvoices[index];
                        return _buildInvoiceCard(invoice);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _getInvoiceTotal(Map<String, dynamic> invoice) {
    // First try to get the total from the invoice document
    if (invoice['total'] != null) {
      return invoice['total'].toString();
    }

    // If no total field, calculate from items
    final items = invoice['items'] ?? {};
    double totalAmount = 0.0;

    for (final item in items.values) {
      if (item is Map<String, dynamic>) {
        final quantity = (item['quantity'] ?? 0) as int;
        final rate = (item['rate'] ?? 0.0).toDouble();
        totalAmount += quantity * rate;
      }
    }

    return totalAmount.toStringAsFixed(0);
  }

  Widget _buildInvoiceCard(Map<String, dynamic> invoice) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Main content area (clickable)
            Expanded(
              child: InkWell(
                onTap: () => _showInvoiceDetails(invoice),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (invoice['bill_number'] != null) ...[
                        Text(
                          'Bill #${invoice['bill_number']}',
                          style: GoogleFonts.quicksand(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6A5AE0),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        invoice['vendor_name'] ?? 'Unknown Vendor',
                        style: GoogleFonts.quicksand(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        invoice['date'] ?? 'No Date',
                        style: GoogleFonts.quicksand(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Total amount section
            Container(
              width: 100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total',
                    style: GoogleFonts.quicksand(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${_getInvoiceTotal(invoice)}',
                    style: GoogleFonts.quicksand(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6A5AE0),
                    ),
                  ),
                ],
              ),
            ),

            // Separator line
            Container(width: 1, color: Colors.grey[200]),

            // 3-dot menu section
            Container(
              width: 60,
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'download') {
                    _downloadInvoice(invoice['id']);
                  } else if (value == 'delete') {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text(
                            'Delete Invoice',
                            style: GoogleFonts.quicksand(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          content: Text(
                            'Are you sure you want to delete this invoice? This action cannot be undone.',
                            style: GoogleFonts.quicksand(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
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
                                Navigator.of(context).pop();
                                _deleteInvoice(invoice['id']);
                              },
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
                  }
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<String>(
                    value: 'download',
                    child: Row(
                      children: [
                        const Icon(Icons.download, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Download',
                          style: GoogleFonts.quicksand(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete, size: 20, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: GoogleFonts.quicksand(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                child: const Center(
                  child: Icon(Icons.more_vert, color: Colors.grey, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
