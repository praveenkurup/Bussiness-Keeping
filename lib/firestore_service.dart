import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Retrieves the user's config document from the 'configs' collection
  /// and prints all the data including business_name, expenses, vendors, and Items subcollection
  static Future<void> retrieveAndPrintUserConfig() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return;
      }

      print('Retrieving config for user: ${user.uid}');

      // Get the user's config document
      final docRef = _firestore.collection('configs').doc(user.uid);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        print('No config document found for user: ${user.uid}');
        return;
      }

      final data = docSnapshot.data()!;
      print('=== USER CONFIG DOCUMENT ===');
      print('Document ID: ${docSnapshot.id}');
      print('Business Name: ${data['business_name'] ?? 'Not set'}');
      print('Address: ${data['address'] ?? 'Not set'}');
      print('Email: ${data['email'] ?? 'Not set'}');
      print('Phone: ${data['phone'] ?? 'Not set'}');
      print('Expenses: ${data['expenses'] ?? 'Not set'}');
      print('Vendors: ${data['vendors'] ?? 'Not set'}');

      // Retrieve and print Items subcollection
      print('\n=== ITEMS SUBSECTION ===');
      final itemsSnapshot = await docRef.collection('items').get();

      if (itemsSnapshot.docs.isEmpty) {
        print('No items found in Items subcollection');
      } else {
        print('Found ${itemsSnapshot.docs.length} items:');
        for (var doc in itemsSnapshot.docs) {
          final itemData = doc.data();
          print('  Item ID: ${doc.id}');
          print('    Name: ${itemData['name'] ?? 'Not set'}');
          print('    Code: ${itemData['code'] ?? 'Not set'}');
          print('    Price: ${itemData['price'] ?? 'Not set'}');
          print('  ---');
        }
      }

      print('\n=== END OF CONFIG DATA ===');
    } catch (e) {
      print('Error retrieving user config: $e');
    }
  }

  /// Fetches staff details from the staffs collection using UIDs
  static Future<List<Map<String, dynamic>>> getStaffDetails(
    List<String> staffUids,
  ) async {
    try {
      if (staffUids.isEmpty) return [];

      final List<Map<String, dynamic>> staffDetails = [];

      for (String uid in staffUids) {
        final docRef = _firestore.collection('staffs').doc(uid);
        final docSnapshot = await docRef.get();

        if (docSnapshot.exists) {
          final data = docSnapshot.data()!;
          staffDetails.add({
            'uid': uid,
            'name': data['name'] ?? '',
            'email': data['email'] ?? '',
            'photoURL': data['photoURL'] ?? '',
            'access_start_time': data['access_start_time'] ?? '9:00',
            'access_end_time': data['access_end_time'] ?? '17:00',
          });
        }
      }

      return staffDetails;
    } catch (e) {
      print('Error fetching staff details: $e');
      return [];
    }
  }

  /// Alternative method that returns the config data as a Map for further processing
  static Future<Map<String, dynamic>?> getUserConfig() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return null;
      }

      final docRef = _firestore.collection('configs').doc(user.uid);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        print('No config document found for user: ${user.uid}');
        return null;
      }

      final data = docSnapshot.data()!;

      // Get Items subcollection
      final itemsSnapshot = await docRef.collection('items').get();
      final items = itemsSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      return {
        'business_name': data['business_name'],
        'address': data['address'],
        'email': data['email'],
        'phone': data['phone'],
        'expenses': data['expenses'],
        'vendors': data['vendors'],
        // New special pricing fields (optional)
        'special_pricing_vendors': data['special_pricing_vendors'],
        'special_prices': data['special_prices'],
        // Staff emails field
        'staffs_email': data['staffs_email'],
        // Staff UIDs field
        'staffs_uid': data['staffs_uid'],
        // FCM token field
        'fcm_token': data['fcm_token'],
        'fcm_token_updated_at': data['fcm_token_updated_at'],
        'items': items,
      };
    } catch (e) {
      print('Error retrieving user config: $e');
      return null;
    }
  }

  /// Refreshes user config by reloading from database
  /// This ensures the config is always up to date
  static Future<bool> refreshUserConfig() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return false;
      }

      // Force reload the config by calling getUserConfig
      final config = await getUserConfig();
      return config != null;
    } catch (e) {
      print('Error refreshing user config: $e');
      return false;
    }
  }

  /// Saves or updates the user's config document
  static Future<bool> saveUserConfig({
    required String businessName,
    required String address,
    required String email,
    required String phone,
    required List<Map<String, dynamic>> items,
    required List<String> vendors,
    required List<String> expenses,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return false;
      }

      final docRef = _firestore.collection('configs').doc(user.uid);

      // Save main config document (merge to preserve special pricing fields)
      await docRef.set({
        'business_name': businessName,
        'address': address,
        'email': email,
        'phone': phone,
        'vendors': vendors,
        'expenses': expenses,
      }, SetOptions(merge: true));

      // Delete existing items in subcollection
      final existingItems = await docRef.collection('items').get();
      for (var doc in existingItems.docs) {
        await doc.reference.delete();
      }

      // Add new items to subcollection
      for (var item in items) {
        await docRef.collection('items').add({
          'name': item['name'],
          'code': item['code'],
          'price': item['price'],
        });
      }

      print('Config saved successfully for user: ${user.uid}');
      return true;
    } catch (e) {
      print('Error saving user config: $e');
      return false;
    }
  }

  /// Creates/updates special prices for a given vendor.
  /// If [itemPricesByCode] is empty, this will remove the vendor's special prices
  /// and also remove the vendor from the special_pricing_vendors list.
  static Future<bool> upsertVendorSpecialPrices(
    String vendorName,
    Map<String, double> itemPricesByCode,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return false;
      }

      final docRef = _firestore.collection('configs').doc(user.uid);

      if (itemPricesByCode.isEmpty) {
        await docRef.update({
          'special_prices.$vendorName': FieldValue.delete(),
          'special_pricing_vendors': FieldValue.arrayRemove([vendorName]),
        });
      } else {
        await docRef.set({
          'special_prices': {vendorName: itemPricesByCode},
          'special_pricing_vendors': FieldValue.arrayUnion([vendorName]),
        }, SetOptions(merge: true));
      }

      return true;
    } catch (e) {
      print('Error upserting vendor special prices: $e');
      return false;
    }
  }

  /// Retrieves the user's total report from the 'total_report' collection
  /// Returns null if no document exists or on error
  static Future<Map<String, dynamic>?> getTotalReport() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return null;
      }

      final docRef = _firestore.collection('total_report').doc(user.uid);
      // Force server fetch to avoid showing stale cached data
      final docSnapshot = await docRef.get(
        const GetOptions(source: Source.server),
      );

      if (!docSnapshot.exists) {
        print('No total report found for user: ${user.uid}');
        return null;
      }

      final data = docSnapshot.data();
      return data;
    } catch (e) {
      print('Error retrieving total report: $e');
      return null;
    }
  }

  /// Updates the user's total report document in 'total_report' collection
  /// Overwrites the entire document with provided data
  static Future<bool> updateTotalReport(Map<String, dynamic> data) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return false;
      }

      final docRef = _firestore.collection('total_report').doc(user.uid);
      await docRef.set(data);
      return true;
    } catch (e) {
      print('Error updating total report: $e');
      return false;
    }
  }

  /// Refreshes the total report by ensuring it's up to date
  /// This method ensures the total report is consistent with the latest data
  static Future<bool> refreshTotalReport() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return false;
      }

      // Simply get the current total report to ensure it's loaded fresh from database
      final currentTotal = await getTotalReport();
      if (currentTotal != null) {
        // The total report is already up to date from our incremental updates
        // This method just ensures we have the latest data loaded
        return true;
      } else {
        // If no total report exists, create an empty one
        final Map<String, dynamic> emptyTotalReport = {
          'items_sales': <String, int>{},
          'vendor_sales': <String, int>{},
          'total_sales': 0,
          'total_revenue': 0,
          'total_expenses': 0,
          'net_profit': 0,
          'addition_revenue': 0,
          'dates_with_data': <String>[],
        };
        return await updateTotalReport(emptyTotalReport);
      }
    } catch (e) {
      print('Error refreshing total report: $e');
      return false;
    }
  }

  /// Retrieves daily report data for a specific date
  /// Path: daily_sales/<userUID>/<YYYY-MM-DD>/data
  /// Returns null if no document exists or on error
  static Future<Map<String, dynamic>?> getDailyReport(DateTime date) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return null;
      }

      // Check if user is staff and get admin UID
      String targetUid = user.uid;
      final isStaff = await isUserStaff();
      if (isStaff) {
        final adminUid = await getStaffAdminUid();
        if (adminUid != null) {
          targetUid = adminUid; // Look under admin's UID
        }
      }

      // Format date as YYYY-MM-DD
      final String dateString =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final docRef = _firestore
          .collection('daily_sales')
          .doc(targetUid)
          .collection(dateString)
          .doc('data');

      // Force server fetch to avoid showing stale cached data
      final docSnapshot = await docRef.get(
        const GetOptions(source: Source.server),
      );

      if (!docSnapshot.exists) {
        print(
          'No daily report found for user: $targetUid on date: $dateString',
        );
        return null;
      }

      final data = docSnapshot.data();
      return data;
    } catch (e) {
      print('Error retrieving daily report: $e');
      return null;
    }
  }

  /// Retrieves and aggregates daily report data for a date range
  /// Returns aggregated data or null if no data found
  static Future<Map<String, dynamic>?> getReportsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return null;
      }

      // Validate date range
      if (endDate.isBefore(startDate)) {
        print('Invalid date range: end date is before start date');
        return null;
      }

      final List<Map<String, dynamic>> reports = [];
      DateTime currentDate = startDate;

      // Iterate through each date in the range
      while (!currentDate.isAfter(endDate)) {
        final String dateString =
            '${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';

        final docRef = _firestore
            .collection('daily_sales')
            .doc(user.uid)
            .collection(dateString)
            .doc('data');

        final docSnapshot = await docRef.get();

        if (docSnapshot.exists) {
          final data = docSnapshot.data();
          if (data != null) {
            reports.add(data);
          }
        }

        // Move to next day
        currentDate = currentDate.add(const Duration(days: 1));
      }

      if (reports.isEmpty) {
        print('No reports found in the date range');
        return null;
      }

      // Aggregate the data
      return _aggregateReports(reports);
    } catch (e) {
      print('Error retrieving reports by date range: $e');
      return null;
    }
  }

  /// Updates daily report data for a specific date
  /// Path: daily_sales/<userUID>/<YYYY-MM-DD>/data
  /// Returns true if successful, false otherwise
  static Future<bool> updateDailyReport(
    DateTime date,
    Map<String, dynamic> reportData,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return false;
      }

      // Check if user is staff and get admin UID
      String targetUid = user.uid;
      String addedByUid = user.uid;

      final isStaff = await isUserStaff();
      if (isStaff) {
        final adminUid = await getStaffAdminUid();
        if (adminUid != null) {
          targetUid = adminUid; // Store under admin's UID
          addedByUid = user.uid; // But track who actually added it
        }
      }

      // Format date as YYYY-MM-DD
      final String dateString =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final docRef = _firestore
          .collection('daily_sales')
          .doc(targetUid)
          .collection(dateString)
          .doc('data');

      await docRef.set(reportData);

      // Create metadata document in the dates subcollection
      final metadataRef = _firestore
          .collection('daily_sales')
          .doc(targetUid)
          .collection(dateString)
          .doc('metadata');

      // Get current date and time in a readable format
      final now = DateTime.now();
      final addedAt = _formatDateTime(now);

      final metadataData = {
        'exists': true,
        'added_by': addedByUid,
        'added_at': addedAt,
      };

      await metadataRef.set(metadataData);

      print(
        'Daily report updated successfully for user: $targetUid on date: $dateString',
      );
      print(
        'Metadata document created for date: $dateString with added_by: $addedByUid',
      );
      return true;
    } catch (e) {
      print('Error updating daily report: $e');
      return false;
    }
  }

  /// Deletes daily report data for a specific date
  /// Path: daily_sales/<userUID>/<YYYY-MM-DD>/data
  /// Returns true if successful, false otherwise
  static Future<bool> deleteDailyReport(DateTime date) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return false;
      }

      // Format date as YYYY-MM-DD
      final String dateString =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final docRef = _firestore
          .collection('daily_sales')
          .doc(user.uid)
          .collection(dateString)
          .doc('data');

      await docRef.delete();

      // Also delete the metadata document
      final metadataRef = _firestore
          .collection('daily_sales')
          .doc(user.uid)
          .collection(dateString)
          .doc('metadata');

      await metadataRef.delete();

      print(
        'Daily report deleted successfully for user: ${user.uid} on date: $dateString',
      );
      print('Metadata document deleted for date: $dateString');
      return true;
    } catch (e) {
      print('Error deleting daily report: $e');
      return false;
    }
  }

  /// Checks if the current user is a staff member by looking for their UID in the staffs collection
  /// Returns true if user is staff, false otherwise
  static Future<bool> isUserStaff() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return false;
      }

      final docRef = _firestore.collection('staffs').doc(user.uid);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        print('User ${user.uid} is a staff member');
        return true;
      } else {
        print('User ${user.uid} is not a staff member');
        return false;
      }
    } catch (e) {
      print('Error checking staff status: $e');
      return false;
    }
  }

  /// Gets the admin UID for a staff member
  /// Returns the admin UID if found, null otherwise
  static Future<String?> getStaffAdminUid() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return null;
      }

      final docRef = _firestore.collection('staffs').doc(user.uid);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        final adminUid = data?['admin'] as String?;
        print('Staff ${user.uid} belongs to admin: $adminUid');
        return adminUid;
      } else {
        print('Staff document not found for user: ${user.uid}');
        return null;
      }
    } catch (e) {
      print('Error getting staff admin UID: $e');
      return null;
    }
  }

  /// Gets staff vendors and items from the staff document
  /// Returns a map with 'vendors' and 'items' keys
  static Future<Map<String, dynamic>?> getStaffVendorsAndItems() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return null;
      }

      final docRef = _firestore.collection('staffs').doc(user.uid);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        final vendors = data?['vendors'] as List<dynamic>? ?? [];
        final items = data?['items'] as List<dynamic>? ?? [];

        print('Staff ${user.uid} vendors: $vendors');
        print('Staff ${user.uid} items: $items');

        // Convert items from List<dynamic> to List<Map<String, dynamic>>
        final convertedItems = items
            .map((item) => item as Map<String, dynamic>)
            .toList();

        return {'vendors': vendors.cast<String>(), 'items': convertedItems};
      } else {
        print('Staff document not found for user: ${user.uid}');
        return null;
      }
    } catch (e) {
      print('Error getting staff vendors and items: $e');
      return null;
    }
  }

  /// Checks if today's report exists for the given admin UID
  /// Returns true if today's report exists, false otherwise
  static Future<bool> isTodayReportFiledForAdmin(String adminUid) async {
    try {
      final today = DateTime.now();
      final String dateString =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      final docRef = _firestore
          .collection('daily_sales')
          .doc(adminUid)
          .collection(dateString)
          .doc('metadata');

      final docSnapshot = await docRef.get();
      final exists = docSnapshot.exists;

      print(
        'Today\'s report metadata for admin $adminUid on $dateString: ${exists ? "exists" : "does not exist"}',
      );
      return exists;
    } catch (e) {
      print('Error checking today\'s report metadata for admin: $e');
      return false;
    }
  }

  /// Gets metadata for a daily report including who added it and when
  /// Returns a map with 'added_by' and 'added_at' fields, or null if not found
  static Future<Map<String, dynamic>?> getDailyReportMetadata(
    DateTime date,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return null;
      }

      // Check if user is staff and get admin UID
      String targetUid = user.uid;
      final isStaff = await isUserStaff();
      if (isStaff) {
        final adminUid = await getStaffAdminUid();
        if (adminUid != null) {
          targetUid = adminUid; // Look under admin's UID
        }
      }

      // Format date as YYYY-MM-DD
      final String dateString =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final docRef = _firestore
          .collection('daily_sales')
          .doc(targetUid)
          .collection(dateString)
          .doc('metadata');

      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        print('No metadata found for date: $dateString');
        return null;
      }

      final data = docSnapshot.data()!;
      print('Metadata found for date $dateString: $data');
      return data;
    } catch (e) {
      print('Error getting daily report metadata: $e');
      return null;
    }
  }

  /// Gets staff name from staffs collection using UID
  /// Returns the staff name if found, null otherwise
  static Future<String?> getStaffNameByUid(String uid) async {
    try {
      final docRef = _firestore.collection('staffs').doc(uid);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        final name = data?['name'] as String?;
        print('Staff name for UID $uid: $name');
        return name;
      } else {
        print('Staff document not found for UID: $uid');
        return null;
      }
    } catch (e) {
      print('Error getting staff name by UID: $e');
      return null;
    }
  }

  /// Helper method to get month name from month number
  static String _getMonthName(int month) {
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
  static String _formatDateTime(DateTime date) {
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

  /// Distributes vendors list to all staff documents
  /// Takes the list of staff UIDs from config and updates each staff document with vendors
  static Future<bool> distributeVendorsToStaff(List<String> vendors) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return false;
      }

      // Get the config to retrieve staff UIDs
      final config = await getUserConfig();
      if (config == null) {
        print('No config found for user');
        return false;
      }

      final staffUids = config['staffs_uid'] as List<dynamic>?;
      if (staffUids == null || staffUids.isEmpty) {
        print(
          'No staff UIDs found in config. Available config fields: ${config.keys}',
        );
        return true; // Not an error, just no staff to update
      }

      print('=== VENDOR DISTRIBUTION DEBUG ===');
      print('User UID: ${user.uid}');
      print('Staff UIDs found: $staffUids');
      print('Vendors to distribute: $vendors');
      print('Number of staff members: ${staffUids.length}');
      print('================================');

      // Update each staff document with the vendors list
      final batch = _firestore.batch();
      int successCount = 0;

      for (final staffUid in staffUids) {
        final staffUidString = staffUid.toString();
        final staffDocRef = _firestore.collection('staffs').doc(staffUidString);

        // Update the staff document with vendors list
        batch.set(staffDocRef, {
          'vendors': vendors,
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        successCount++;
        print('Added vendors to staff document: $staffUidString');
      }

      // Commit the batch update
      await batch.commit();

      print(
        'Successfully distributed vendors to $successCount staff documents',
      );
      return true;
    } catch (e) {
      print('Error distributing vendors to staff: $e');
      return false;
    }
  }

  /// Distributes items list to all staff documents
  /// Takes the list of staff UIDs from config and updates each staff document with items
  static Future<bool> distributeItemsToStaff(
    List<Map<String, String>> items,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return false;
      }

      // Get the config to retrieve staff UIDs
      final config = await getUserConfig();
      if (config == null) {
        print('No config found for user');
        return false;
      }

      final staffUids = config['staffs_uid'] as List<dynamic>?;
      if (staffUids == null || staffUids.isEmpty) {
        print(
          'No staff UIDs found in config. Available config fields: ${config.keys}',
        );
        return true; // Not an error, just no staff to update
      }

      print('=== ITEM DISTRIBUTION DEBUG ===');
      print('User UID: ${user.uid}');
      print('Staff UIDs found: $staffUids');
      print('Items to distribute: $items');
      print('Number of staff members: ${staffUids.length}');
      print('================================');

      // Update each staff document with the items list
      final batch = _firestore.batch();
      int successCount = 0;

      for (final staffUid in staffUids) {
        final staffUidString = staffUid.toString();
        final staffDocRef = _firestore.collection('staffs').doc(staffUidString);

        // Update the staff document with items list
        batch.set(staffDocRef, {
          'items': items,
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        successCount++;
        print('Added items to staff document: $staffUidString');
      }

      // Commit the batch update
      await batch.commit();

      print('Successfully distributed items to $successCount staff documents');
      return true;
    } catch (e) {
      print('Error distributing items to staff: $e');
      return false;
    }
  }

  /// Debug method to print all available config fields
  /// This helps identify what fields are available in the config
  static Future<void> debugPrintConfigFields() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user is currently signed in');
        return;
      }

      final docRef = _firestore.collection('configs').doc(user.uid);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        print('No config document found for user: ${user.uid}');
        return;
      }

      final data = docSnapshot.data()!;
      print('=== CONFIG FIELDS DEBUG ===');
      print('Document ID: ${docSnapshot.id}');
      print('Available fields: ${data.keys.toList()}');
      print('staffs_uid field: ${data['staffs_uid']}');
      print('staffs_email field: ${data['staffs_email']}');
      print('vendors field: ${data['vendors']}');
      print('==========================');
    } catch (e) {
      print('Error debugging config fields: $e');
    }
  }

  /// Aggregates multiple daily reports into a single report
  static Map<String, dynamic> _aggregateReports(
    List<Map<String, dynamic>> reports,
  ) {
    final Map<String, int> aggregatedItemsSales = {};
    final Map<String, Map<String, dynamic>> aggregatedVendorSales = {};
    final Map<String, double> aggregatedExpenses = {};

    int totalSales = 0;
    double totalRevenue = 0.0;
    double totalExpenses = 0.0;
    double totalAdditionRevenue = 0.0;

    for (final report in reports) {
      // Aggregate total sales
      totalSales += (report['total_sales'] as num?)?.toInt() ?? 0;
      totalRevenue += (report['total_revenue'] as num?)?.toDouble() ?? 0.0;
      totalExpenses += (report['total_expenses'] as num?)?.toDouble() ?? 0.0;
      totalAdditionRevenue +=
          (report['addition_revenue'] as num?)?.toDouble() ?? 0.0;

      // Aggregate items sales
      final Map<String, dynamic> itemsSales =
          report['items_sales'] as Map<String, dynamic>? ?? {};
      itemsSales.forEach((itemCode, quantity) {
        final int qty = (quantity is num) ? quantity.toInt() : 0;
        aggregatedItemsSales[itemCode] =
            (aggregatedItemsSales[itemCode] ?? 0) + qty;
      });

      // Aggregate vendor sales
      final Map<String, dynamic> vendorSales =
          report['vendor_sales'] as Map<String, dynamic>? ?? {};
      vendorSales.forEach((vendorName, vendorData) {
        if (vendorData is Map<String, dynamic>) {
          if (!aggregatedVendorSales.containsKey(vendorName)) {
            aggregatedVendorSales[vendorName] = {
              'sale': 0,
              'revenue': 0.0,
              'items': <String, int>{},
            };
          }

          final int vendorSale = (vendorData['sale'] as num?)?.toInt() ?? 0;
          final double vendorRevenue =
              (vendorData['revenue'] as num?)?.toDouble() ?? 0.0;

          aggregatedVendorSales[vendorName]!['sale'] =
              (aggregatedVendorSales[vendorName]!['sale'] as int) + vendorSale;
          aggregatedVendorSales[vendorName]!['revenue'] =
              (aggregatedVendorSales[vendorName]!['revenue'] as double) +
              vendorRevenue;

          // Aggregate vendor items
          final Map<String, dynamic> vendorItems =
              vendorData['items'] as Map<String, dynamic>? ?? {};
          vendorItems.forEach((itemCode, quantity) {
            final int qty = (quantity is num) ? quantity.toInt() : 0;
            final Map<String, int> items =
                aggregatedVendorSales[vendorName]!['items'] as Map<String, int>;
            items[itemCode] = (items[itemCode] ?? 0) + qty;
          });
        }
      });

      // Aggregate expenses
      final Map<String, dynamic> expenses =
          report['expenses'] as Map<String, dynamic>? ?? {};
      expenses.forEach((expenseCategory, amount) {
        final double expenseAmount = (amount is num) ? amount.toDouble() : 0.0;
        aggregatedExpenses[expenseCategory] =
            (aggregatedExpenses[expenseCategory] ?? 0.0) + expenseAmount;
      });
    }

    final double netProfit =
        totalRevenue + totalAdditionRevenue - totalExpenses;

    return {
      'total_sales': totalSales,
      'total_revenue': totalRevenue,
      'total_expenses': totalExpenses,
      'net_profit': netProfit,
      'addition_revenue': totalAdditionRevenue,
      'items_sales': aggregatedItemsSales,
      'vendor_sales': aggregatedVendorSales,
      'expenses': aggregatedExpenses,
    };
  }
}
