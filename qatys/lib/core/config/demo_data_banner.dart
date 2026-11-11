import 'package:flutter/material.dart';

/// Full-width red strip above every screen of a release build that runs on
/// mock data (see `AppConfig.showsDemoDataWarning`).
class DemoDataBanner extends StatelessWidget {
  const DemoDataBanner({super.key, required this.child});

  static const text = 'DEMO DATA — not connected to the server';

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: const Color(0xFFB00020),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
        // The strip already covers the status bar area.
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}
