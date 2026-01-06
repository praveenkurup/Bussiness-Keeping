import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Top-level function to handle background messages
/// This function must be top-level (not a class method) to work properly
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();

  print('FCM: Handling background message: ${message.messageId}');
  print('FCM: Data: ${message.data}');

  // Note: We can't navigate here since the app is in background
  // The navigation will be handled when the user taps the notification
  // and the app comes to foreground
}
