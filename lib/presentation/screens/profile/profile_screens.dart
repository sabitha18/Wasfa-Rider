import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wasfa_rider/core/theme/app_theme.dart';
import 'package:wasfa_rider/presentation/viewmodels/app_viewmodel.dart';
import 'package:wasfa_rider/presentation/viewmodels/orders_viewmodel.dart';
import 'package:wasfa_rider/presentation/widgets/shared_widgets.dart';
import 'package:wasfa_rider/data/models/models.dart';

// ── PROFILE SCREEN (main) ──────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onTabChange,
    required this.onOpenHistory,
    required this.onLogout,
  });
  final ValueChanged<String> onTabChange;
  final VoidCallback onOpenHistory, onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _role = 'zone'; // 'express' | 'batch' | 'zone'

  @override
  Widget build(BuildContext context) {
    final appVM   = context.watch<AppViewModel>();
    final ordersVM = context.watch<OrdersViewModel>();
    final driver  = appVM.driver;
    if (driver == null) return const Scaffold();

    final done    = ordersVM.orders.where((o) => o.status.name == 'done').length;
    final totalKm = ordersVM.orders.where((o) => o.status.name == 'done')
        .fold(0.0, (s, o) => s + o.distanceKm);

    return Scaffold(
      backgroundColor: WTheme.blush,
      body: Column(children: [
        RiderRibbon(
          earnings: driver.todayEarnings,
          deliveries: driver.deliveriesToday,
          onShift: driver.onShift,
          onToggleShift: appVM.toggleShift,
          role: _role,
        ),
        Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            // ── Driver card ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.10), blurRadius: 14, offset: const Offset(0, 4))],
              ),
              child: Column(children: [
                // Avatar
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [WTheme.rose, WTheme.sky]),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [BoxShadow(color: WTheme.rose.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Center(child: Text(driver.avatarInitials,
                      style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 24))),
                ),
                const SizedBox(height: 12),
                Text(driver.name, style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 17, letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text('${driver.phone} · ⭐ 4.8', style: GoogleFonts.dmSans(fontSize: 12, color: WTheme.muted)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(999)),
                  child: Text('🛵 ${driver.vehiclePlate ?? "—"}',
                      style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.navy, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),

            // ── My driver profile button ──────────────────────
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DriverProfileScreen(onBack: () => Navigator.of(context).pop()))),
              child: Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF023B60), Color(0xFF1E9CD7)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(12)),
                    child: const Center(child: Text('👤', style: TextStyle(fontSize: 18))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('My driver profile', style: GoogleFonts.dmSans(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                    Text('Personal info · documents · vehicle · bank', style: GoogleFonts.dmSans(
                        color: Colors.white.withOpacity(0.85), fontSize: 11)),
                  ])),
                  Text('›', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 22, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),

            // ── Role selector ─────────────────────────────────
            Text('DEMO: CHANGE ROLE', style: GoogleFonts.dmSans(
                fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted,
                letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
              ),
              child: Row(children: [
                for (final r in [('express', '🏍 Express'), ('batch', '🛵 Batch'), ('zone', '📍 Zone')])
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() => _role = r.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: _role == r.$1 ? WTheme.navy : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(child: Text(r.$2, style: GoogleFonts.dmSans(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: _role == r.$1 ? Colors.white : WTheme.muted))),
                    ),
                  )),
              ]),
            ),

            // ── Order history ─────────────────────────────────
            GestureDetector(
              onTap: widget.onOpenHistory,
              child: Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
                ),
                child: Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(color: WTheme.blush, borderRadius: BorderRadius.circular(12)),
                    child: const Center(child: Text('📋', style: TextStyle(fontSize: 18))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Order history', style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w700, color: WTheme.navy, fontSize: 14)),
                    Text('All completed deliveries', style: GoogleFonts.dmSans(
                        fontSize: 11, color: WTheme.muted)),
                  ])),
                  Text('›', style: TextStyle(color: WTheme.cloud, fontSize: 20, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),

            // ── Language ──────────────────────────────────────
            Text('LANGUAGE', style: GoogleFonts.dmSans(
                fontSize: 11, fontWeight: FontWeight.w700, color: WTheme.muted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))],
              ),
              child: Row(children: [
                for (final l in [('en', 'English'), ('ar', 'العربية')])
                  Expanded(child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: l.$1 == 'en' ? WTheme.navy : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: Text(l.$2, style: GoogleFonts.dmSans(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: l.$1 == 'en' ? Colors.white : WTheme.muted))),
                  )),
              ]),
            ),

            // ── Log out ────────────────────────────────────────
            GestureDetector(
              onTap: widget.onLogout,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: WTheme.err, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: WTheme.err.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Center(child: Text('🚪 Log out', style: GoogleFonts.dmSans(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
              ),
            ),
            const SizedBox(height: 22),

            // ── Footer ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(12)),
              child: RichText(text: TextSpan(
                style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted, height: 1.6),
                children: [
                  TextSpan(text: 'WASFA Rider V2 · Interactive prototype\n',
                      style: TextStyle(color: WTheme.navy, fontWeight: FontWeight.w800)),
                  const TextSpan(text: 'This is a working spec for the native Android rebuild. Connects to mock data — no backend yet.'),
                ],
              )),
            ),
          ],
        )),
        RiderBottomNav(current: 'profile', onChanged: widget.onTabChange),
      ]),
    );
  }
}

