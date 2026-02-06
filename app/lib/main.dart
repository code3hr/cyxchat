import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cyxchat/screens/home_screen.dart';
import 'package:cyxchat/screens/onboarding_screen.dart';
import 'package:cyxchat/services/identity_service.dart';
import 'package:cyxchat/services/log_service.dart';
import 'package:cyxchat/providers/identity_provider.dart';
import 'package:cyxchat/providers/settings_provider.dart';
import 'package:cyxchat/theme/app_themes.dart';

// App colors
class AppColors {
  // Primary gradient colors
  static const primary = Color(0xFF6C5CE7);
  static const primaryLight = Color(0xFF8B7CF6);
  static const primaryDark = Color(0xFF5B4BD5);

  // Accent colors
  static const accent = Color(0xFF00D9FF);
  static const accentGreen = Color(0xFF00F5A0);
  static const accentPink = Color(0xFFFF6B9D);
  static const accentOrange = Color(0xFFFF9F43);

  // Background colors
  static const bgDark = Color(0xFF0D0D1A);
  static const bgDarkSecondary = Color(0xFF1A1A2E);
  static const bgDarkTertiary = Color(0xFF252542);

  static const bgLight = Color(0xFFF8F9FE);
  static const bgLightSecondary = Color(0xFFFFFFFF);
  static const bgLightTertiary = Color(0xFFEEF0F8);

  // Text colors
  static const textDark = Color(0xFFFFFFFF);
  static const textDarkSecondary = Color(0xFFB8B8D0);
  static const textLight = Color(0xFF1A1A2E);
  static const textLightSecondary = Color(0xFF6B6B80);

  // Status colors
  static const success = Color(0xFF00F5A0);
  static const warning = Color(0xFFFFBE0B);
  static const error = Color(0xFFFF5757);
  static const info = Color(0xFF00D9FF);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging to capture all debugPrint output
  setupLogging();

  // Initialize sqflite for desktop platforms
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Set system UI style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Initialize services
  await IdentityService.instance.initialize();

  runApp(
    const ProviderScope(
      child: CyxChatApp(),
    ),
  );
}

class CyxChatApp extends ConsumerWidget {
  const CyxChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);
    final settings = ref.watch(settingsProvider);

    // Get theme data based on settings
    final themeData = AppThemes.getThemeData(
      settings.theme,
      fontFamily: settings.fontFamily.fontFamily,
    );

    // Determine if using light theme for system UI style
    final isLightTheme = settings.theme == AppTheme.light;

    return MaterialApp(
      title: 'CyxChat',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      darkTheme: themeData, // Use same theme for both to respect user choice
      themeMode: ThemeMode.system,
      builder: (context, child) {
        // Apply font scaling
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(settings.fontScale.factor),
          ),
          child: child!,
        );
      },
      home: Builder(
        builder: (context) {
          // Update system UI style based on theme
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isLightTheme ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: themeData.scaffoldBackgroundColor,
            systemNavigationBarIconBrightness: isLightTheme ? Brightness.dark : Brightness.light,
          ));

          return identityAsync.when(
            data: (identity) => identity != null
                ? const HomeScreen()
                : const OnboardingScreen(),
            loading: () => _SplashScreen(themeData: themeData),
            error: (error, stack) => _ErrorScreen(error: error.toString(), themeData: themeData),
          );
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  final ThemeData themeData;

  const _SplashScreen({required this.themeData});

  @override
  Widget build(BuildContext context) {
    final colorScheme = themeData.colorScheme;

    return Scaffold(
      backgroundColor: themeData.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo with glow effect
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 24),
            // App name
            Text(
              'CyxChat',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            // Tagline
            Text(
              'Private by Default',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.5),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 48),
            // Loading indicator
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(
                  colorScheme.primary.withOpacity(0.8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String error;
  final ThemeData themeData;

  const _ErrorScreen({required this.error, required this.themeData});

  @override
  Widget build(BuildContext context) {
    final colorScheme = themeData.colorScheme;

    return Scaffold(
      backgroundColor: themeData.scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colorScheme.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Something went wrong',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  // Restart app logic
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
