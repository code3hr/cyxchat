import 'dart:io';
import 'package:flutter/services.dart';

/// Service for managing screen security (screenshot blocking)
class ScreenSecurityService {
  static final ScreenSecurityService instance = ScreenSecurityService._();

  static const _channel = MethodChannel('com.example.cyxchat/screen_security');

  ScreenSecurityService._();

  /// Set screen security flag (Android only)
  /// When enabled, prevents screenshots and screen recording
  Future<void> setSecureFlag(bool secure) async {
    if (!Platform.isAndroid) {
      // Only supported on Android
      return;
    }

    try {
      await _channel.invokeMethod('setSecureFlag', {'secure': secure});
    } on PlatformException catch (e) {
      print('ScreenSecurityService: Failed to set secure flag: ${e.message}');
    }
  }
}