// ── DRIVER PROFILE EDITOR ──────────────────────────────────────
class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final Map<String, String> _data = {
    'fullName': 'Ahmed Al-Rashidi', 'arabicName': 'أحمد الراشدي',
    'dob': '', 'employer': 'WASFA Logistics', 'employeeId': 'WL-4821',
    'joinedAt': '',
    'phone': '+965 9XXX 1234', 'whatsapp': '', 'email': 'ahmed@example.com',
    'civilId': '', 'civilIdExpiry': '', 'nationality': 'Kuwaiti', 'bloodGroup': 'O+',
    'vehicleType': 'motorbike', 'vehiclePlate': '', 'vehicleMake': 'Honda', 'vehicleYear': '',
    'bankName': 'NBK', 'bankIban': '',
  };
  final Set<String> _langs = {'Arabic', 'English'};
  final Set<String> _uploadedDocs = {};
  String _photo = '👤';

  int get _completion {
    final fields = [
      'fullName', 'dob', 'nationality', 'civilId', 'phone', 'employer',
      'vehiclePlate', 'bankIban',
    ];
    final filled = fields.where((k) => (_data[k] ?? '').isNotEmpty).length;
    const requiredDocs = 6;
    final totalRequired = fields.length + requiredDocs;
    final filledTotal = filled + _uploadedDocs.length;
    return ((filledTotal / totalRequired) * 100).round();
  }

  Future<void> _pickDate(String key) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1970, 1, 1),
      lastDate: DateTime(2100, 1, 1),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(primary: WTheme.rose, onPrimary: Colors.white, onSurface: WTheme.navy),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _data[key] = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WTheme.blush,
      body: Column(children: [
        RiderRibbon(earnings: 0, deliveries: 0, onShift: true, onToggleShift: () {}),
        // Sub-header
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
              Text('My driver profile', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 16)),
              Text('$_completion% complete', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 11)),
            ]),
          ]),
        ),
        Expanded(child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            // Hero card
            Container(
              padding: const EdgeInsets.all(18),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF023B60), Color(0xFF1E9CD7)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.30), blurRadius: 30, offset: const Offset(0, 12))],
              ),
              child: Column(children: [
                Row(children: [
                  // Avatar
                  Stack(children: [
                    GestureDetector(
                      onTap: () => setState(() => _photo = '📸'),
                      child: Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [WTheme.rose, WTheme.sky]),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.5), width: 3),
                        ),
                        child: Center(child: Text(_photo, style: const TextStyle(fontSize: 28))),
                      ),
                    ),
                    Positioned(bottom: -2, right: -2, child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)]),
                      child: const Center(child: Icon(Icons.camera_alt, size: 13, color: Color(0xFF023B60))),
                    )),
                  ]),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_data['fullName']!.isNotEmpty ? _data['fullName']! : 'Add your name', style: GoogleFonts.dmSans(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    Text('${_data['employer']!.isNotEmpty ? _data['employer'] : '—'} · ID ${_data['employeeId']!.isNotEmpty ? _data['employeeId'] : '—'}',
                        style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 11)),
                  ])),
                ]),
                const SizedBox(height: 14),
                // Completion bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _completion / 100,
                    backgroundColor: Colors.white.withOpacity(0.18),
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft,
                    child: Text('Profile completion · $_completion% — finish all sections to keep working without interruptions',
                        style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.85), fontSize: 10, fontWeight: FontWeight.w700))),
              ]),
            ),

            // Personal
            _Section(icon: Icons.person, iconColor: WTheme.navy, title: 'Personal information', children: [
              _Field(label: 'Full name (English)', value: _data['fullName'] ?? '',
                  onChange: (v) => setState(() => _data['fullName'] = v)),
              _Field(label: 'Full name (Arabic)', value: _data['arabicName'] ?? '',
                  onChange: (v) => setState(() => _data['arabicName'] = v)),
              _DateField(label: 'Date of birth', value: _data['dob'] ?? '', onTap: () => _pickDate('dob')),
              _Picker(label: 'Nationality', value: _data['nationality'] ?? '',
                  options: ['Kuwaiti','Egyptian','Indian','Bangladeshi','Pakistani','Filipino','Syrian','Jordanian','Lebanese','Other'],
                  onChange: (v) => setState(() => _data['nationality'] = v)),
              _Field(label: 'Civil ID number (12 digits)', value: _data['civilId'] ?? '',
                  onChange: (v) => setState(() => _data['civilId'] = v),
                  keyboard: TextInputType.number),
              _DateField(label: 'Civil ID expiry', value: _data['civilIdExpiry'] ?? '', onTap: () => _pickDate('civilIdExpiry')),
              _Picker(label: 'Blood group', value: _data['bloodGroup'] ?? '',
                  options: ['A+','A-','B+','B-','AB+','AB-','O+','O-','Unknown'],
                  onChange: (v) => setState(() => _data['bloodGroup'] = v)),
              const SizedBox(height: 8),
              Text('LANGUAGES SPOKEN', style: GoogleFonts.dmSans(
                  fontSize: 10, fontWeight: FontWeight.w800, color: WTheme.muted, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final l in ['Arabic','English','Hindi','Urdu','Tagalog','French'])
                  GestureDetector(
                    onTap: () => setState(() => _langs.contains(l) ? _langs.remove(l) : _langs.add(l)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _langs.contains(l) ? WTheme.navy : WTheme.cloud,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${_langs.contains(l) ? "✓ " : ""}$l', style: GoogleFonts.dmSans(
                          color: _langs.contains(l) ? Colors.white : WTheme.navy,
                          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                    ),
                  ),
              ]),
            ]),

            // Contact
            _Section(icon: Icons.call, iconColor: WTheme.err, title: 'Contact', children: [
              _Field(label: 'Primary phone', value: _data['phone'] ?? '',
                  onChange: (v) => setState(() => _data['phone'] = v),
                  keyboard: TextInputType.phone),
              _Field(label: 'WhatsApp number', value: _data['whatsapp'] ?? '',
                  onChange: (v) => setState(() => _data['whatsapp'] = v),
                  keyboard: TextInputType.phone),
              _Field(label: 'Email', value: _data['email'] ?? '',
                  onChange: (v) => setState(() => _data['email'] = v),
                  keyboard: TextInputType.emailAddress),
              Text('HOME ADDRESS', style: GoogleFonts.dmSans(
                  fontSize: 10, fontWeight: FontWeight.w800, color: WTheme.muted, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              _Field(label: 'Area', value: '', onChange: (_) {}),
              _Field(label: 'Block', value: '', onChange: (_) {}),
              _Field(label: 'Street', value: '', onChange: (_) {}),
              _Field(label: 'House / building', value: '', onChange: (_) {}),
            ]),

            // Emergency
            _Section(icon: Icons.sos, iconColor: WTheme.rose, title: 'Emergency contact', children: [
              _Field(label: 'Contact name', value: '', onChange: (_) {}),
              _Field(label: 'Contact phone', value: '', onChange: (_) {}, keyboard: TextInputType.phone),
              _Picker(label: 'Relationship', value: '',
                  options: ['Father','Mother','Spouse','Sibling','Friend','Relative','Other'],
                  onChange: (_) {}),
            ]),

            // Employment
            _Section(icon: Icons.business_center, iconColor: WTheme.navy, title: 'Employment', children: [
              _Field(label: 'Company / employer', value: _data['employer'] ?? '', onChange: (v) => setState(() => _data['employer'] = v)),
              _Field(label: 'Employee ID', value: _data['employeeId'] ?? '', onChange: (v) => setState(() => _data['employeeId'] = v)),
              _DateField(label: 'Joining date', value: _data['joinedAt'] ?? '', onTap: () => _pickDate('joinedAt')),
              _Field(label: 'Years of driving experience', value: '', onChange: (_) {}, keyboard: TextInputType.number),
            ]),

            // Vehicle
            _Section(icon: Icons.two_wheeler, iconColor: WTheme.sky, title: 'Vehicle', children: [
              _Picker(label: 'Vehicle type', value: _data['vehicleType'] ?? '',
                  options: ['motorbike','scooter','car'],
                  onChange: (v) => setState(() => _data['vehicleType'] = v)),
              _Field(label: 'Plate number', value: _data['vehiclePlate'] ?? '',
                  onChange: (v) => setState(() => _data['vehiclePlate'] = v)),
              _Field(label: 'Make (Honda, Toyota…)', value: _data['vehicleMake'] ?? '', onChange: (v) => setState(() => _data['vehicleMake'] = v)),
              _Field(label: 'Model', value: '', onChange: (_) {}),
              _Field(label: 'Year', value: _data['vehicleYear'] ?? '',
                  onChange: (v) => setState(() => _data['vehicleYear'] = v),
                  keyboard: TextInputType.number),
              _Field(label: 'Color', value: '', onChange: (_) {}),
            ]),

            // Bank
            _Section(icon: Icons.account_balance, iconColor: WTheme.ok, title: 'Bank account (for commission payouts)', children: [
              _Picker(label: 'Bank', value: _data['bankName'] ?? '',
                  options: ['NBK','KFH','Boubyan','CBK','Gulf Bank','Burgan','Warba','Ahli United','ABK','Other'],
                  onChange: (v) => setState(() => _data['bankName'] = v)),
              _Field(label: 'IBAN', value: _data['bankIban'] ?? '', onChange: (v) => setState(() => _data['bankIban'] = v)),
              _Field(label: 'Beneficiary name (as on bank)', value: '', onChange: (_) {}),
            ]),

            // Documents
            _Section(icon: Icons.attach_file, iconColor: WTheme.muted, title: 'Documents — uploads required', children: [
              for (final doc in [
                'Civil ID — FRONT', 'Civil ID — BACK',
                'Driving license — FRONT', 'Driving license — BACK',
                'Vehicle registration / license', 'Vehicle insurance',
              ])
                _DocSlot(
                  label: doc,
                  uploaded: _uploadedDocs.contains(doc),
                  onUpload: () => setState(() => _uploadedDocs.add(doc)),
                ),
            ]),
          ],
        )),

        // ── Sticky save bar ──────────────────────────────────
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 20 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, -8))],
          ),
          child: GestureDetector(
            onTap: () { showWToast(context, '✅ Profile saved'); widget.onBack(); },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [WTheme.rose, const Color(0xFFC84686)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: WTheme.rose.withOpacity(0.4), blurRadius: 28, offset: const Offset(0, 12))],
              ),
              child: Center(child: Text('💾 SAVE PROFILE', style: GoogleFonts.dmSans(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.4))),
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Section wrapper — colored icon badge + collapsible body ────
class _Section extends StatefulWidget {
  const _Section({required this.icon, required this.iconColor, required this.title, required this.children});
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool _open = true;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 14, offset: const Offset(0, 4))]),
    child: Column(children: [
      GestureDetector(
        onTap: () => setState(() => _open = !_open),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: _open ? Border(bottom: BorderSide(color: WTheme.cloud, width: 1)) : null,
          ),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: widget.iconColor.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
              child: Icon(widget.icon, size: 16, color: widget.iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.title.toUpperCase(), style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 12, letterSpacing: 0.3))),
            Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: WTheme.muted, size: 20),
          ]),
        ),
      ),
      if (_open) Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widget.children),
      ),
    ]),
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, required this.onChange, this.keyboard});
  final String label, value;
  final ValueChanged<String> onChange;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800, color: WTheme.muted, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      TextFormField(
        initialValue: value,
        keyboardType: keyboard,
        onChanged: onChange,
        style: GoogleFonts.dmSans(fontSize: 13, color: WTheme.navy, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          filled: true, fillColor: WTheme.blush.withOpacity(0.5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: WTheme.cloud, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: WTheme.cloud, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: WTheme.sky, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      ),
    ]),
  );
}

