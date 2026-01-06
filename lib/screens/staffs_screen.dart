import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../auth_service.dart';
import '../firestore_service.dart';

class StaffsScreen extends StatefulWidget {
  const StaffsScreen({super.key});

  @override
  State<StaffsScreen> createState() => _StaffsScreenState();
}

class _StaffsScreenState extends State<StaffsScreen> {
  final List<Map<String, dynamic>> _staffs = [];
  final List<Map<String, dynamic>> _originalStaffs = [];
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadStaffs();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadStaffs() async {
    try {
      final config = await FirestoreService.getUserConfig();
      print('=== STAFF LOADING DEBUG ===');
      print('Config loaded: $config');

      if (config != null) {
        print('staffs_uid field: ${config['staffs_uid']}');
        print('staffs_email field: ${config['staffs_email']}');

        // First, try to load from staffs_uid (existing staff from collection)
        if (config['staffs_uid'] != null) {
          final staffUids = config['staffs_uid'] as List<dynamic>?;
          final staffEmails = config['staffs_email'] as List<dynamic>?;
          print('staffUids: $staffUids');
          print('staffEmails: $staffEmails');

          if (staffUids != null && staffUids.isNotEmpty) {
            final List<String> uidList = staffUids
                .map((uid) => uid.toString())
                .toList();
            print('Loading staff details for UIDs: $uidList');
            final staffDetails = await FirestoreService.getStaffDetails(
              uidList,
            );
            print('Staff details loaded: $staffDetails');

            // If staff details have empty emails, use emails from staffs_email field
            if (staffEmails != null && staffEmails.isNotEmpty) {
              for (
                int i = 0;
                i < staffDetails.length && i < staffEmails.length;
                i++
              ) {
                if (staffDetails[i]['email'] == null ||
                    staffDetails[i]['email'].toString().isEmpty) {
                  staffDetails[i]['email'] = staffEmails[i].toString();
                }
                // Mark as existing staff (loaded from collection)
                staffDetails[i]['isExisting'] = true;
              }
            }

            print('Staff details after email fix: $staffDetails');

            setState(() {
              _staffs.clear();
              _staffs.addAll(staffDetails);
              _originalStaffs.clear();
              _originalStaffs.addAll(
                staffDetails.map((staff) => Map<String, dynamic>.from(staff)),
              );
            });
          }
        }

        // If no staffs_uid or empty, try to load from staffs_email (simple email list)
        if (_staffs.isEmpty && config['staffs_email'] != null) {
          final staffEmails = config['staffs_email'] as List<dynamic>?;
          print('staffEmails: $staffEmails');
          if (staffEmails != null && staffEmails.isNotEmpty) {
            final List<Map<String, dynamic>> emailStaffs = staffEmails
                .map(
                  (email) => {
                    'uid': '',
                    'name': '',
                    'email': email.toString(),
                    'photoURL': '',
                    'access_start_time': '9:00',
                    'access_end_time': '17:00',
                    'isExisting':
                        false, // Mark as new staff (from simple email list)
                  },
                )
                .toList();
            print('Created email staffs: $emailStaffs');

            setState(() {
              _staffs.clear();
              _staffs.addAll(emailStaffs);
              _originalStaffs.clear();
              _originalStaffs.addAll(
                emailStaffs.map((staff) => Map<String, dynamic>.from(staff)),
              );
            });
          }
        }

        print('Final _staffs list: $_staffs');
      } else {
        print('Config is null');
      }
      print('========================');
    } catch (e) {
      print('Error loading staffs: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addEmail() {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnackBar('Please enter an email address', Colors.red);
      return;
    }

    if (!_isValidEmail(email)) {
      _showSnackBar('Please enter a valid email address', Colors.red);
      return;
    }

    if (_staffs.any((staff) => staff['email'] == email)) {
      _showSnackBar('This email is already in the list', Colors.orange);
      return;
    }

    setState(() {
      _staffs.add({
        'uid': '', // Will be set by the API
        'name': '',
        'email': email,
        'photoURL': '',
        'access_start_time': '9:00',
        'access_end_time': '17:00',
        'isExisting': false, // Mark as newly added staff
      });
      _emailController.clear();
      _checkForChanges();
    });
  }

  void _removeStaff(int index) {
    setState(() {
      _staffs.removeAt(index);
      _checkForChanges();
    });
  }

  void _updateAccessTime(int index, String field, String time) {
    setState(() {
      _staffs[index][field] = time;
      _checkForChanges();
    });
  }

  void _checkForChanges() {
    final hasChanges = !_listsEqual(_staffs, _originalStaffs);
    setState(() {
      _hasChanges = hasChanges;
    });
  }

  bool _listsEqual(
    List<Map<String, dynamic>> list1,
    List<Map<String, dynamic>> list2,
  ) {
    if (list1.length != list2.length) return false;

    for (int i = 0; i < list1.length; i++) {
      final staff1 = list1[i];
      final staff2 = list2[i];

      if (staff1['email'] != staff2['email'] ||
          staff1['access_start_time'] != staff2['access_start_time'] ||
          staff1['access_end_time'] != staff2['access_end_time']) {
        return false;
      }
    }
    return true;
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.quicksand(
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: color,
      ),
    );
  }

