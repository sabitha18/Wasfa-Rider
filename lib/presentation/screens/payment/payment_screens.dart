import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/data/models/models.dart';
import 'package:wasfa_rider/presentation/widgets/shared_widgets.dart';

// ── PAYMENT SCREEN ─────────────────────────────────────────────
class PaymentScreen extends StatelessWidget {
  const PaymentScreen({
    super.key,
    required this.order,
    required this.onBack,
    required this.onCollectCash,
    required this.onCollectKnet,
    required this.onSendLink,
  });
  final Order order;
  final VoidCallback onBack, onCollectCash, onCollectKnet, onSendLink;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WTheme.blush,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Center(child: Text('‹', style: TextStyle(color: WTheme.navy, fontSize: 22, fontWeight: FontWeight.w700))),
                ),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Collect payment', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 16)),
                Text('#${order.id} · ${order.patient}', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11)),
              ]),
            ]),
          ),
          // Body
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            child: Column(children: [
              // Amount due card — navy gradient, matches HTML exactly
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF023B60), Color(0xFF04527F)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.30), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: Column(children: [
                  Text('AMOUNT DUE', style: GoogleFonts.dmSans(
                      color: Colors.white.withOpacity(0.7), fontSize: 11,
                      fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  RichText(text: TextSpan(
                    children: [
                      TextSpan(text: order.total.toStringAsFixed(3),
                          style: GoogleFonts.dmSans(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800)),
                      TextSpan(text: ' KD',
                          style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 18, fontWeight: FontWeight.w600)),
                    ],
                  )),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: WTheme.warn.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('⏳ NOT PAID YET', style: GoogleFonts.dmSans(
                        color: const Color(0xFFFFD08A), fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              // Payment options — all 3 always shown matching HTML
              _PayOption(
                emoji: '💵', label: 'Cash', desc: 'Collect physical cash now',
                color: WTheme.warn, onTap: onCollectCash,
              ),
              _PayOption(
                emoji: '💳', label: 'KNET', desc: 'Card at the door',
                color: WTheme.sky, onTap: onCollectKnet,
              ),
              _PayOption(
                emoji: '🔗', label: 'Send payment link', desc: 'WhatsApp checkout to patient',
                color: WTheme.ok, onTap: onSendLink,
              ),
            ]),
          )),
        ]),
      ),
    );
  }
}

