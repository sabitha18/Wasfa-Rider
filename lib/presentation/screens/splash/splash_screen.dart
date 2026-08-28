import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shown once at cold start while `AppViewModel.sessionRestoreFuture` is
/// resolving — avoids the language/login screen flashing on screen for a
/// frame before jumping straight into the app for an already-logged-in
/// driver.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // CLIENT-REQUESTED (2026-08-28): replaced the placeholder
            // "W" text with the real WASFA Riders logo. Dropped the
            // gradient-square frame that used to sit behind the "W" —
            // the real logo already has its own pink/blue coloring
            // (capsule pills + scooter), so nesting it inside another
            // gradient box would compete visually rather than look
            // clean. Asset path assumes assets/images/logo_icon.png —
            // see the accompanying note for the exact pubspec.yaml line
            // needed and where to place the file.
            Image.asset('assets/images/logo_icon.png', width: 160),
            const SizedBox(height: 12),
            Text('WASFA Rider', style: GoogleFonts.dmSans(
              color: const Color(0xFF023B60), fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2,
            )),
          ],
        ),
      ),
    );
  }
}
