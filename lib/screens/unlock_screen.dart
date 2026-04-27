import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

class UnlockScreen extends StatefulWidget {
  final Future<void> Function() onUnlock;

  const UnlockScreen({super.key, required this.onUnlock});

  @override
  _UnlockScreenState createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    // Auto-trigger authentication on load
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleUnlock());
  }

  void _handleUnlock() async {
    if (_isAuthenticating) return;

    HapticFeedback.selectionClick();
    setState(() {
      _isAuthenticating = true;
    });
    await widget.onUnlock();
    if (mounted) {
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: FindUXProTheme.primaryGradient,
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // PREMIUM BRANDING ON UNLOCK
              Image.asset(
                'assets/logo.png',
                width: 180,
                height: 180,
              ),
              const SizedBox(height: 20),
              Text(
                'FindYouX',
                style: FindUXProTheme.headlineStyle.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 40),

              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: GestureDetector(
                    onTap: _isAuthenticating ? null : _handleUnlock,
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      width: 260,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Platform.isIOS ? CupertinoIcons.lock_shield_fill : Icons.fingerprint,
                            size: 64,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _isAuthenticating ? 'Autorisierung...' : 'Hardware entsperren',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_isAuthenticating) ...[
                            const SizedBox(height: 20),
                            const CupertinoActivityIndicator(color: Colors.white),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                'Zero-Data Policy aktiv.\nHardware-verschlüsselter Zugriff.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