class _PayOption extends StatelessWidget {
  const _PayOption({required this.emoji, required this.label, required this.color, required this.desc, required this.onTap});
  final String emoji, label, desc;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 5)),
          boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 16, color: WTheme.navy)),
            const SizedBox(height: 2),
            Text(desc, style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted)),
          ])),
          Text('›', style: TextStyle(color: WTheme.cloud, fontSize: 22, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

// ── CASH AMOUNT SCREEN ─────────────────────────────────────────
class CashAmountScreen extends StatefulWidget {
  const CashAmountScreen({super.key, required this.order, required this.onBack, required this.onConfirm});
  final Order order;
  final VoidCallback onBack;
  final ValueChanged<double> onConfirm;

  @override
  State<CashAmountScreen> createState() => _CashAmountScreenState();
}

class _CashAmountScreenState extends State<CashAmountScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.order.total.toStringAsFixed(3));
    _ctrl.addListener(() => setState(() {}));
  }

  double get _given => double.tryParse(_ctrl.text) ?? 0;
  double get _change => (_given - widget.order.total).clamp(0, double.infinity);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WTheme.blush,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(children: [
              GestureDetector(
                onTap: widget.onBack,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: Center(child: Text('‹', style: TextStyle(color: WTheme.navy, fontSize: 22, fontWeight: FontWeight.w700))),
                ),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cash received', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 16)),
                Text('Type the amount the patient gave', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11)),
              ]),
            ]),
          ),
          // Body
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(children: [
              // Order total card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.15), blurRadius: 22, offset: const Offset(0, 8))]),
                child: Column(children: [
                  Text('ORDER TOTAL', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  RichText(text: TextSpan(children: [
                    TextSpan(text: widget.order.total.toStringAsFixed(3), style: GoogleFonts.dmSans(fontSize: 32, color: WTheme.navy, fontWeight: FontWeight.w800)),
                    TextSpan(text: ' KD', style: GoogleFonts.dmSans(fontSize: 14, color: WTheme.muted, fontWeight: FontWeight.w600)),
                  ])),
                ]),
              ),
              // Patient gave card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.15), blurRadius: 22, offset: const Offset(0, 8))]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('PATIENT GAVE', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  TextField(
                    controller: _ctrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    style: GoogleFonts.dmSans(fontSize: 36, color: WTheme.navy, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(
                      hintText: '0.000',
                      hintStyle: GoogleFonts.dmSans(fontSize: 36, color: WTheme.muted, fontWeight: FontWeight.w800),
                      filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
                  // Change to give — aqua gradient
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    margin: const EdgeInsets.only(top: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                          colors: [Color(0xFF58C4E4), Color(0xFF1E9CD7)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Change to give', style: GoogleFonts.dmSans(fontSize: 12, color: Colors.white.withOpacity(0.85))),
                      const SizedBox(height: 4),
                      RichText(text: TextSpan(children: [
                        TextSpan(text: _change.toStringAsFixed(3), style: GoogleFonts.dmSans(fontSize: 28, color: Colors.white, fontWeight: FontWeight.w800)),
                        TextSpan(text: ' KD', style: GoogleFonts.dmSans(fontSize: 14, color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w600)),
                      ])),
                    ]),
                  ),
                ]),
              ),
            ]),
          )),
          // Swipe to confirm at bottom
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
            child: SwipeToConfirm(
              label: 'Confirm cash received',
              color: WTheme.ok,
              onConfirm: () => widget.onConfirm(_given),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── SEND LINK SCREEN ───────────────────────────────────────────
class SendLinkScreen extends StatelessWidget {
  const SendLinkScreen({super.key, required this.order, required this.onBack, required this.onSent});
  final Order order;
  final VoidCallback onBack, onSent;

  @override
  Widget build(BuildContext context) {
    final initials = order.patient.split(' ').map((n) => n.isNotEmpty ? n[0] : '').take(2).join();
    final link = 'pay.wasfakw.com/o/${order.id}';
    final preview = 'Hi ${order.patient}, your payment link for WASFA order #${order.id}: $link · ${order.total.toStringAsFixed(3)} KD';
    return Scaffold(
      backgroundColor: WTheme.blush,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: Center(child: Text('‹', style: TextStyle(color: WTheme.navy, fontSize: 22, fontWeight: FontWeight.w700))),
                ),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Send payment link', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 16)),
                Text('via WhatsApp', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11)),
              ]),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.12), blurRadius: 30, offset: const Offset(0, 12))]),
              child: Column(children: [
                // WhatsApp icon
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF25D366), Color(0xFF128C7E)]),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: const Color(0xFF25D366).withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 12))],
                  ),
                  child: const Center(child: Text('💬', style: TextStyle(fontSize: 40))),
                ),
                const SizedBox(height: 14),
                Text('Pay ${order.total.toStringAsFixed(3)} KD via link',
                    style: GoogleFonts.dmSans(fontSize: 18, color: WTheme.navy, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Patient pays from their phone. Order auto-marks PAID when payment lands.',
                    style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted, height: 1.5), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                // Patient row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: WTheme.rose, borderRadius: BorderRadius.circular(14)),
                      child: Center(child: Text(initials, style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(order.patient, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: WTheme.navy, fontSize: 13)),
                      Text(order.phone, style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted)),
                    ])),
                    const Text('✓', style: TextStyle(fontSize: 16)),
                  ]),
                ),
                const SizedBox(height: 16),
                // Preview
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF25D366).withOpacity(0.4)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('📎 Preview:', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted)),
                    const SizedBox(height: 4),
                    Text('"$preview"', style: GoogleFonts.dmSans(fontSize: 11, color: const Color(0xFF128C7E), fontWeight: FontWeight.w700, height: 1.4)),
                  ]),
                ),
              ]),
            ),
          )),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
            child: SwipeToConfirm(label: 'Send via WhatsApp', color: WTheme.ok, onConfirm: onSent),
          ),
        ]),
      ),
    );
  }
}

