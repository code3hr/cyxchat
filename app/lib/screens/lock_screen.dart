import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../providers/settings_provider.dart';
import '../services/identity_service.dart';

/// App Lock Screen
/// Shown when the app is locked and requires authentication
class LockScreen extends ConsumerStatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({
    super.key,
    required this.onUnlocked,
  });

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _auth = LocalAuthentication();
  String _pin = '';
  bool _isAuthenticating = false;
  bool _showPinInput = false;
  String? _error;
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();

      if (mounted) {
        setState(() {
          _canUseBiometrics = canCheck && isDeviceSupported;
        });

        // Auto-trigger biometric if available
        if (_canUseBiometrics) {
          _authenticateWithBiometrics();
        } else {
          setState(() => _showPinInput = true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _showPinInput = true;
          _canUseBiometrics = false;
        });
      }
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _error = null;
    });

    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to unlock CyxChat',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );

      if (authenticated) {
        widget.onUnlocked();
      } else {
        setState(() => _showPinInput = true);
      }
    } on PlatformException catch (e) {
      setState(() {
        _error = e.message;
        _showPinInput = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isAuthenticating = false);
      }
    }
  }

  void _onPinDigit(String digit) {
    if (_pin.length >= 6) return;

    setState(() {
      _pin += digit;
      _error = null;
    });

    // Auto-submit when 6 digits entered (or manually via biometric button area)
    if (_pin.length == 6) {
      _verifyPin();
    }
  }

  void _onPinBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _verifyPin() async {
    if (_pin.length < 4) {
      setState(() {
        _error = 'PIN must be at least 4 digits';
        _pin = '';
      });
      return;
    }

    // Check if PIN is set
    final hasPin = await IdentityService.instance.hasPinSet();
    if (!hasPin) {
      // No PIN set yet - this is first unlock, save this PIN
      await IdentityService.instance.savePinHash(_pin);
      widget.onUnlocked();
      return;
    }

    // Verify against stored PIN
    final isValid = await IdentityService.instance.verifyPin(_pin);
    if (isValid) {
      widget.onUnlocked();
    } else {
      setState(() {
        _error = 'Incorrect PIN';
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Lock icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.lock_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'CyxChat is locked',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _showPinInput ? 'Enter your PIN to unlock' : 'Authenticate to continue',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withAlpha(153),
              ),
            ),
            const SizedBox(height: 40),

            if (_showPinInput) ...[
              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final isFilled = index < _pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: isFilled ? colorScheme.primary : colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isFilled ? colorScheme.primary : colorScheme.outline.withAlpha(100),
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.error,
                  ),
                ),
              ],
              const Spacer(),
              // PIN keypad
              _PinKeypad(
                onDigit: _onPinDigit,
                onBackspace: _onPinBackspace,
                onBiometric: _canUseBiometrics ? _authenticateWithBiometrics : null,
              ),
            ] else ...[
              const Spacer(),
              // Biometric authentication button
              if (_isAuthenticating)
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                )
              else
                Column(
                  children: [
                    IconButton(
                      onPressed: _authenticateWithBiometrics,
                      icon: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.fingerprint_rounded,
                          size: 32,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to authenticate',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withAlpha(153),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => setState(() => _showPinInput = true),
                      child: const Text('Use PIN instead'),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// PIN keypad widget
class _PinKeypad extends StatelessWidget {
  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  const _PinKeypad({
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _KeypadButton(digit: '1', onTap: () => onDigit('1')),
              _KeypadButton(digit: '2', onTap: () => onDigit('2')),
              _KeypadButton(digit: '3', onTap: () => onDigit('3')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _KeypadButton(digit: '4', onTap: () => onDigit('4')),
              _KeypadButton(digit: '5', onTap: () => onDigit('5')),
              _KeypadButton(digit: '6', onTap: () => onDigit('6')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _KeypadButton(digit: '7', onTap: () => onDigit('7')),
              _KeypadButton(digit: '8', onTap: () => onDigit('8')),
              _KeypadButton(digit: '9', onTap: () => onDigit('9')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (onBiometric != null)
                _KeypadButton(
                  icon: Icons.fingerprint_rounded,
                  onTap: onBiometric!,
                )
              else
                const SizedBox(width: 64),
              _KeypadButton(digit: '0', onTap: () => onDigit('0')),
              _KeypadButton(
                icon: Icons.backspace_outlined,
                onTap: onBackspace,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Individual keypad button
class _KeypadButton extends StatelessWidget {
  final String? digit;
  final IconData? icon;
  final VoidCallback onTap;

  const _KeypadButton({
    this.digit,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: digit != null
                ? Text(
                    digit!,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  )
                : Icon(
                    icon,
                    size: 24,
                    color: colorScheme.onSurface,
                  ),
          ),
        ),
      ),
    );
  }
}
