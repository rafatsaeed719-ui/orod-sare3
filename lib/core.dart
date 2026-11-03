import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'firebase_options.dart';

// ======================== ثوابت ========================

const String kAppName = 'أورد على السريع';
const String kAdminEmail = 'rafatsaeed719@gmail.com';
const String kUserDomain = 'orod-sare3.app';

/// عمولة التطبيق الثابتة على كل أوردر
const double kRate = 0.05;
const String kInstaPay = '01207760898';
const String kVodaCash = '01018530843';
const String kPayName = 'رأفت سعيد';

/// القاهرة (لو مفيش لوكيشن)
final LatLng kDefaultCenter = LatLng(30.0444, 31.2357);

// ======================== الألوان ========================

const Color kBg = Color(0xFF0D1020);
const Color kPanel = Color(0xFF161A33);
const Color kPanel2 = Color(0xFF1E2344);
const Color kDeep = Color(0xFF10142E);
const Color kLine = Color(0xFF2B315C);
const Color kTxt = Color(0xFFF3F4FB);
const Color kMuted = Color(0xFF9AA0C3);
const Color kOrange = Color(0xFFFF7A18);
const Color kOrange2 = Color(0xFFFFB347);
const Color kRed = Color(0xFFFF3D5A);
const Color kGreen = Color(0xFF22D38A);
const Color kBlue = Color(0xFF3D8BFF);
const Color kPurple = Color(0xFF9B5CFF);
const Color kGold = Color(0xFFFFD24A);

/// ألوان الأيقونات الـ 3D
class G3 {
  static const or = [Color(0xFFFFB347), Color(0xFFFF5F1F)];
  static const bl = [Color(0xFF6FB4FF), Color(0xFF2B5CFF)];
  static const gr = [Color(0xFF5FF0B0), Color(0xFF0FA86A)];
  static const pu = [Color(0xFFC59BFF), Color(0xFF6A2BFF)];
  static const rd = [Color(0xFFFF8A9A), Color(0xFFE0173A)];
  static const gd = [Color(0xFFFFF09A), Color(0xFFE8A400)];
  static const cy = [Color(0xFF7FF3FF), Color(0xFF0A9FC9)];
}

// ======================== Firebase ========================

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
String get uid => auth.currentUser?.uid ?? '';
bool get isAdmin => (auth.currentUser?.email ?? '').toLowerCase() == kAdminEmail.toLowerCase();

CollectionReference<Map<String, dynamic>> get usersCol => db.collection('users');
CollectionReference<Map<String, dynamic>> get captainsCol => db.collection('captains');
CollectionReference<Map<String, dynamic>> get projectsCol => db.collection('projects');
CollectionReference<Map<String, dynamic>> get ordersCol => db.collection('orders');
CollectionReference<Map<String, dynamic>> get paymentsCol => db.collection('payments');
CollectionReference<Map<String, dynamic>> get redeemsCol => db.collection('redeems');
CollectionReference<Map<String, dynamic>> get messagesCol => db.collection('messages');
CollectionReference<Map<String, dynamic>> get sosCol => db.collection('sos');
DocumentReference<Map<String, dynamic>> get settingsRef => db.collection('meta').doc('settings');

// ======================== التليفون ========================

String normPhone(String input) {
  var d = input.replaceAll(RegExp(r'[^0-9٠-٩]'), '');
  const ar = '٠١٢٣٤٥٦٧٨٩';
  d = d.split('').map((c) {
    final i = ar.indexOf(c);
    return i >= 0 ? '$i' : c;
  }).join();
  if (d.startsWith('0020')) d = d.substring(4);
  if (d.startsWith('20') && d.length == 12) d = d.substring(2);
  if (d.length == 10 && d.startsWith('1')) d = '0$d';
  return d;
}

bool validPhone(String p) => RegExp(r'^01[0-9]{9}$').hasMatch(normPhone(p));
String phoneToEmail(String phone) => '${normPhone(phone)}@$kUserDomain';
String loginToEmail(String input) {
  final t = input.trim();
  return t.contains('@') ? t : phoneToEmail(t);
}

String waNumber(String phone) {
  final p = normPhone(phone);
  if (p.startsWith('0') && p.length == 11) return '2$p';
  return p;
}

