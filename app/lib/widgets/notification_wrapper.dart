import 'package:flutter/material.dart';
import '../services/notification_service.dart';

/// Widget that tracks app lifecycle for notification management.
///
/// When the app goes to background, notifications are enabled.
/// When the app returns to foreground, notifications are suppressed.
class NotificationWrapper extends StatefulWidget {
  final Widget child;

  const NotificationWrapper({super.key, required this.child});

  @override
  State<NotificationWrapper> createState() => _NotificationWrapperState();
}

class _NotificationWrapperState extends State<NotificationWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // App starts in foreground
    NotificationService.instance.appInForeground = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground
        NotificationService.instance.appInForeground = true;
        debugPrint('App resumed - notifications suppressed');
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // App is in background or transitioning
        NotificationService.instance.appInForeground = false;
        debugPrint('App backgrounded - notifications enabled');
        break;
      case AppLifecycleState.detached:
        // App is detaching, keep notifications enabled
        NotificationService.instance.appInForeground = false;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
