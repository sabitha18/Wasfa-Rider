import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/core/constants/app_strings.dart';
import 'package:wasfa_rider/presentation/viewmodels/app_viewmodel.dart';
import 'package:wasfa_rider/data/models/models.dart';

// ── W LOGO ─────────────────────────────────────────────────────
class _WLogo extends StatelessWidget {
  const _WLogo({this.size = 56});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFFE7609F), Color(0xFF1E9CD7)],
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: const Color(0xFFE7609F).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: Center(child: Text('W', style: GoogleFonts.dmSans(color: Colors.white, fontSize: size * 0.46, fontWeight: FontWeight.w800))),
  );
}

// ── LANGUAGE SCREEN ────────────────────────────────────────────
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key, required this.onSelected});
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF023B60),Color(0xFF023B60), Color(0xFF04527F)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 60, 22, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _WLogo(size: 64),
              const SizedBox(height: 20),
              Text('Choose your language',
                  style: GoogleFonts.dmSans(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 4),
              Text('اختر لغتك',
                  style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 24, fontWeight: FontWeight.w800)),
              const Spacer(),
              _LangRow(
                code: 'EN', title: 'English', subtitle: 'Continue in English',
                onTap: () { context.read<AppViewModel>().setLanguage('en'); onSelected(); },
              ),
              const SizedBox(height: 12),
              _LangRow(
                code: 'AR', title: 'العربية', subtitle: 'المتابعة بالعربية',
                onTap: () { context.read<AppViewModel>().setLanguage('ar'); onSelected(); },
                rtl: true,
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LangRow extends StatelessWidget {
  const _LangRow({required this.code, required this.title, required this.subtitle, required this.onTap, this.rtl = false});
  final String code, title, subtitle;
  final VoidCallback onTap;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
        ),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(code, style: GoogleFonts.dmSans(color: WTheme.navy, fontSize: 14, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.dmSans(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              Text(subtitle, style: GoogleFonts.dmSans(color: Colors.white60, fontSize: 12)),
            ])),
            Text('›', style: const TextStyle(color: Colors.white60, fontSize: 22)),
          ]),
        ),
      ),
    );
  }
}