// ── PHOTO POD SCREEN ───────────────────────────────────────────
class PhotoPODScreen extends StatefulWidget {
  const PhotoPODScreen({super.key, required this.order, required this.onBack, required this.onCaptured});
  final Order order;
  final VoidCallback onBack, onCaptured;

  @override
  State<PhotoPODScreen> createState() => _PhotoPODScreenState();
}

class _PhotoPODScreenState extends State<PhotoPODScreen> {
  bool _captured = false;

  void _capture() {
    setState(() => _captured = true);
    Future.delayed(const Duration(milliseconds: 500), widget.onCaptured);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Camera viewfinder background
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 1.2,
              colors: [Color(0xFF2a3340), Color(0xFF0f1419)],
            ),
          ),
        ),
        // Door scene mock (matches HTML)
        Positioned(
          top: MediaQuery.of(context).size.height * 0.18,
          left: MediaQuery.of(context).size.width / 2 - 90,
          child: Container(
            width: 180, height: 280,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Color(0xFF4a3324), Color(0xFF2e1f15)]),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF1a1108), width: 4),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 60, offset: Offset(0, 20))],
            ),
          ),
        ),
        // Rx bag on doorstep
        Positioned(
          top: MediaQuery.of(context).size.height * 0.52,
          left: MediaQuery.of(context).size.width / 2 - 55,
          child: Container(
            width: 110, height: 90,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFFF6E8D4), Color(0xFFD4B993)]),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 30, offset: Offset(0, 10))],
            ),
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: WTheme.rose, borderRadius: BorderRadius.circular(4)),
              child: Text('Rx', style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
            )),
          ),
        ),
        // Top bar: close + flash
        Positioned(
          top: MediaQuery.of(context).padding.top + 20,
          left: 16, right: 16,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            GestureDetector(
              onTap: widget.onBack,
              child: Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                child: const Center(child: Text('✕', style: TextStyle(color: Colors.white, fontSize: 18))),
              ),
            ),
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
              child: const Center(child: Text('⚡', style: TextStyle(fontSize: 18))),
            ),
          ]),
        ),
        // Instruction card
        Positioned(
          top: MediaQuery.of(context).padding.top + 70,
          left: 18, right: 18,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 30, offset: Offset(0, 10))],
            ),
            child: Column(children: [
              Text('📸 Photo of medication at door',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 13, color: WTheme.navy)),
              const SizedBox(height: 2),
              Text('POD step 1 of 2 · Order #${widget.order.id}',
                  style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted)),
            ]),
          ),
        ),
        // Aqua corner brackets
        Positioned(
          top: MediaQuery.of(context).size.height * 0.25,
          left: MediaQuery.of(context).size.width / 2 - 130,
          child: SizedBox(
            width: 260, height: 300,
            child: CustomPaint(painter: _CornerBracketsPainter(color: WTheme.aqua)),
          ),
        ),
        // Flash effect
        if (_captured)
          Positioned.fill(child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: 0,
              duration: const Duration(milliseconds: 500),
              child: Container(color: Colors.white),
            ),
          )),
        // Bottom controls
        Positioned(
          bottom: 30, left: 0, right: 0,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
              child: const Center(child: Text('🖼', style: TextStyle(fontSize: 20))),
            ),
            // Shutter button
            GestureDetector(
              onTap: _capture,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 0, spreadRadius: 6)],
                ),
                child: Center(child: Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFFE7609F), Color(0xFF1E9CD7)]),
                    shape: BoxShape.circle,
                  ),
                )),
              ),
            ),
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
              child: const Center(child: Text('🔄', style: TextStyle(fontSize: 20))),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _CornerBracketsPainter extends CustomPainter {
  const _CornerBracketsPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 3..style = PaintingStyle.stroke;
    const l = 30.0;
    // TL
    canvas.drawLine(Offset.zero, Offset(l, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, l), paint);
    // TR
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - l, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, l), paint);
    // BL
    canvas.drawLine(Offset(0, size.height), Offset(l, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - l), paint);
    // BR
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - l, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - l), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── SIGNATURE SCREEN ───────────────────────────────────────────
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key, required this.order, required this.onBack, required this.onSigned});
  final Order order;
  final VoidCallback onBack, onSigned;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final SignatureController _sig = SignatureController(
    penStrokeWidth: 2.5, penColor: WTheme.navy, exportBackgroundColor: Colors.white,
  );
  TextEditingController _recipientCtrl = TextEditingController();
  String _mode = 'signature';
  final List<TextEditingController> _otpCtrls = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpNodes = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _recipientCtrl = TextEditingController(text: 'Recipient: ${widget.order.patient}');
    _sig.addListener(() { if (mounted) setState(() {}); });
  }

  bool get _canConfirm => _mode == 'signature'
      ? _sig.isNotEmpty
      : _otpCtrls.every((c) => c.text.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WTheme.blush,
      body: Column(children: [
        // Ribbon at top (matches HTML)
        RiderRibbon(
          earnings: 0, deliveries: 0,
          onShift: true, onToggleShift: () {},
        ),
        // Back button + title
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(children: [
            GestureDetector(
              onTap: widget.onBack,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))]),
                child: Center(child: Text('‹', style: TextStyle(color: WTheme.navy, fontSize: 22, fontWeight: FontWeight.w700))),
              ),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Confirm handover', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 16)),
              Text('POD step 2 of 2 · #${widget.order.id}', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11)),
            ]),
          ]),
        ),
        // Progress bar
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Row(children: [
            Expanded(child: Container(height: 5, decoration: BoxDecoration(color: WTheme.ok, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(width: 4),
            Expanded(child: Container(height: 5, decoration: BoxDecoration(color: WTheme.rose, borderRadius: BorderRadius.circular(4)))),
          ]),
        ),
        // Mode tabs
        Container(
          margin: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.12), blurRadius: 18, offset: const Offset(0, 6))]),
          child: Row(children: [
            _ModeTab(label: '✍️ Signature', active: _mode == 'signature', onTap: () => setState(() => _mode = 'signature')),
            _ModeTab(label: '📱 OTP code',  active: _mode == 'otp',       onTap: () => setState(() => _mode = 'otp')),
          ]),
        ),
        // Body
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
          child: Column(children: [
            // Signature pad or OTP
            _mode == 'signature' ? _buildSigPad() : _buildOtpPad(),
            const SizedBox(height: 14),
            // Recipient editable field (matches HTML)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 4))]),
              child: Row(children: [
                Text('👤', style: TextStyle(color: WTheme.muted, fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: _recipientCtrl,
                  style: GoogleFonts.dmSans(fontSize: 14, color: WTheme.navy),
                  decoration: const InputDecoration(
                    border: InputBorder.none, enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none, filled: false,
                    isDense: true, contentPadding: EdgeInsets.zero,
                  ),
                )),
              ]),
            ),
            const SizedBox(height: 14),
          ]),
        )),
        // Bottom: SwipeToConfirm when ready, placeholder when not
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          child: _canConfirm
              ? SwipeToConfirm(label: 'Confirm delivery', color: WTheme.ok, onConfirm: widget.onSigned)
              : Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text(
              _mode == 'signature' ? 'Capture signature above' : 'Type the 6-digit code',
              style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 13, fontWeight: FontWeight.w700),
            )),
          ),
        ),
      ]),
    );
  }

  Widget _buildSigPad() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        height: 240,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: WTheme.cloud, width: 2, style: BorderStyle.solid),
          boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(children: [
            Signature(
              controller: _sig,
              backgroundColor: Colors.white,
            ),
            // Dashed baseline
            Positioned(
              bottom: 30, left: 20, right: 20,
              child: Container(height: 1.5,
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: WTheme.cloud, width: 1.5, style: BorderStyle.solid)))),
            ),
            if (!_sig.isNotEmpty)
              Positioned(
                bottom: 35, left: 0, right: 0,
                child: Center(child: Text('SIGN WITH YOUR FINGER ABOVE THE LINE',
                    style: GoogleFonts.dmSans(fontSize: 10, color: WTheme.muted, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
              ),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          GestureDetector(
            onTap: () { _sig.clear(); setState(() {}); },
            child: Row(children: [
              Text('🔄', style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 4),
              Text('Clear', style: GoogleFonts.dmSans(color: WTheme.err, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
          Text('Patient: ${widget.order.patient}', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 12)),
        ]),
      ),
    ]);
  }

  Widget _buildOtpPad() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 20, offset: const Offset(0, 6))]),
      child: Column(children: [
        RichText(textAlign: TextAlign.center, text: TextSpan(
          style: GoogleFonts.dmSans(fontSize: 13, color: WTheme.muted, height: 1.5),
          children: [
            const TextSpan(text: 'A 6-digit code was just sent to '),
            TextSpan(text: widget.order.phone, style: TextStyle(color: WTheme.navy, fontWeight: FontWeight.w800)),
            const TextSpan(text: ' via WhatsApp.\nAsk the patient and type it here.'),
          ],
        )),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: SizedBox(width: 42, height: 56, child: TextField(
              controller: _otpCtrls[i], focusNode: _otpNodes[i],
              maxLength: 1, keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 22, fontWeight: FontWeight.w800, color: WTheme.navy),
              decoration: InputDecoration(
                counterText: '', filled: false,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _otpCtrls[i].text.isNotEmpty ? WTheme.rose : WTheme.cloud, width: 2)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _otpCtrls[i].text.isNotEmpty ? WTheme.rose : WTheme.cloud, width: 2)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: WTheme.rose, width: 2)),
              ),
              onChanged: (v) {
                if (v.isNotEmpty && i < 5) _otpNodes[i + 1].requestFocus();
                if (v.isEmpty && i > 0) _otpNodes[i - 1].requestFocus();
                setState(() {});
              },
            )),
          )),
        ),
        const SizedBox(height: 14),
        RichText(text: TextSpan(
          style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted),
          children: [
            const TextSpan(text: 'Demo code: '),
            TextSpan(text: '123456', style: TextStyle(color: WTheme.rose, fontWeight: FontWeight.w800)),
          ],
        )),
      ]),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? WTheme.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: active ? [BoxShadow(color: WTheme.navy.withOpacity(0.30), blurRadius: 14, offset: const Offset(0, 6))] : [],
        ),
        child: Center(child: Text(label,
            style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700,
                color: active ? Colors.white : WTheme.muted))),
      ),
    ));
  }
}