Future<void> openWhatsApp(String phone, String text) async {
  final uri = Uri.parse('https://wa.me/${waNumber(phone)}?text=${Uri.encodeComponent(text)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> callPhone(String phone) async {
  await launchUrl(Uri.parse('tel:${normPhone(phone)}'));
}

/// يفتح جوجل ماب على الطريق للنقطة دي
Future<void> navigateTo(double lat, double lng) async {
  final nav = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
  try {
    if (await launchUrl(nav, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  await launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
      mode: LaunchMode.externalApplication);
}

String mapsLink(double lat, double lng) => 'https://maps.google.com/?q=$lat,$lng';

/// يطلّع الإحداثيات من لينك لوكيشن (جوجل ماب أو واتساب) أو "30.1, 31.2"
LatLng? parseLocation(String text) {
  final pats = [
    RegExp(r'@(-?\d{1,3}\.\d+),\s*(-?\d{1,3}\.\d+)'),
    RegExp(r'[?&](?:q|query|destination|ll)=(-?\d{1,3}\.\d+)(?:,|%2C)\s*(-?\d{1,3}\.\d+)'),
    RegExp(r'!3d(-?\d{1,3}\.\d+)!4d(-?\d{1,3}\.\d+)'),
    RegExp(r'(-?\d{1,3}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})'),
  ];
  for (final p in pats) {
    final m = p.firstMatch(text);
    if (m != null) {
      final a = double.tryParse(m.group(1)!), b = double.tryParse(m.group(2)!);
      if (a != null && b != null && a.abs() <= 90 && b.abs() <= 180) return LatLng(a, b);
    }
  }
  return null;
}

// ======================== اللوكيشن ========================

/// اللوكيشن الحالي (بيطلب الإذن لو محتاج). بيرجع null لو مفيش إذن أو الـ GPS مقفول
Future<LatLng?> myLocation(BuildContext? context) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (context != null && context.mounted) toast(context, 'افتح الـ GPS (اللوكيشن) من الموبايل', error: true);
      return null;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      if (context != null && context.mounted) toast(context, 'لازم تسمح للتطبيق باللوكيشن', error: true);
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
    return LatLng(pos.latitude, pos.longitude);
  } catch (_) {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return LatLng(last.latitude, last.longitude);
    } catch (_) {}
    return null;
  }
}

/// المسافة بالكيلو
double kmBetween(double lat1, double lng1, double lat2, double lng2) =>
    Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000;

String kmTxt(double km) => km < 1 ? '${(km * 1000).round()} متر' : '${km.toStringAsFixed(1)} كم';

/// وقت تقريبي بسرعة 25 كم/س في الزحمة
String etaTxt(double km) {
  final m = max(1, (km / 25 * 60).round() + 2);
  return m < 60 ? '$m دقيقة' : '${m ~/ 60} س ${m % 60} د';
}

LatLng? latLngOf(Map<String, dynamic>? d, [String prefix = '']) {
  if (d == null) return null;
  final a = d['${prefix}lat'] ?? d['${prefix}Lat'], b = d['${prefix}lng'] ?? d['${prefix}Lng'];
  if (a is num && b is num) return LatLng(a.toDouble(), b.toDouble());
  return null;
}

// ======================== أرقام وتواريخ ========================