// ── LOGIN SCREEN ───────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSubmit});
  final void Function(String phone) onSubmit; // may kick off an async OTP request

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _ctrl = TextEditingController();
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() => _valid = _ctrl.text.replaceAll(RegExp(r'\D'), '').length >= 7));
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppViewModel>().language;
    final s = AppStrings(lang);
    final isAr = lang == 'ar';
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [const Color(0xFF023B60), const Color(0xFF04527F), WTheme.rose.withOpacity(0.3)],
            stops: const [0.0, 0.66, 1.0],
          ),
        ),
        child: Stack(children: [
          // radial aqua glow top-right
          Positioned(
            top: -60, right: -60,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFF58C4E4).withOpacity(0.20),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          SafeArea(
            child: Directionality(
              textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 60, 22, 30),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _WLogo(size: 56),
                  const SizedBox(height: 22),
                  Text(s.get('welcome'),
                      style: GoogleFonts.dmSans(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  Text(s.get('enterPhone'),
                      style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                  const Spacer(),
                  // Phone input
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                    ),
                    child: Row(children: [
                      Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('🇰🇼 +965',
                            style: GoogleFonts.dmSans(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s]'))],
                          style: GoogleFonts.dmSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                          decoration: InputDecoration(
                            hintText: '9XXX XXXX',
                            hintStyle: GoogleFonts.dmSans(color: Colors.white38, fontSize: 18),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  if (context.watch<AppViewModel>().error != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        context.watch<AppViewModel>().error!,
                        style: GoogleFonts.dmSans(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: _valid ? WTheme.rose : Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: _valid ? [BoxShadow(color: WTheme.rose.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8))] : [],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _valid ? () => widget.onSubmit('+965 ${_ctrl.text.trim()}') : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Center(child: Text(s.get('sendCode'),
                                style: GoogleFonts.dmSans(color: Colors.white.withOpacity(_valid ? 1 : 0.7), fontSize: 16, fontWeight: FontWeight.w800))),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(child: Text('By continuing you agree to WASFA terms of service.',
                      style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.6), fontSize: 11),
                      textAlign: TextAlign.center)),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── OTP SCREEN ─────────────────────────────────────────────────
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phone, required this.onVerified});
  final String phone;
  final ValueChanged<String> onVerified; // now passes the entered 6-digit code

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _ctrls = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  bool _complete = false;

  void _checkComplete() {
    final complete = _ctrls.every((c) => c.text.isNotEmpty);
    if (complete != _complete) setState(() => _complete = complete);
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppViewModel>().language;
    final s = AppStrings(lang);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF023B60), Color(0xFF04527F)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 60, 22, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: () {},
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Center(child: Text('‹', style: TextStyle(color: Colors.white, fontSize: 20))),
                ),
              ),
              const SizedBox(height: 22),
              Text(s.get('enterCode'),
                  style: GoogleFonts.dmSans(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              RichText(text: TextSpan(
                style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.8), fontSize: 13),
                children: [
                  TextSpan(text: '${s.get('sentTo')} '),
                  TextSpan(
                    text: widget.phone,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              )),
              const SizedBox(height: 32),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) {
                    final filled = _ctrls[i].text.isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: SizedBox(
                        width: 44, height: 56,
                        child: TextField(
                          controller: _ctrls[i], focusNode: _nodes[i],
                          maxLength: 1, keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: GoogleFonts.dmMono(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                          decoration: InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: filled ? Colors.white.withOpacity(0.20) : Colors.white.withOpacity(0.08),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: filled ? WTheme.aqua : Colors.white.withOpacity(0.2), width: 2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: filled ? WTheme.aqua : Colors.white.withOpacity(0.2), width: 2),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: filled ? WTheme.aqua : Colors.white.withOpacity(0.4), width: 2),
                            ),
                          ),
                          onChanged: (v) {
                            if (v.isNotEmpty && i < 5) _nodes[i + 1].requestFocus();
                            if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
                            _checkComplete();
                            if (_complete) {
                              Future.delayed(const Duration(milliseconds: 400),
                                  () => widget.onVerified(_ctrls.map((c) => c.text).join()));
                            }
                          },
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 22),
              if (context.watch<AppViewModel>().devOtpHint != null)
                Center(
                  child: RichText(text: TextSpan(
                    style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.7), fontSize: 12),
                    children: [
                      const TextSpan(text: 'Dev OTP (from backend): '),
                      TextSpan(
                        text: context.watch<AppViewModel>().devOtpHint!,
                        style: GoogleFonts.dmSans(color: WTheme.aqua, fontWeight: FontWeight.w800),
                      ),
                    ],
                  )),
                ),
              if (context.watch<AppViewModel>().error != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    context.watch<AppViewModel>().error!,
                    style: GoogleFonts.dmSans(color: Colors.white, fontSize: 12),
                  ),
                ),
              const Spacer(),
              Center(child: TextButton(
                onPressed: () => context.read<AppViewModel>().requestOtp(widget.phone),
                child: Text(s.get('resend'), style: GoogleFonts.dmSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              )),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: _complete ? WTheme.aqua : Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _complete ? [BoxShadow(color: WTheme.aqua.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8))] : [],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _complete ? () => widget.onVerified(_ctrls.map((c) => c.text).join()) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: Text(s.get('verify'),
                            style: GoogleFonts.dmSans(
                                color: _complete ? WTheme.navy : Colors.white.withOpacity(0.7),
                                fontWeight: FontWeight.w800, fontSize: 16))),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── VEHICLE SETUP ──────────────────────────────────────────────
