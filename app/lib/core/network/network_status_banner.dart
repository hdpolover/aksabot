import 'dart:async';

import 'package:flutter/material.dart';

import '../di/injection.dart';
import 'connectivity_service.dart';

/// A banner that slides in from the top when the device loses internet.
///
/// Wrap your main shell or scaffold body with this widget.
class NetworkStatusBanner extends StatefulWidget {
  final Widget child;

  const NetworkStatusBanner({super.key, required this.child});

  @override
  State<NetworkStatusBanner> createState() => _NetworkStatusBannerState();
}

class _NetworkStatusBannerState extends State<NetworkStatusBanner> {
  late final ConnectivityService _connectivity;
  StreamSubscription<bool>? _subscription;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _connectivity = sl<ConnectivityService>();
    _checkInitialState();

    _subscription = _connectivity.onConnectivityChanged.listen((isOnline) {
      if (mounted) setState(() => _isOnline = isOnline);
    });
  }

  Future<void> _checkInitialState() async {
    final online = await _connectivity.isOnline;
    if (mounted) setState(() => _isOnline = online);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _isOnline ? 0 : 36,
          child: _isOnline
              ? const SizedBox.shrink()
              : Material(
                  color: colors.error,
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: 36,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_off, size: 16, color: colors.onError),
                          const SizedBox(width: 8),
                          Text(
                            'No internet connection',
                            style: TextStyle(
                              color: colors.onError,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