double toD(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int toI(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

String money(dynamic v) {
  final d = toD(v);
  final s = d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  return '$s ج';
}

double commOf(Map<String, dynamic> o) => double.parse((toD(o['fee']) * kRate).toStringAsFixed(2));

DateTime? tsToDate(dynamic ts) {
  if (ts is Timestamp) return ts.toDate();
  if (ts is DateTime) return ts;
  return null;
}

String ago(dynamic ts) {
  final d = tsToDate(ts);
  if (d == null) return 'دلوقتي';
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'دلوقتي';
  if (m < 60) return 'من $m دقيقة';
  final h = m ~/ 60;
  if (h < 24) return 'من $h ساعة';
  final days = h ~/ 24;
  if (days < 30) return 'من $days يوم';
  return '${d.day}/${d.month}/${d.year}';
}

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

// ======================== المستويات والهدايا ========================

class Level {
  final String name, emoji;
  final int min;
  const Level(this.name, this.emoji, this.min);
}

const List<Level> kLevels = [
  Level('برونزي', '🥉', 0),
  Level('فضي', '🥈', 150),
  Level('ذهبي', '🥇', 400),
  Level('ماسي', '💎', 800),
];

Level levelOf(int points) {
  var l = kLevels.first;
  for (final x in kLevels) {
    if (points >= x.min) l = x;
  }
  return l;
}

Level? nextLevel(int points) {
  for (final x in kLevels) {
    if (x.min > points) return x;
  }
  return null;
}

class Gift {
  final String id, title, emoji;
  final int points;
  const Gift(this.id, this.title, this.emoji, this.points);
}

const List<Gift> kGifts = [
  Gift('card50', 'كارت شحن 50 ج', '📱', 100),
  Gift('fuel200', 'تفويل بنزين 200 ج', '⛽', 250),
  Gift('helmet', 'خوذة احترافية', '⛑️', 500),
  Gift('service', 'صيانة موتوسيكل', '🛠️', 900),
];

double ratingOf(Map<String, dynamic> c) {
  final n = toI(c['ratingCount']);
  return n == 0 ? 0 : toD(c['ratingSum']) / n;
}

String starsTxt(double r) {
  final n = r.round().clamp(0, 5);
  return '${'★' * n}${'☆' * (5 - n)}';
}

// ======================== حالات الأوردر ========================

const Map<String, String> kStatus = {
  'pending': 'مستني موافقة الكابتن',
  'accepted': 'الكابتن رايح يستلم',
  'picked': 'الكابتن استلم الأوردر',
  'onway': 'في الطريق للعميل',
  'arrived': 'الكابتن وصل للعميل',
  'delivered': 'تم التسليم',
  'rejected': 'الكابتن رفض',
  'cancelled': 'اتلغى',
};

const List<String> kActive = ['pending', 'accepted', 'picked', 'onway', 'arrived'];

Color statusColor(String s) {
  switch (s) {
    case 'delivered':
      return kGreen;
    case 'rejected':
    case 'cancelled':
      return kRed;
    case 'pending':
      return kOrange2;
    default:
      return kBlue;
  }
}

Widget statusPill(String s) => Pill(kStatus[s] ?? s, statusColor(s));

// ======================== الإعدادات ========================

class AppSettings {
  final double maxDue;
  final String insta, voda;
  AppSettings(Map<String, dynamic>? d)
      : maxDue = d == null || d['maxDue'] == null ? 150 : toD(d['maxDue']),
        insta = (d?['insta'] ?? kInstaPay).toString(),
        voda = (d?['voda'] ?? kVodaCash).toString();
}

Stream<AppSettings> settingsStream() => settingsRef.snapshots().map((s) => AppSettings(s.data()));

// ======================== الحسابات ========================

Future<FirebaseAuth> helperAuth() async {
  const name = 'orod-admin-helper';
  FirebaseApp app;
  try {
    app = Firebase.app(name);
  } catch (_) {
    app = await Firebase.initializeApp(name: name, options: orodFirebaseOptions);
  }
  return FirebaseAuth.instanceFor(app: app);
}

/// المدير بيعمل حساب كابتن أو مشروع من غير ما يخرج من حسابه
Future<String> adminCreateAccount(
    {required String role, required String phone, required String name, required String password, String extra = ''}) async {
  final helper = await helperAuth();
  final cred = await helper.createUserWithEmailAndPassword(email: phoneToEmail(phone), password: password);
  final id = cred.user!.uid;
  await helper.signOut();
  final batch = db.batch();
  batch.set(usersCol.doc(id), {
    'role': role,
    'phone': normPhone(phone),
    'name': name,
    'password': password,
    'disabled': false,
    'createdByAdmin': true,
    'createdAt': FieldValue.serverTimestamp(),
  });
  if (role == 'captain') {
    batch.set(captainsCol.doc(id), newCaptainDoc(name, normPhone(phone), extra.isEmpty ? 'موتوسيكل' : extra)..['verified'] = true);
  } else {
    batch.set(projectsCol.doc(id), newProjectDoc(name, normPhone(phone), name, extra));
  }
  await batch.commit();
  return id;
}

Map<String, dynamic> newCaptainDoc(String name, String phone, String vehicle) => {
      'name': name,
      'phone': phone,
      'vehicle': vehicle,
      'photo': '',
      'verified': false,
      'blocked': false,
      'online': false,
      'points': 0,
      'trips': 0,
      'ratingSum': 0,
      'ratingCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    };

Map<String, dynamic> newProjectDoc(String name, String phone, String owner, String type) => {
      'name': name,
      'owner': owner,
      'phone': phone,
      'type': type,
      'photo': '',
      'blocked': false,
      'favs': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    };

Future<void> changeAccountPassword(String userId, Map<String, dynamic> u, String newPass) async {
  final helper = await helperAuth();
  final cred = await helper.signInWithEmailAndPassword(
      email: phoneToEmail(u['phone'] ?? ''), password: (u['password'] ?? '').toString());
  await cred.user!.updatePassword(newPass);
  await helper.signOut();
  await usersCol.doc(userId).update({'password': newPass});
}

/// حذف نهائي (لو كلمة السر متسجلة) + حذف البروفايل
Future<void> deleteAccount(String userId) async {
  final u = (await usersCol.doc(userId).get()).data() ?? {};
  try {
    final helper = await helperAuth();
    final cred = await helper.signInWithEmailAndPassword(
        email: phoneToEmail(u['phone'] ?? ''), password: (u['password'] ?? '').toString());
    await cred.user!.delete();
  } catch (_) {}
  final batch = db.batch();
  batch.delete(usersCol.doc(userId));
  batch.delete(captainsCol.doc(userId));
  batch.delete(projectsCol.doc(userId));
  await batch.commit();
}

String authError(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-email':
        return 'رقم الموبايل أو كلمة السر غلط';
      case 'email-already-in-use':
        return 'الرقم ده متسجل قبل كده، ادخل بكلمة السر';
      case 'weak-password':
        return 'كلمة السر لازم تكون 6 حروف أو أرقام على الأقل';
      case 'network-request-failed':
        return 'مفيش إنترنت';
      case 'too-many-requests':
        return 'محاولات كتير، استنى شوية وجرّب تاني';
    }
    return e.message ?? e.code;
  }
  if (e is FirebaseException) {
    if (e.code == 'permission-denied') return 'مفيش صلاحية للعملية دي';
    return e.message ?? e.code;
  }
  return e.toString();
}

String randomCode() => (1000 + Random.secure().nextInt(9000)).toString();

// ======================== الصور ========================

Future<String?> pickImageB64(BuildContext context, {double maxWidth = 600, bool cameraFirst = false}) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: Icon(Icons.camera_alt_outlined),
          title: Text('صوّر بالكاميرا'),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
        ListTile(
          leading: Icon(Icons.photo_library_outlined),
          title: Text('اختار من المعرض'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (src == null) return null;
  final x = await ImagePicker().pickImage(source: src, maxWidth: maxWidth, maxHeight: maxWidth, imageQuality: 55);
  if (x == null) return null;
  return base64Encode(await x.readAsBytes());
}

final Map<int, Uint8List> _imgCache = {};

class B64Image extends StatelessWidget {
  final String? data;
  final double? width, height;
  final BoxFit fit;
  final String emoji;
  const B64Image(this.data, {super.key, this.width, this.height, this.fit = BoxFit.cover, this.emoji = '📷'});

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null || d.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: kPanel2,
        alignment: Alignment.center,
        child: Text(emoji, style: TextStyle(fontSize: (height ?? 40) * 0.45)),
      );
    }
    try {
      final bytes = _imgCache.putIfAbsent(Object.hash(d.length, d.hashCode), () => base64Decode(d));
      return Image.memory(bytes, width: width, height: height, fit: fit, gaplessPlayback: true);
    } catch (_) {
      return SizedBox(width: width, height: height);
    }
  }
}