// ── SUCCESS SCREEN ─────────────────────────────────────────────
class SuccessScreen extends StatefulWidget {
  const SuccessScreen({
    super.key,
    required this.order,
    this.nextOrder,
    required this.earningsBump,
    required this.onContinue,
  });
  final Order order;
  final Order? nextOrder;
  final double earningsBump;
  final VoidCallback onContinue;

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _popCtrl;
  late final Animation<double> _popAnim;

  @override
  void initState() {
    super.initState();
    // Pop animation for checkmark circle
    _popCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _popAnim = CurvedAnimation(parent: _popCtrl, curve: Curves.elasticOut);
    _popCtrl.forward();
    // Auto-navigate after 5 seconds (matches HTML's setTimeout 5000)
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) widget.onContinue();
    });
  }

  @override
  void dispose() {
    _popCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = widget.nextOrder;
    return Scaffold(
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF21B47A), Color(0xFF18A06D), Color(0xFF023B60)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: Stack(children: [
          // Radial white glow at top
          Positioned(
            top: -100, left: 0, right: 0,
            child: Container(
              height: 400,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, 0.3),
                  radius: 0.8,
                  colors: [Colors.white.withOpacity(0.18), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(children: [
              const SizedBox(height: 100),
              // Animated checkmark circle
              ScaleTransition(
                scale: _popAnim,
                child: Container(
                  width: 130, height: 130,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.white.withOpacity(0.15), blurRadius: 0, spreadRadius: 10),
                      BoxShadow(color: Colors.white.withOpacity(0.08), blurRadius: 0, spreadRadius: 22),
                      const BoxShadow(color: Colors.black26, blurRadius: 40, offset: Offset(0, 20)),
                    ],
                  ),
                  child: Center(child: Text('✓', style: TextStyle(
                      fontSize: 64, color: WTheme.ok, fontWeight: FontWeight.w800))),
                ),
              ),
              const SizedBox(height: 22),
              // Title
              Text('Delivered!', style: GoogleFonts.dmSans(
                  color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text('Order #${widget.order.id} · ${widget.order.total.toStringAsFixed(3)} KD',
                  style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 14)),
              const SizedBox(height: 26),
              // Next stop card OR all-done message
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: next != null ? _buildNextCard(next) : _buildAllDone(),
              ),
              const SizedBox(height: 16),
              // Earnings bump
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.20)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Earnings bump', style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 12)),
                      Text('+${widget.earningsBump.toStringAsFixed(3)} KD',
                          style: GoogleFonts.dmSans(color: const Color(0xFFB7F5CE), fontSize: 14, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Swipe to continue
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: SwipeToConfirm(
                  label: next != null ? 'Start next stop' : 'Finish shift',
                  color: WTheme.aqua,
                  onConfirm: widget.onContinue,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildNextCard(Order next) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: WTheme.aqua, borderRadius: BorderRadius.circular(6)),
            child: Text('NEXT STOP', style: GoogleFonts.dmSans(
                color: WTheme.navy, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
          Text('Stop ${next.stopNumber}', style: GoogleFonts.dmSans(
              color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Text(next.patient, style: GoogleFonts.dmSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('${next.addr1} · ${next.addr2}', style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          Text('📍 ', style: const TextStyle(fontSize: 11)),
          Text('${next.distanceKm} km', style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(width: 14),
          Text('⏱ ', style: const TextStyle(fontSize: 11)),
          Text('${next.etaMin} min', style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(width: 14),
          Text(next.paid ? '✓ Paid' : '💵 ${next.payMethod.name.toUpperCase()}',
              style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  Widget _buildAllDone() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(children: [
        const Text('🎉', style: TextStyle(fontSize: 32)),
        const SizedBox(height: 8),
        Text('All deliveries done! Time for cash handover.',
            style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 14),
            textAlign: TextAlign.center),
      ]),
    );
  }
}

// ── FAILED DELIVERY SCREEN ─────────────────────────────────────
class FailedDeliveryScreen extends StatefulWidget {
  const FailedDeliveryScreen({super.key, required this.order, required this.onBack, required this.onConfirm});
  final Order order;
  final VoidCallback onBack;
  final ValueChanged<String> onConfirm;

  @override
  State<FailedDeliveryScreen> createState() => _FailedDeliveryScreenState();
}

class _FailedDeliveryScreenState extends State<FailedDeliveryScreen> {
  String? _selected;
  final _noteCtrl = TextEditingController();

  static const _reasons = [
    'Patient not home',
    'Patient refused delivery',
    'Wrong address',
    'Patient not reachable',
    'Payment issue',
    'Items damaged',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        _Header(title: 'Failed Delivery', onBack: widget.onBack),
        Expanded(child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Select a reason:', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 14, color: WTheme.muted)),
            const SizedBox(height: 10),
            ..._reasons.map((r) => GestureDetector(
              onTap: () => setState(() => _selected = r),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _selected == r ? WTheme.err.withOpacity(0.08) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _selected == r ? WTheme.err : WTheme.cloud, width: 1.5),
                ),
                child: Row(children: [
                  Icon(_selected == r ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: _selected == r ? WTheme.err : WTheme.muted, size: 20),
                  const SizedBox(width: 10),
                  Text(r, style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14,
                      color: _selected == r ? WTheme.err : WTheme.ink)),
                ]),
              ),
            )),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Additional notes (optional)',
                filled: true, fillColor: WTheme.cloud,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: WTheme.err, padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _selected != null ? () => widget.onConfirm(_selected!) : null,
              child: Text('Report as Failed', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 15)),
            )),
          ],
        )),
      ]),
    );
  }
}

// ── Shared header ──────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 10, left: 16, right: 16, bottom: 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [WTheme.navy, Color(0xFF04527F)]),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: onBack,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
          ),
        ),
        const SizedBox(width: 14),
        Text(title, style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
      ]),
    );
  }
}
