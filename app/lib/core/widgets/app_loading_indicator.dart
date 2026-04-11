import 'package:flutter/material.dart';

/// Centered loading spinner — use as the body of a loading state.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// Small inline spinner for buttons and compact spaces.
class AppButtonSpinner extends StatelessWidget {
  final double size;
  final double strokeWidth;

  const AppButtonSpinner({
    super.key,
    this.size = 20,
    this.strokeWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: strokeWidth),
    );
  }
}
