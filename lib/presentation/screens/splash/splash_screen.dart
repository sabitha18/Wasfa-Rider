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
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFFE7609F), Color(0xFF1E9CD7)],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: const Color(0xFFE7609F).withOpacity(0.35), blurRadius: 30, offset: const Offset(0, 12))],
              ),
              child: Center(
                child: Text('W', style: GoogleFonts.dmSans(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 18),
            Text('WASFA Rider', style: GoogleFonts.dmSans(
              color: const Color(0xFF023B60), fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2,
            )),
          ],
        ),
      ),
    );
  }
}