class Avatar extends StatelessWidget {
  final String? photo;
  final String emoji;
  final double size;
  const Avatar(this.photo, {super.key, this.emoji = '🧑', this.size = 50});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(2),
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [kOrange2, kRed]),
            boxShadow: [BoxShadow(color: kOrange.withValues(alpha: .35), blurRadius: 10)]),
        child: ClipOval(child: B64Image(photo, width: size, height: size, emoji: emoji)),
      );
}

void showPhoto(BuildContext context, String b64) {
  showDialog(
    context: context,
    builder: (c) => Dialog(
      insetPadding: EdgeInsets.all(12),
      backgroundColor: Colors.black,
      child: InkWell(
        onTap: () => Navigator.pop(c),
        child: InteractiveViewer(child: B64Image(b64, fit: BoxFit.contain)),
      ),
    ),
  );
}

// ======================== واجهة مشتركة ========================

void toast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg, style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
    backgroundColor: error ? Color(0xFFB3203A) : kPanel2,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14), side: BorderSide(color: error ? kRed : kOrange)),
  ));
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'تأكيد', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: kRed) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(BuildContext context, String title,
    {String hint = '', String initial = '', TextInputType? type, int lines = 1}) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
          controller: c, autofocus: true, keyboardType: type, maxLines: lines, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text('تمام')),
      ],
    ),
  );
  return r;
}

