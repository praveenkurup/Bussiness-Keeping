import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'screens/daily_report_detail_screen.dart';
import 'main.dart';

class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Initialize FCM and request permissions
  static Future<void> initialize() async {
    try {
      // Request permission for notifications
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      print('FCM Permission status: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('FCM: User granted permission');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        print('FCM: User granted provisional permission');
      } else {
        print('FCM: User declined or has not accepted permission');
        return;
      }

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Get the FCM token
      await _getAndStoreToken();
    } catch (e) {
      print('Error initializing FCM: $e');
    }
  }

  /// Initialize local notifications
  static Future<void> _initializeLocalNotifications() async {
    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('ic_notification');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          );

      const InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS,
          );

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      print('Local notifications initialized successfully');
    } catch (e) {
      print('Error initializing local notifications: $e');
    }
  }

  /// Handle local notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    print('Local notification tapped: ${response.payload}');

    // Parse the payload and navigate if it contains screen data
    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        final payload = response.payload!;
        final parts = payload.split('|');

        if (parts.length >= 2) {
          final screen = parts[0];
          final date = parts[1];
          _handleNotificationNavigation({'screen': screen, 'date': date});
        } else if (parts.length == 1) {
          // Assume it's just a date
          _handleNotificationNavigation({'date': parts[0]});
        }
      } catch (e) {
        print('Error handling notification tap: $e');
      }
    }
  }

  /// Get the current FCM token and store it in user config
  static Future<String?> _getAndStoreToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('FCM: No user is currently signed in');
        return null;
      }

      // Get the FCM token with error handling
      String? token;
      try {
        token = await _messaging.getToken();
      } catch (e) {
        print('FCM: Failed to get token - $e');
        return null;
      }

      if (token == null) {
        print('FCM: Token is null');
        return null;
      }

      print('FCM: Current token: $token');

      // Store the token in user config
      await _storeTokenInConfig(token);

      return token;
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  /// Store FCM token in user's config document
  static Future<bool> _storeTokenInConfig(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('FCM: No user is currently signed in');
        return false;
      }

      final docRef = _firestore.collection('configs').doc(user.uid);

      // Update the config document with the FCM token
      await docRef.set({
        'fcm_token': token,
        'fcm_token_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('FCM: Token stored successfully for user: ${user.uid}');
      return true;
    } catch (e) {
      print('Error storing FCM token: $e');
      return false;
    }
  }

  /// Get the stored FCM token from user config
  static Future<String?> getStoredToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('FCM: No user is currently signed in');
        return null;
      }

      final docRef = _firestore.collection('configs').doc(user.uid);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        print('FCM: No config document found for user: ${user.uid}');
        return null;
      }

      final data = docSnapshot.data()!;
      final storedToken = data['fcm_token'] as String?;

      print('FCM: Stored token: $storedToken');
      return storedToken;
    } catch (e) {
      print('Error getting stored FCM token: $e');
      return null;
    }
  }

  /// Validate and update FCM token if needed
  static Future<bool> validateAndUpdateToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('FCM: No user is currently signed in');
        return false;
      }

      // Get current device token with error handling
      String? currentToken;
      try {
        currentToken = await _messaging.getToken();
      } catch (e) {
        print('FCM: Failed to get current token - $e');
        return false;
      }

      if (currentToken == null) {
        print('FCM: Current token is null');
        return false;
      }

      // Get stored token from config
      final storedToken = await getStoredToken();

      // Compare tokens
      if (storedToken == null || storedToken != currentToken) {
        print('FCM: Token mismatch detected. Updating stored token...');
        print('FCM: Stored: $storedToken');
        print('FCM: Current: $currentToken');

        // Update the stored token
        final success = await _storeTokenInConfig(currentToken);
        if (success) {
          print('FCM: Token updated successfully');
          return true;
        } else {
          print('FCM: Failed to update token');
          return false;
        }
      } else {
        print('FCM: Token is valid and up to date');
        return true;
      }
    } catch (e) {
      print('Error validating FCM token: $e');
      return false;
    }
  }

  /// Force refresh the FCM token
  static Future<String?> refreshToken() async {
    try {
      // Delete the current token to force refresh
      await _messaging.deleteToken();

      // Get a new token
      final newToken = await _getAndStoreToken();

      print('FCM: Token refreshed: $newToken');
      return newToken;
    } catch (e) {
      print('Error refreshing FCM token: $e');
      return null;
    }
  }

  /// Listen for token refresh events
  static void listenForTokenRefresh() {
    _messaging.onTokenRefresh.listen((newToken) {
      print('FCM: Token refreshed automatically: $newToken');
      _storeTokenInConfig(newToken);
    });
  }

  /// Get FCM token for current user (public method)
  static Future<String?> getCurrentToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      print('Error getting current FCM token: $e');
      return null;
    }
  }

  /// Test FCM functionality
  static Future<void> testFCM() async {
    print('=== FCM TEST START ===');
    try {
      // Test 1: Check if messaging instance is available
      print('Test 1: Messaging instance available: true');

      // Test 2: Try to get token
      try {
        final token = await _messaging.getToken();
        print('Test 2: Token retrieved: ${token != null && token.isNotEmpty}');
        if (token != null && token.isNotEmpty) {
          print('Test 2: Token value: $token');
        }
      } catch (e) {
        print('Test 2: Token retrieval failed: $e');
      }

      // Test 3: Try to request permission
      try {
        final settings = await _messaging.requestPermission();
        print('Test 3: Permission status: ${settings.authorizationStatus}');
      } catch (e) {
        print('Test 3: Permission request failed: $e');
      }
    } catch (e) {
      print('FCM Test failed: $e');
    }
    print('=== FCM TEST END ===');
  }

  /// Initialize FCM notification handlers
  static void initializeNotificationHandlers() {
    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle messages when app is in background but not terminated
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    // Handle messages when app is terminated and opened via notification
    _handleInitialMessage();
  }

  /// Handle foreground messages
  static void _handleForegroundMessage(RemoteMessage message) {
    print('FCM: Received foreground message: ${message.messageId}');
    print('FCM: Data: ${message.data}');

    // Try to show local notification, fallback to simple message
    _showLocalNotification(message);

    // Also show a simple fallback message
    _showFallbackMessage(message);
  }

  /// Handle background messages (app in background but not terminated)
  static void _handleBackgroundMessage(RemoteMessage message) {
    print('FCM: Received background message: ${message.messageId}');
    print('FCM: Data: ${message.data}');

    // Navigate when user taps notification (app comes to foreground)
    _handleNotificationNavigation(message.data);
  }

  /// Handle initial message (app was terminated)
  static Future<void> _handleInitialMessage() async {
    try {
      final RemoteMessage? initialMessage = await _messaging
          .getInitialMessage();

      if (initialMessage != null) {
        print('FCM: Received initial message: ${initialMessage.messageId}');
        print('FCM: Data: ${initialMessage.data}');

        // Navigate when user taps notification (app was terminated)
        // Add a delay to ensure the app is fully initialized
        Future.delayed(const Duration(seconds: 2), () {
          _handleNotificationNavigation(initialMessage.data);
        });
      }
    } catch (e) {
      print('FCM: Error handling initial message: $e');
    }
  }

  /// Navigate to Daily Report Detail screen with the specified date
  static void _navigateToDailyReport(String dateString) {
    try {
      print('FCM: Navigating to daily report for date: $dateString');

      // Parse the date string
      DateTime? date = _parseDate(dateString);
      if (date == null) {
        print('FCM: Could not parse date: $dateString');
        return;
      }

      // Get the current navigator context
      final context = _getCurrentContext();
      if (context == null) {
        print('FCM: No navigator context available, will retry later');
        // Store the date for later navigation when context becomes available
        _pendingNavigationDate = date;
        return;
      }

      // Navigate to Daily Report Detail screen
      _performNavigation(context, date);
    } catch (e) {
      print('FCM: Error navigating to daily report: $e');
    }
  }

  /// Parse date string in various formats
  static DateTime? _parseDate(String dateString) {
    try {
      // Try parsing as ISO 8601 format first
      return DateTime.parse(dateString);
    } catch (e) {
      // Try parsing as common date formats
      try {
        // Try DD/MM/YYYY format
        final parts = dateString.split('/');
        if (parts.length == 3) {
          return DateTime(
            int.parse(parts[2]), // year
            int.parse(parts[1]), // month
            int.parse(parts[0]), // day
          );
        }
      } catch (e2) {
        // Try YYYY-MM-DD format
        try {
          final parts = dateString.split('-');
          if (parts.length == 3) {
            return DateTime(
              int.parse(parts[0]), // year
              int.parse(parts[1]), // month
              int.parse(parts[2]), // day
            );
          }
        } catch (e3) {
          print('FCM: Failed to parse date: $dateString');
          return null;
        }
      }
    }
    return null;
  }

  /// Perform the actual navigation
  static void _performNavigation(BuildContext context, DateTime date) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DailyReportDetailScreen(date: date),
      ),
    );
    print('FCM: Successfully navigated to daily report for ${date.toString()}');
  }

  /// Store pending navigation date for when context becomes available
  static DateTime? _pendingNavigationDate;

  /// Check and perform pending navigation if context is available
  static void checkPendingNavigation() {
    if (_pendingNavigationDate != null) {
      final context = _getCurrentContext();
      if (context != null) {
        print(
          'FCM: Performing pending navigation for ${_pendingNavigationDate}',
        );
        _performNavigation(context, _pendingNavigationDate!);
        _pendingNavigationDate = null;
      }
    }
  }

  /// Get the current navigator context
  static BuildContext? _getCurrentContext() {
    try {
      // Use the global navigator key to get the current context
      return navigatorKey.currentContext;
    } catch (e) {
      print('FCM: Could not get navigator context: $e');
      return null;
    }
  }

  /// Public method to navigate to daily report (can be called from anywhere)
  static void navigateToDailyReport(String dateString) {
    _navigateToDailyReport(dateString);
  }

  /// Show local notification for foreground messages
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final notification = message.notification;
      final data = message.data;

      // Check if local notifications are available
      try {
        await _localNotifications.initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'),
            iOS: DarwinInitializationSettings(),
          ),
        );
      } catch (e) {
        print('FCM: Local notifications not available: $e');
        return;
      }

      // Create notification details
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            'fcm_channel',
            'FCM Notifications',
            channelDescription: 'Notifications from Firebase Cloud Messaging',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            icon: 'ic_notification',
          );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      // Prepare payload for navigation
      String payload = '';
      if (data.containsKey('screen') && data.containsKey('date')) {
        payload = '${data['screen']}|${data['date']}';
      } else if (data.containsKey('date')) {
        payload = 'daily_report|${data['date']}';
      }

      // Show notification
      await _localNotifications.show(
        message.hashCode, // Use message hash as notification ID
        notification?.title ?? 'New Notification',
        notification?.body ?? 'You have a new notification',
        platformChannelSpecifics,
        payload: payload,
      );

      print('FCM: Local notification shown for foreground message');
    } catch (e) {
      print('FCM: Error showing local notification: $e');
      // Fallback: show a simple snackbar or just log the message
      print(
        'FCM: Fallback - Message received: ${message.notification?.title ?? 'New notification'}',
      );
    }
  }

  /// Handle notification navigation based on data
  static void _handleNotificationNavigation(Map<String, dynamic> data) {
    try {
      print('FCM: Handling notification navigation with data: $data');

      // Check if message contains screen and date data
      if (data.containsKey('screen') && data.containsKey('date')) {
        final screen = data['screen'] as String;
        final date = data['date'] as String;

        switch (screen.toLowerCase()) {
          case 'daily_report':
          case 'daily_reports':
            _navigateToDailyReport(date);
            break;
          default:
            print('FCM: Unknown screen type: $screen');
            // Default to daily report if date is available
            if (data.containsKey('date')) {
              _navigateToDailyReport(date);
            }
        }
      } else if (data.containsKey('date')) {
        // Default to daily report if only date is available
        _navigateToDailyReport(data['date'] as String);
      } else {
        print('FCM: No valid navigation data found in message');
      }
    } catch (e) {
      print('FCM: Error handling notification navigation: $e');
    }
  }

  /// Show fallback message when local notifications fail
  static void _showFallbackMessage(RemoteMessage message) {
    try {
      final context = _getCurrentContext();
      if (context != null) {
        final notification = message.notification;
        final title = notification?.title ?? 'New Notification';
        final body = notification?.body ?? 'You have a new notification';

        // Show a simple snackbar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title: $body'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                // Navigate to the appropriate screen
                _handleNotificationNavigation(message.data);
              },
            ),
          ),
        );

        print('FCM: Fallback message shown: $title');
      } else {
        print('FCM: No context available for fallback message');
      }
    } catch (e) {
      print('FCM: Error showing fallback message: $e');
    }
  }
}