// ── Date field — tap to open native date picker ────────────────
class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});
  final String label, value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800, color: WTheme.muted, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: WTheme.blush.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: WTheme.cloud, width: 1.5),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_rounded, size: 15, color: WTheme.sky),
            const SizedBox(width: 8),
            Expanded(child: Text(value.isNotEmpty ? value : 'Select date…', style: GoogleFonts.dmSans(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: value.isNotEmpty ? WTheme.navy : WTheme.muted))),
          ]),
        ),
      ),
    ]),
  );
}

class _Picker extends StatelessWidget {
  const _Picker({required this.label, required this.value, required this.options, required this.onChange});
  final String label, value;
  final List<String> options;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800, color: WTheme.muted, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        value: value.isNotEmpty && options.contains(value) ? value : null,
        hint: Text('— Select —', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 13)),
        items: options.map((o) => DropdownMenuItem(value: o, child: Text(o,
            style: GoogleFonts.dmSans(fontSize: 13, color: WTheme.navy)))).toList(),
        onChanged: (v) { if (v != null) onChange(v); },
        decoration: InputDecoration(
          filled: true, fillColor: WTheme.blush.withOpacity(0.5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: WTheme.cloud, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: WTheme.cloud, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: WTheme.sky, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          isDense: true,
        ),
      ),
    ]),
  );
}