/// أيقونة 3D: مربع بتدرّج وضل ولمعة
class Icon3D extends StatelessWidget {
  final String emoji;
  final List<Color> colors;
  final double size;
  const Icon3D(this.emoji, {super.key, this.colors = G3.or, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final r = size * 0.3;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateX(0.12),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: .45), offset: Offset(0, size * 0.12), blurRadius: 0, spreadRadius: -size * 0.04),
            BoxShadow(color: colors.last.withValues(alpha: .55), offset: Offset(0, size * 0.22), blurRadius: size * 0.4, spreadRadius: -size * 0.12),
          ],
        ),
        child: Stack(children: [
          Positioned(
            top: size * 0.06,
            left: size * 0.14,
            right: size * 0.14,
            height: size * 0.4,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(r * 0.8), bottom: Radius.circular(r * 2)),
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: .45), Colors.white.withValues(alpha: 0)]),
              ),
            ),
          ),
          Center(
            child: Text(emoji,
                style: TextStyle(fontSize: size * 0.5, shadows: [
                  Shadow(color: Colors.black.withValues(alpha: .4), offset: Offset(0, 3), blurRadius: 4)
                ])),
          ),
        ]),
      ),
    );
  }
}

/// كارت بخلفية متدرجة
class Box extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? border;
  final Gradient? gradient;
  final VoidCallback? onTap;
  const Box({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.border, this.gradient, this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 14),
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient ?? LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [kPanel2, kPanel]),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border ?? kLine, width: border == null ? 1 : 1.6),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .35), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: child,
    );
    if (onTap == null) return w;
    return GestureDetector(onTap: onTap, child: w);
  }
}

class BoxTitle extends StatelessWidget {
  final String text;
  final String? emoji;
  final Widget? trailing;
  const BoxTitle(this.text, {super.key, this.emoji, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Row(children: [
          if (emoji != null) ...[Text(emoji!, style: TextStyle(fontSize: 20)), SizedBox(width: 8)],
          Expanded(child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// زرار 3D برتقالي (أو بألوان تانية)
class Btn3D extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final List<Color> colors;
  final bool busy;
  final double fontSize;
  const Btn3D(this.label, {super.key, this.onTap, this.colors = const [kOrange2, kOrange, kRed], this.busy = false, this.fontSize = 16});
  @override
  State<Btn3D> createState() => _Btn3DState();
}

class _Btn3DState extends State<Btn3D> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final dis = widget.onTap == null || widget.busy;
    final shade = HSLColor.fromColor(widget.colors.last).withLightness(.25).toColor();
    return GestureDetector(
      onTapDown: dis ? null : (_) => setState(() => down = true),
      onTapUp: dis ? null : (_) => setState(() => down = false),
      onTapCancel: () => setState(() => down = false),
      onTap: dis ? null : widget.onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 90),
        transform: Matrix4.translationValues(0, down ? 4 : 0, 0),
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: dis ? [Color(0xFF3A3F66), Color(0xFF2B315C)] : widget.colors),
          boxShadow: dis
              ? []
              : [
                  BoxShadow(color: shade, offset: Offset(0, down ? 2 : 6), blurRadius: 0),
                  BoxShadow(color: widget.colors[widget.colors.length ~/ 2].withValues(alpha: .4), offset: Offset(0, 12), blurRadius: 20, spreadRadius: -6),
                ],
        ),
        alignment: Alignment.center,
        child: widget.busy
            ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : Text(widget.label,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: widget.fontSize)),
      ),
    );
  }
}

const List<Color> kBtnGreen = [Color(0xFF5FF0B0), Color(0xFF0FA86A)];
const List<Color> kBtnBlue = [Color(0xFF6FB4FF), Color(0xFF2B5CFF)];
const List<Color> kBtnRed = [Color(0xFFFF8A9A), Color(0xFFE0173A)];

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

class StatBox extends StatelessWidget {
  final String value, label;
  final Color? color;
  const StatBox(this.value, this.label, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(18), border: Border.all(color: kLine)),
        child: Column(children: [
          FittedBox(child: Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color ?? kTxt))),
          SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w600)),
        ]),
      );
}