  Future<void> _updateStaffs() async {
    if (!_hasChanges) {
      _showSnackBar('No changes to update', Colors.orange);
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      // Get the current user's ID token
      final user = AuthService.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated', Colors.red);
        return;
      }

      final idToken = await user.getIdToken();

      // Prepare request data in the new format
      final Map<String, dynamic> staffsData = {};
      for (var staff in _staffs) {
        staffsData[staff['email']] = {
          'name': staff['name'] ?? '',
          'photoURL': staff['photoURL'] ?? '',
          'access_start_time': staff['access_start_time'],
          'access_end_time': staff['access_end_time'],
        };
      }

      final Map<String, dynamic> requestData = {'staffs': staffsData};

      // Make HTTP POST request to the update staffs endpoint
      final response = await http.post(
        Uri.parse('https://update-staffs-list-cwo6krsusa-uc.a.run.app'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(requestData),
      );

      // Print entire API response to console
      print('=== API RESPONSE DEBUG ===');
      print('Status Code: ${response.statusCode}');
      print('Response Headers: ${response.headers}');
      print('Response Body: ${response.body}');
      print('Response Body Length: ${response.body.length}');
      print('========================');

      if (response.statusCode == 200) {
        // After successful staff update, distribute vendors and items to staff
        await _distributeVendorsAndItemsToStaff();

        // Show success popup with the response and redirect after user closes it
        _showResponseDialog(
          'Success',
          '${response.body}\n\nVendors and items have been distributed to all staff members.',
          redirectToHome: true,
        );
      } else {
        _showResponseDialog(
          'Error',
          'Server returned status: ${response.statusCode}\n\nResponse: ${response.body}',
        );
      }
    } catch (e) {
      _showResponseDialog('Error', 'Failed to update staff list: $e');
    } finally {
      setState(() {
        _isUpdating = false;
      });
    }
  }

  Future<void> _distributeVendorsAndItemsToStaff() async {
    try {
      // Get the current admin's config to retrieve vendors and items
      final config = await FirestoreService.getUserConfig();
      if (config == null) {
        print('No config found for admin user');
        return;
      }

      // Get vendors from config
      final vendors = config['vendors'] as List<dynamic>?;
      if (vendors != null && vendors.isNotEmpty) {
        final vendorList = vendors.cast<String>();
        print('Distributing vendors to staff: $vendorList');

        // Distribute vendors to staff documents
        final vendorDistributionSuccess =
            await FirestoreService.distributeVendorsToStaff(vendorList);

        if (vendorDistributionSuccess) {
          print('Successfully distributed vendors to staff');
        } else {
          print('Failed to distribute vendors to staff');
        }
      }

      // Get items from config
      final items = config['items'] as List<dynamic>?;
      if (items != null && items.isNotEmpty) {
        // Prepare items data (code mapped to name)
        final itemMaps = <Map<String, String>>[];
        for (var item in items) {
          if (item is Map<String, dynamic>) {
            // Handle the item structure from config
            final code = item['code']?.toString();
            final name = item['name']?.toString();
            if (code != null &&
                name != null &&
                code.isNotEmpty &&
                name.isNotEmpty) {
              itemMaps.add({code: name});
            }
          }
        }

        if (itemMaps.isNotEmpty) {
          print('Distributing items to staff: $itemMaps');

          // Distribute items to staff documents
          final itemDistributionSuccess =
              await FirestoreService.distributeItemsToStaff(itemMaps);

          if (itemDistributionSuccess) {
            print('Successfully distributed items to staff');
          } else {
            print('Failed to distribute items to staff');
          }
        }
      }
    } catch (e) {
      print('Error distributing vendors and items to staff: $e');
    }
  }