// ── Document upload slot ────────────────────────────────────────
// NOTE: this only tracks an "uploaded" flag — there's no real camera/
// gallery capture wired up yet, so no actual thumbnail can render.
// Wiring up the `image_picker` package would let this show a real photo.
class _DocSlot extends StatelessWidget {
  const _DocSlot({required this.label, required this.uploaded, required this.onUpload});
  final String label;
  final bool uploaded;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: uploaded ? WTheme.ok.withOpacity(0.06) : WTheme.blush.withOpacity(0.5),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: uploaded ? WTheme.ok : WTheme.cloud, width: 1.5),
    ),
    child: Row(children: [
      Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          color: uploaded ? WTheme.ok : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: uploaded ? null : Border.all(color: WTheme.cloud, width: 1.5),
        ),
        child: Icon(uploaded ? Icons.check_rounded : Icons.camera_alt_outlined,
            size: 22, color: uploaded ? Colors.white : WTheme.muted),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.dmSans(
            fontSize: 11, fontWeight: FontWeight.w800, color: WTheme.navy, letterSpacing: 0.3)),
        const SizedBox(height: 2),
        Text(uploaded ? 'Uploaded' : 'Tap to take a clear photo', style: GoogleFonts.dmSans(
            fontSize: 10, fontWeight: uploaded ? FontWeight.w700 : FontWeight.w600,
            color: uploaded ? WTheme.ok : WTheme.muted)),
      ])),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onUpload,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: uploaded ? Colors.white : WTheme.rose,
            borderRadius: BorderRadius.circular(10),
            border: uploaded ? Border.all(color: WTheme.rose, width: 1.5) : null,
          ),
          child: Text(uploaded ? 'RETAKE' : 'UPLOAD', style: GoogleFonts.dmSans(
              fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4,
              color: uploaded ? WTheme.rose : Colors.white)),
        ),
      ),
    ]),
  );
}