class VehicleSetupScreen extends StatefulWidget {
  const VehicleSetupScreen({super.key, required this.phone, required this.onContinue});
  final String phone;
  final VoidCallback onContinue;

  @override
  State<VehicleSetupScreen> createState() => _VehicleSetupScreenState();
}

class _VehicleSetupScreenState extends State<VehicleSetupScreen> {
  VehicleType _selected = VehicleType.motorbike;
  final _plateCtrl = TextEditingController();
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _plateCtrl.addListener(() => setState(() => _valid = _plateCtrl.text.trim().length >= 3));
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<AppViewModel>().language;
    final s = AppStrings(lang);
    return Scaffold(
      backgroundColor: WTheme.blush,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: WTheme.navy, borderRadius: BorderRadius.circular(14)),
                  child: const Center(child: Text('🛵', style: TextStyle(fontSize: 28))),
                ),
                const SizedBox(height: 22),
                Text(s.get('setupVehicle'),
                    style: GoogleFonts.dmSans(color: WTheme.navy, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text("Choose what you'll ride today and add your plate number.",
                    style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 13)),
                const SizedBox(height: 22),
                Text(s.get('vehicleType').toUpperCase(),
                    style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Row(children: [
                  _VehicleBtn(emoji: '🏍', label: s.get('motorbike'), type: VehicleType.motorbike, selected: _selected, onTap: (t) => setState(() => _selected = t)),
                  const SizedBox(width: 8),
                  _VehicleBtn(emoji: '🛵', label: s.get('scooter'),   type: VehicleType.scooter,   selected: _selected, onTap: (t) => setState(() => _selected = t)),
                  const SizedBox(width: 8),
                  _VehicleBtn(emoji: '🚗', label: s.get('car'),       type: VehicleType.car,       selected: _selected, onTap: (t) => setState(() => _selected = t)),
                ]),
                const SizedBox(height: 22),
                Text(s.get('plate').toUpperCase(),
                    style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _plateCtrl.text.isNotEmpty ? WTheme.rose : WTheme.cloud, width: 1.5),
                    boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  child: Row(children: [
                    Text('🔢', style: TextStyle(color: WTheme.muted, fontSize: 18)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _plateCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: GoogleFonts.dmSans(color: WTheme.navy, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 2),
                        decoration: InputDecoration(
                          hintText: '123 ABC',
                          hintStyle: GoogleFonts.dmSans(color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 2),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
            child: SizedBox(
              width: double.infinity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _valid ? WTheme.rose : WTheme.cloud,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _valid ? [BoxShadow(color: WTheme.rose.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8))] : [],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _valid
                        ? () async {
                      final vehicleTypeStr = _selected == VehicleType.car
                          ? 'car'
                          : _selected == VehicleType.scooter ? 'scooter' : 'motorbike';
                      final ok = await context.read<AppViewModel>().completeVehicleSetup(
                        vehicleType: vehicleTypeStr,
                        plateNumber: _plateCtrl.text.trim(),
                      );
                      if (ok) widget.onContinue();
                    }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: Text(s.get('continue_'),
                          style: GoogleFonts.dmSans(
                              color: _valid ? Colors.white : WTheme.muted,
                              fontWeight: FontWeight.w800, fontSize: 16))),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
class _VehicleBtn extends StatelessWidget {
  const _VehicleBtn({required this.emoji, required this.label, required this.type, required this.selected, required this.onTap});
  final String emoji, label;
  final VehicleType type, selected;
  final ValueChanged<VehicleType> onTap;

  @override
  Widget build(BuildContext context) {
    final active = type == selected;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFE7609F), Color(0xFF1E9CD7)],
            )
                : null,
            color: active ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: active ? null : Border.all(color: WTheme.cloud, width: 1.5),
            boxShadow: active ? [BoxShadow(color: WTheme.rose.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))] : [],
          ),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 6),
            Text(label,
                style: GoogleFonts.dmSans(color: active ? Colors.white : WTheme.navy, fontSize: 12, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}