Widget statsRow(List<Widget> items) => Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Row(
          children: [for (var i = 0; i < items.length; i++) ...[if (i > 0) SizedBox(width: 10), Expanded(child: items[i])]]),
    );

class KV extends StatelessWidget {
  final String k;
  final String v;
  final Color? color;
  const KV(this.k, this.v, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(k, style: TextStyle(color: kMuted, fontSize: 14)),
          SizedBox(width: 10),
          Expanded(
              child: Text(v,
                  textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color))),
        ]),
      );
}

class Header extends StatelessWidget {
  final String emoji, title, sub;
  final List<Color> colors;
  final Widget? trailing;
  const Header(this.emoji, this.title, this.sub, {super.key, this.colors = G3.or, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          Icon3D(emoji, colors: colors),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(sub, style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyView extends StatelessWidget {
  final String title;
  final String emoji;
  final String text;
  const EmptyView(this.title, {super.key, this.emoji = '📭', this.text = ''});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon3D(emoji, colors: G3.bl, size: 70),
          SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          if (text.isNotEmpty) ...[
            SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
          ],
        ]),
      );
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => Center(child: CircularProgressIndicator(color: kOrange));
}

class Note extends StatelessWidget {
  final String text;
  final Color color;
  const Note(this.text, {super.key, this.color = kOrange});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kDeep,
          borderRadius: BorderRadius.circular(14),
          border: BorderDirectional(start: BorderSide(color: color, width: 4)),
        ),
        child: Text(text, style: TextStyle(fontSize: 14, height: 1.5)),
      );
}

/// صف كابتن: صورة، اسم، تقييم، مستوى، مسافة
class CaptainTile extends StatelessWidget {
  final Map<String, dynamic> c;
  final double? km;
  final bool selected;
  final bool fav;
  final VoidCallback? onTap;
  final Widget? trailing;
  const CaptainTile(this.c, {super.key, this.km, this.selected = false, this.fav = false, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final r = ratingOf(c);
    final l = levelOf(toI(c['points']));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kDeep,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? kOrange : kLine, width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(color: kOrange.withValues(alpha: .25), blurRadius: 12)] : null,
        ),
        child: Row(children: [
          Avatar(c['photo'], size: 48),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                    child: Text((c['name'] ?? '').toString(),
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                if (c['verified'] == true) Text(' ✅', style: TextStyle(fontSize: 12)),
                if (fav) Text(' ⭐', style: TextStyle(fontSize: 12)),
              ]),
              Text('${starsTxt(r)}  ${r == 0 ? 'جديد' : r.toStringAsFixed(1)} · ${toI(c['trips'])} رحلة',
                  style: TextStyle(color: kGold, fontSize: 12)),
              Text('${l.emoji} ${l.name} · ${c['vehicle'] ?? ''}', style: TextStyle(color: kMuted, fontSize: 12)),
            ]),
          ),
          if (km != null)
            Column(children: [
              Text(km! < 1 ? '${(km! * 1000).round()}' : km!.toStringAsFixed(1),
                  style: TextStyle(color: kOrange2, fontWeight: FontWeight.w900, fontSize: 17)),
              Text(km! < 1 ? 'متر' : 'كم', style: TextStyle(color: kMuted, fontSize: 11)),
            ]),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

/// كارت أوردر صغير
class OrderTile extends StatelessWidget {
  final Map<String, dynamic> o;
  final VoidCallback? onTap;
  final bool forCaptain;
  const OrderTile(this.o, {super.key, this.onTap, this.forCaptain = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(18), border: Border.all(color: kLine)),
          child: Row(children: [
            Icon3D('📦', size: 40),
            SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('#${o['no'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w900)),
                  Spacer(),
                  statusPill((o['status'] ?? '').toString()),
                ]),
                SizedBox(height: 4),
                Text(
                    forCaptain
                        ? '🏪 ${o['projectName'] ?? ''} ← 🏠 ${o['custName'] ?? ''}'
                        : '🏠 ${o['custName'] ?? ''} · 🛵 ${o['captainName'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: kMuted, fontSize: 13)),
                Text('💵 ${money(o['fee'])} · عمولة ${money(commOf(o))} · ${ago(o['createdAt'])}',
                    style: TextStyle(color: kMuted, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      );
}

Widget sectionPad(List<Widget> children) =>
    Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Column(children: children));

/// مفتاح تشغيل/إيقاف
class Toggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const Toggle(this.value, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) => Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.white,
        activeTrackColor: kGreen,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: kLine,
      );
}