// ── HISTORY SCREEN ─────────────────────────────────────────────
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final allOrders = context.watch<OrdersViewModel>().orders;
    final done = allOrders.where((o) => o.status.name == 'done').toList()
      ..sort((a, b) {
        final ad = a.deliveredAt;
        final bd = b.deliveredAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad); // most recent first
      });
    final failed = allOrders.where((o) => o.status.name == 'failed').toList();
    final combined = [...done, ...failed];

    return Scaffold(
      backgroundColor: WTheme.blush,
      body: Column(children: [
        // ── Navy app bar — matches HTML exactly ──
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 16, 18, 16),
          color: WTheme.navy,
          child: Row(children: [
            GestureDetector(
              onTap: onBack,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('‹', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))),
              ),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Order history', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 18)),
              const SizedBox(height: 2),
              Text('${done.length} completed deliveries', style: GoogleFonts.dmSans(
                  color: Colors.white.withOpacity(0.75), fontSize: 11)),
            ]),
          ]),
        ),
        Expanded(child: combined.isEmpty
            ? Center(child: Container(
          margin: const EdgeInsets.all(30),
          padding: const EdgeInsets.symmetric(vertical: 30),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('📋', style: TextStyle(fontSize: 38)),
            const SizedBox(height: 10),
            Text('No completed orders yet', style: GoogleFonts.dmSans(color: WTheme.navy, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Deliveries will show up here.', style: GoogleFonts.dmSans(color: WTheme.muted, fontSize: 12)),
          ]),
        ))
            : ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: combined.length,
          itemBuilder: (_, i) {
            final o = combined[i];
            final isDone = o.status.name == 'done';
            final accent = isDone ? WTheme.ok : WTheme.err;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border(left: BorderSide(color: accent, width: 4)),
                boxShadow: [BoxShadow(color: WTheme.navy.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Green (or red) checkmark badge
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Text(isDone ? '✓' : '✕', style: GoogleFonts.dmSans(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Patient name + total
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Expanded(child: Text(o.patient, style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w700, color: WTheme.navy, fontSize: 14))),
                    Text('${o.total.toStringAsFixed(3)} KD', style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w800, color: WTheme.navy, fontSize: 14)),
                  ]),
                  const SizedBox(height: 2),
                  Text('${o.addr1} · ${o.addr2}', style: GoogleFonts.dmSans(fontSize: 11, color: WTheme.muted)),
                  const SizedBox(height: 6),
                  // Chip row: status pill + pay chip + order id pill
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: accent.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        isDone
                            ? 'Delivered ${o.deliveredAt != null ? _fmtDate(o.deliveredAt!) : 'today'}'
                            : 'Failed',
                        style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w700, color: accent),
                      ),
                    ),
                    _HistoryPayChip(method: o.payMethod),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: WTheme.cloud, borderRadius: BorderRadius.circular(999)),
                      child: Text('#${o.id}', style: GoogleFonts.dmSans(
                          fontSize: 10, fontWeight: FontWeight.w700, color: WTheme.navy)),
                    ),
                  ]),
                ])),
              ]),
            );
          },
        )),
      ]),
    );
  }

  static String _fmtDate(DateTime d) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}
// ── Small pay chip — sized to match the other pills on this screen ──
class _HistoryPayChip extends StatelessWidget {
  const _HistoryPayChip({required this.method});
  final PayMethod method;

  @override
  Widget build(BuildContext context) {
    final Map<String, (Color, Color, String)> styles = {
      'paid': (WTheme.ok.withOpacity(0.15), WTheme.ok, 'PAID'),
      'cash': (const Color(0xFFF5A524).withOpacity(0.15), const Color(0xFFB4730E), 'CASH'),
      'knet': (WTheme.sky.withOpacity(0.12), WTheme.sky, 'KNET'),
      'link': (WTheme.ok.withOpacity(0.12), WTheme.ok, 'LINK'),
    };
    final (bg, fg, label) = styles[method.name.toLowerCase()] ?? (WTheme.cloud, WTheme.navy, 'CASH');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}