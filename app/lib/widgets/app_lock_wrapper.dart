import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../screens/lock_screen.dart';

/// Manages app lock state
class AppLockManager extends ChangeNotifier {
  bool _isLocked = true;
  DateTime? _lastActiveTime;

  bool get isLocked => _isLocked;

  void lock() {
    _isLocked = true;
    notifyListeners();
  }

  void unlock() {
    _isLocked = false;
    _lastActiveTime = DateTime.now();
    notifyListeners();
  }

  void updateActivity() {
    _lastActiveTime = DateTime.now();
  }

  bool shouldLock(int timeoutSeconds) {
    if (_lastActiveTime == null) return true;
    if (timeoutSeconds == 0) return true; // Immediate lock
    final elapsed = DateTime.now().difference(_lastActiveTime!);
    return elapsed.inSeconds >= timeoutSeconds;
  }
}

/// Provider for app lock manager
final appLockManagerProvider = ChangeNotifierProvider<AppLockManager>((ref) {
  return AppLockManager();
});

/// Wrapper widget that shows lock screen when app is locked
class AppLockWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const AppLockWrapper({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends ConsumerState<AppLockWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = ref.read(settingsProvider);
    final lockManager = ref.read(appLockManagerProvider);

    if (!settings.appLockEnabled) return;

    if (state == AppLifecycleState.resumed) {
      // Check if we should lock based on timeout
      if (lockManager.shouldLock(settings.appLockTimeout)) {
        lockManager.lock();
      }
    } else if (state == AppLifecycleState.paused) {
      // Mark last active time when going to background
      lockManager.updateActivity();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final lockManager = ref.watch(appLockManagerProvider);

    // If app lock is disabled, just show the child
    if (!settings.appLockEnabled) {
      return widget.child;
    }

    // Show lock screen if locked
    if (lockManager.isLocked) {
      return LockScreen(
        onUnlocked: () {
          ref.read(appLockManagerProvider).unlock();
        },
      );
    }

    return widget.child;
  }
}
