import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/sign_in_screen.dart';
import 'screens/root_shell.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'fcm_service.dart';
import 'firebase_messaging_background.dart';

// Global navigator key for FCM navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with error handling
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Test FCM functionality first
    await FCMService.testFCM();

    // Initialize FCM
    await FCMService.initialize();
    FCMService.listenForTokenRefresh();

    // Initialize notification handlers
    FCMService.initializeNotificationHandlers();
  } catch (e) {
    print('Firebase initialization error: $e');
    // For now, continue without Firebase to test the app
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Business Keeping',
      navigatorKey: navigatorKey, // Add global navigator key
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _hasRetrievedConfig = false;
  bool? _isStaff;
  bool _isCheckingStaff = false;
  bool _hasShownStaffPopup = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        // Show loading indicator while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If user is signed in, show main app and retrieve config
        if (snapshot.hasData && snapshot.data != null) {
          // Check staff status when user is authenticated
          if (!_hasRetrievedConfig) {
            _hasRetrievedConfig = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _checkStaffStatus();
            });
            FirestoreService.retrieveAndPrintUserConfig();

            // Store FCM token when user logs in
            FCMService.validateAndUpdateToken();

            // Check for pending navigation from FCM
            FCMService.checkPendingNavigation();
          }

          // Show loading while checking staff status
          if (_isCheckingStaff) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Show staff popup if user is staff and popup hasn't been shown
          if (_isStaff == true && !_hasShownStaffPopup) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showStaffAccountPopup();
            });
          }

          return RootShell(isStaff: _isStaff ?? false);
        }

        // Reset flags when user signs out
        _hasRetrievedConfig = false;
        _isStaff = null;
        _isCheckingStaff = false;
        _hasShownStaffPopup = false;

        // If user is not signed in, show sign in screen
        return const SignInScreen();
      },
    );
  }

  Future<void> _checkStaffStatus() async {
    setState(() {
      _isCheckingStaff = true;
    });

    try {
      final isStaff = await FirestoreService.isUserStaff();
      if (mounted) {
        setState(() {
          _isStaff = isStaff;
          _isCheckingStaff = false;
        });
      }
    } catch (e) {
      print('Error checking staff status: $e');
      if (mounted) {
        setState(() {
          _isStaff = false;
          _isCheckingStaff = false;
        });
      }
    }
  }

  void _showStaffAccountPopup() {
    if (!mounted) return;

    setState(() {
      _hasShownStaffPopup = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Staff Account'),
          content: const Text('You are logged in as a staff account.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}

// Removed template counter page; using SignInScreen as the home