  void _showResponseDialog(
    String title,
    String message, {
    bool redirectToHome = false,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            title,
            style: GoogleFonts.quicksand(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SingleChildScrollView(
            child: Text(
              message,
              style: GoogleFonts.quicksand(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (redirectToHome && mounted) {
                  // Redirect to home after user closes the popup
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
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

  Future<void> _selectTime(int index, String field) async {
    final currentTime = _staffs[index][field] as String;
    final timeParts = currentTime.split(':');
    final initialTime = TimeOfDay(
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
    );

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      final formattedTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      _updateAccessTime(index, field, formattedTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

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
          'Staff Management',
          style: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: size.height * 0.025),

                    // Add email section
                    Text(
                      'Add Staff Email:-',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFFE9E9E9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              hintText: 'Enter staff email address',
                              hintStyle: GoogleFonts.quicksand(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                            style: GoogleFonts.quicksand(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                            onSubmitted: (_) => _addEmail(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _addEmail,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6A5AE0),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Add',
                            style: GoogleFonts.quicksand(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Staff list section
                    Text(
                      'Staff List:-',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_staffs.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFE0E0E0),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'No staff added yet. Add some emails above.',
                          style: GoogleFonts.quicksand(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ...List.generate(_staffs.length, (index) {
                        final staff = _staffs[index];
                        final isExisting = staff['isExisting'] == true;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isExisting
                                ? const Color(
                                    0xFFE8F5E8,
                                  ) // Light green for existing staff
                                : const Color(
                                    0xFFF0F8FF,
                                  ), // Light blue for new staff
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isExisting
                                  ? const Color(
                                      0xFF4CAF50,
                                    ) // Green border for existing
                                  : const Color(
                                      0xFF2196F3,
                                    ), // Blue border for new
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Staff info header with status indicator
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Top row: Status indicator, Name, and Remove button
                                  Row(
                                    children: [
                                      // Status indicator
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: isExisting
                                              ? const Color(0xFF4CAF50)
                                              : const Color(0xFF2196F3),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Staff name (main identifier)
                                      Expanded(
                                        child: Text(
                                          staff['name']
                                                      ?.toString()
                                                      .isNotEmpty ==
                                                  true
                                              ? staff['name']
                                              : 'Staff Member',
                                          style: GoogleFonts.quicksand(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                      // Status badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isExisting
                                              ? const Color(
                                                  0xFF4CAF50,
                                                ).withOpacity(0.1)
                                              : const Color(
                                                  0xFF2196F3,
                                                ).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          isExisting ? 'Existing' : 'New',
                                          style: GoogleFonts.quicksand(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isExisting
                                                ? const Color(0xFF4CAF50)
                                                : const Color(0xFF2196F3),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        onPressed: () => _removeStaff(index),
                                        icon: const Icon(
                                          Icons.remove_circle,
                                          color: Colors.red,
                                        ),
                                        tooltip: 'Remove staff',
                                      ),
                                    ],
                                  ),
                                  // Email row (separate line for better spacing)
                                  if (staff['email']?.toString().isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const SizedBox(
                                          width: 20,
                                        ), // Align with name
                                        Expanded(
                                          child: Text(
                                            staff['email'],
                                            style: GoogleFonts.quicksand(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Access times
                              Text(
                                'Access Times:',
                                style: GoogleFonts.quicksand(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 8),

                              Row(
                                children: [
                                  // Start time
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Start Time:',
                                          style: GoogleFonts.quicksand(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        InkWell(
                                          onTap: () => _selectTime(
                                            index,
                                            'access_start_time',
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(0xFFE0E0E0),
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  staff['access_start_time'],
                                                  style: GoogleFonts.quicksand(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.access_time,
                                                  size: 16,
                                                  color: Colors.grey[600],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // End time
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'End Time:',
                                          style: GoogleFonts.quicksand(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        InkWell(
                                          onTap: () => _selectTime(
                                            index,
                                            'access_end_time',
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(0xFFE0E0E0),
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  staff['access_end_time'],
                                                  style: GoogleFonts.quicksand(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.access_time,
                                                  size: 16,
                                                  color: Colors.grey[600],
                                                ),
                                              ],
                                            ),
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
                      }),

                    const SizedBox(height: 32),

                    // Update button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _hasChanges && !_isUpdating
                            ? _updateStaffs
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _hasChanges
                              ? const Color(0xFF6A5AE0)
                              : const Color(0xFFE0E0E0),
                          foregroundColor: _hasChanges
                              ? Colors.white
                              : Colors.grey[600],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        icon: _isUpdating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.update, size: 20),
                        label: Text(
                          _isUpdating
                              ? 'Updating...'
                              : _hasChanges
                              ? 'Update Staff List'
                              : 'No Changes to Update',
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
            ),
    );
  }
}
