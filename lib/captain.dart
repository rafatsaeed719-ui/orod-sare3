import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'common.dart';
import 'core.dart';
import 'map_view.dart';

// ======================== بث لوكيشن الكابتن ========================

class LocationPusher {
  static StreamSubscription<Position>? _sub;
  static DateTime _last = DateTime(2000);
  static bool get running => _sub != null;

  static Future<bool> start(BuildContext context) async {
    if (_sub != null) return true;
    final first = await myLocation(context);
    if (first == null) return false;
    await _push(first.latitude, first.longitude, force: true);
    LocationSettings settings;
    try {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        intervalDuration: Duration(seconds: 10),
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'أورد على السريع',
          notificationText: 'إنت أونلاين.. أصحاب المشاريع شايفين مكانك 🛵',
          enableWakeLock: true,
        ),
      );
    } catch (_) {
      settings = LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20);
    }
    try {
      _sub = Geolocator.getPositionStream(locationSettings: settings)
          .listen((p) => _push(p.latitude, p.longitude), onError: (_) {});
    } catch (_) {
      _sub = Geolocator.getPositionStream(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20))
          .listen((p) => _push(p.latitude, p.longitude), onError: (_) {});
    }
    return true;
  }

  static Future<void> _push(double lat, double lng, {bool force = false}) async {
    if (!force && DateTime.now().difference(_last).inSeconds < 8) return;
    _last = DateTime.now();
    try {
      await captainsCol.doc(uid).update({'lat': lat, 'lng': lng, 'locAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}

double dueOf(List<QueryDocumentSnapshot<Map<String, dynamic>>> orders) => double.parse(orders
    .where((d) => d.data()['status'] == 'delivered' && d.data()['commPaid'] == 'no')
    .fold<double>(0, (s, d) => s + commOf(d.data()))
    .toStringAsFixed(2));

// ======================== الرئيسية ========================

class CaptainHome extends StatefulWidget {
  const CaptainHome({super.key});
  @override
  State<CaptainHome> createState() => _CaptainHomeState();
}

class _CaptainHomeState extends State<CaptainHome> {
  int tab = 0;
  bool started = false;
  final Set<String> seen = {};
  bool firstLoad = true;
  late final meStream = captainsCol.doc(uid).snapshots();
  late final ordersStream = ordersWhere('captainUid', uid);
  late final settings$ = settingsStream();
  late final unread = unreadMessages('captains');

  void _autoStart(Map<String, dynamic> c) {
    if (started) return;
    started = true;
    if (c['online'] == true && c['verified'] == true && c['blocked'] != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => LocationPusher.start(context));
    }
  }

  void _checkNew(List<QueryDocumentSnapshot<Map<String, dynamic>>> orders) {
    final pending = orders.where((d) => d.data()['status'] == 'pending').map((d) => d.id).toSet();
    final fresh = pending.difference(seen);
    seen.addAll(pending);
    if (firstLoad) {
      firstLoad = false;
      if (pending.isEmpty) return;
    }
    if (fresh.isNotEmpty) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      Future.delayed(Duration(milliseconds: 400), HapticFeedback.heavyImpact);
      if (tab != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => tab = 0);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: meStream,
      builder: (context, snap) {
        if (!snap.hasData) return Scaffold(body: Loading());
        final c = snap.data!.data();
        if (c == null) return Scaffold(body: Loading());
        _autoStart(c);
        return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: ordersStream,
          builder: (context, os) {
            final orders = os.data ?? [];
            if (os.hasData) _checkNew(orders);
            return StreamBuilder<AppSettings>(
              stream: settings$,
              builder: (context, ss) {
                final settings = ss.data ?? AppSettings(null);
                final pages = [
                  _CaptainMain(c: c, orders: orders, settings: settings, openTab: (i) => setState(() => tab = i)),
                  WalletScreen(c: c, orders: orders, settings: settings),
                  GiftsScreen(c: c),
                  MessagesScreen('captains'),
                  CaptainProfile(c: c, orders: orders),
                ];
                return Scaffold(
                  body: SafeArea(child: pages[tab]),
                  floatingActionButton: tab == 0 ? _SosButton(c: c) : null,
                  floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
                  bottomNavigationBar: StreamBuilder<int>(
                    stream: unread,
                    builder: (context, u) => OrodNav(
                      index: tab,
                      onTap: (i) => setState(() => tab = i),
                      badges: {
                        0: orders.where((d) => d.data()['status'] == 'pending').length,
                        3: tab == 3 ? 0 : (u.data ?? 0),
                      },
                      items: [('🏠', 'الرئيسية'), ('💸', 'محفظتي'), ('🎁', 'الهدايا'), ('📢', 'الرسايل'), ('👤', 'حسابي')],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CaptainMain extends StatefulWidget {
  final Map<String, dynamic> c;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> orders;
  final AppSettings settings;
  final ValueChanged<int> openTab;
  const _CaptainMain({required this.c, required this.orders, required this.settings, required this.openTab});
  @override
  State<_CaptainMain> createState() => _CaptainMainState();
}

class _CaptainMainState extends State<_CaptainMain> {
  bool busy = false;

  Future<void> _toggle(bool on) async {
    final c = widget.c;
    if (on) {
      if (c['blocked'] == true) return toast(context, 'حسابك موقوف.. كلّم الإدارة', error: true);
      if (c['verified'] != true) {
        return toast(context, 'لازم حسابك يتوثق الأول.. ارفع صورة البطاقة من «حسابي»', error: true);
      }
      final due = dueOf(widget.orders);
      if (due > widget.settings.maxDue) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('💸 حوّل العمولة الأول'),
            content: Text(
                'عليك عمولة ${money(due)} وده أكتر من الحد المسموح (${money(widget.settings.maxDue)}).\nحوّلها من «محفظتي» وبعد ما الإدارة تأكد تقدر تشتغل تاني.'),
            actions: [
              FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.openTab(1);
                  },
                  child: Text('افتح المحفظة')),
            ],
          ),
        );
        return;
      }
    }
    setState(() => busy = true);
    try {
      if (on) {
        final ok = await LocationPusher.start(context);
        if (!ok) return;
        await captainsCol.doc(uid).update({'online': true});
        if (mounted) toast(context, '🟢 إنت أونلاين.. استنى الأوردرات');
      } else {
        await LocationPusher.stop();
        await captainsCol.doc(uid).update({'online': false});
      }
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _accept(String id) async {
    await ordersCol.doc(id).update({'status': 'accepted', 'updatedAt': FieldValue.serverTimestamp()});
    if (!mounted) return;
    toast(context, '✅ قبلت الأوردر.. يلا على المحل');
    Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(id)));
  }

  Future<void> _reject(String id) async {
    if (!await confirm(context, 'رفض الأوردر', 'متأكد إنك عاوز ترفض الأوردر ده؟', ok: 'رفض', danger: true)) return;
    await ordersCol.doc(id).update({'status': 'rejected', 'updatedAt': FieldValue.serverTimestamp()});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final orders = widget.orders;
    final pending = orders.where((d) => d.data()['status'] == 'pending').toList();
    final active = orders.where((d) => ['accepted', 'picked', 'onway', 'arrived'].contains(d.data()['status'])).toList();
    final done = orders.where((d) => d.data()['status'] == 'delivered').toList();
    final now = DateTime.now();
    final today = done.where((d) {
      final t = tsToDate(d.data()['updatedAt']) ?? tsToDate(d.data()['createdAt']);
      return t != null && sameDay(t, now);
    });
    final due = dueOf(orders);
    final pts = toI(c['points']);
    final l = levelOf(pts), nl = nextLevel(pts);
    final me = latLngOf(c);
    return ListView(children: [
      Header('🛵', 'أهلاً يا ${(c['name'] ?? '').toString().split(' ').first}', '${l.emoji} كابتن ${l.name}',
          colors: G3.gr, trailing: Avatar(c['photo'], size: 44)),
      sectionPad([
        Box(
          border: c['online'] == true ? kGreen : null,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['online'] == true ? '🟢 متاح لاستقبال أوردرات' : '⚫ مش متاح دلوقتي',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(
                    c['blocked'] == true
                        ? '⛔ حسابك موقوف'
                        : c['verified'] == true
                            ? 'حسابك موثق ✅'
                            : '⚠️ ارفع البطاقة من «حسابي» عشان تتوثق',
                    style: TextStyle(color: kMuted, fontSize: 13)),
              ]),
            ),
            busy ? SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2)) : Toggle(c['online'] == true, _toggle),
          ]),
        ),
        for (final d in pending) _requestCard(d, me),
        for (final d in active)
          Box(
            border: kBlue,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(d.id))),
            child: Row(children: [
              Icon3D('🚚', colors: G3.bl, size: 44),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('#${d.data()['no']}', style: TextStyle(fontWeight: FontWeight.w900)),
                    Spacer(),
                    statusPill(d.data()['status']),
                  ]),
                  Text('🏪 ${d.data()['projectName']} ← 🏠 ${d.data()['custName']}', style: TextStyle(color: kMuted, fontSize: 13)),
                  Text('افتح الرحلة 🧭', style: TextStyle(color: kOrange2, fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        statsRow([
          StatBox('${today.length}', 'رحلات النهارده'),
          StatBox(money(today.fold<double>(0, (s, d) => s + toD(d.data()['fee']))), 'كسبت النهارده', color: kGreen),
          StatBox(money(due), 'عمولة عليك', color: kOrange2),
        ]),
        Box(
          onTap: () => widget.openTab(2),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BoxTitle('مستواك ونقطك', emoji: '🏆', trailing: Pill('${l.emoji} ${l.name}', kGold)),
            Text('$pts نقطة', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kGold)),
            if (nl != null) ...[
              SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (pts - l.min) / (nl.min - l.min),
                  minHeight: 10,
                  backgroundColor: kDeep,
                  valueColor: AlwaysStoppedAnimation(kOrange),
                ),
              ),
              SizedBox(height: 6),
              Text('فاضلك ${nl.min - pts} نقطة للمستوى ${nl.emoji} ${nl.name}', style: TextStyle(color: kMuted, fontSize: 13)),
            ] else
              Text('وصلت لأعلى مستوى 💎', style: TextStyle(color: kMuted)),
          ]),
        ),
        LatestMessage('captains', onOpen: () => widget.openTab(3)),
        SizedBox(height: 70),
      ]),
    ]);
  }

  Widget _requestCard(QueryDocumentSnapshot<Map<String, dynamic>> d, LatLng? me) {
    final o = d.data();
    final pick = LatLng(toD(o['pickLat']), toD(o['pickLng']));
    final drop = LatLng(toD(o['dropLat']), toD(o['dropLng']));
    final toPick = me == null ? 0.0 : kmBetween(me.latitude, me.longitude, pick.latitude, pick.longitude);
    final trip = kmBetween(pick.latitude, pick.longitude, drop.latitude, drop.longitude);
    return Box(
      border: kOrange,
      child: Column(children: [
        BoxTitle('أوردر جديد ليك!', emoji: '🔔', trailing: Text(ago(o['createdAt']), style: TextStyle(color: kMuted, fontSize: 12))),
        OrodMap(
          fit: true,
          height: 180,
          route: [if (me != null) me, pick, drop],
          pins: [
            if (me != null) MapPin(me, '🛵', color: kOrange, glow: true),
            MapPin(pick, '🏪', color: kPurple),
            MapPin(drop, '🏠', color: kRed),
          ],
        ),
        SizedBox(height: 10),
        KV('من', '${o['projectName']}'),
        if (me != null) KV('لحد المحل', kmTxt(toPick)),
        KV('من المحل للعميل', kmTxt(trip)),
        KV('التوصيلة', money(o['fee']), color: kGreen),
        if (o['cod'] == true) KV('هتحصّل من العميل', money(o['value']), color: kOrange2),
        if ((o['note'] ?? '').toString().isNotEmpty) Note('📝 ${o['note']}'),
        SizedBox(height: 8),
        Row(children: [
          Expanded(flex: 2, child: Btn3D('قبول ✅', colors: kBtnGreen, onTap: () => _accept(d.id))),
          SizedBox(width: 10),
          Expanded(child: Btn3D('رفض', colors: kBtnRed, onTap: () => _reject(d.id))),
        ]),
      ]),
    );
  }
}

class _SosButton extends StatelessWidget {
  final Map<String, dynamic> c;
  const _SosButton({required this.c});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          if (!await confirm(context, '🆘 طوارئ', 'هنبعت مكانك للإدارة فوراً عشان تكلمك. متأكد؟', ok: 'ابعت', danger: true)) {
            return;
          }
          final p = await myLocation(context) ?? latLngOf(c);
          await sosCol.add({
            'captainUid': uid,
            'name': c['name'] ?? '',
            'phone': c['phone'] ?? '',
            if (p != null) 'lat': p.latitude,
            if (p != null) 'lng': p.longitude,
            'status': 'open',
            'createdAt': FieldValue.serverTimestamp(),
          });
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('🆘 اتبعت للإدارة'),
                content: Text('هنكلمك خلال دقايق.. خليك في مكان آمن.'),
                actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text('تمام'))],
              ),
            );
          }
        },
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFFF8A9A), Color(0xFFE0173A)]),
            boxShadow: [
              BoxShadow(color: kRed.withValues(alpha: .35), spreadRadius: 6),
              BoxShadow(color: Colors.black54, blurRadius: 14, offset: Offset(0, 6)),
            ],
          ),
          alignment: Alignment.center,
          child: Text('SOS', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
        ),
      );
}

// ======================== الرحلة ========================

class TripScreen extends StatefulWidget {
  final String id;
  const TripScreen(this.id, {super.key});
  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final otp = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    if (!LocationPusher.running) {
      WidgetsBinding.instance.addPostFrameCallback((_) => LocationPusher.start(context));
    }
  }

  Future<void> _set(String status) async {
    setState(() => busy = true);
    try {
      await ordersCol.doc(widget.id).update({'status': status, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _deliver() async {
    final code = otp.text.trim();
    if (code.length != 4) return toast(context, 'اكتب الكود اللي مع العميل (4 أرقام)', error: true);
    setState(() => busy = true);
    try {
      await ordersCol.doc(widget.id).update({
        'status': 'delivered',
        'otpIn': code,
        'deliveredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, '❌ الكود غلط.. اتأكد من العميل', error: true);
      }
      return;
    }
    try {
      await captainsCol.doc(uid).update({'trips': FieldValue.increment(1), 'points': FieldValue.increment(10)});
    } catch (_) {}
    if (mounted) {
      setState(() => busy = false);
      HapticFeedback.heavyImpact();
      toast(context, '🎉 تم التسليم.. كسبت 10 نقط');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ordersCol.doc(widget.id).snapshots(),
      builder: (context, snap) {
        final o = snap.data?.data();
        if (snap.hasError) {
          return Scaffold(appBar: AppBar(), body: EmptyView('الأوردر ده مبقاش معاك', emoji: '🚫'));
        }
        if (o == null) return Scaffold(appBar: AppBar(), body: Loading());
        final st = (o['status'] ?? '').toString();
        final pick = LatLng(toD(o['pickLat']), toD(o['pickLng']));
        final drop = LatLng(toD(o['dropLat']), toD(o['dropLng']));
        final toPick = st == 'accepted' || st == 'pending';
        final target = toPick ? pick : drop;
        return Scaffold(
          appBar: AppBar(title: Text('رحلة #${o['no']}')),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: captainsCol.doc(uid).snapshots(),
            builder: (context, cs) {
              final me = latLngOf(cs.data?.data());
              return ListView(padding: EdgeInsets.all(16), children: [
                OrodMap(
                  fit: true,
                  height: 260,
                  hint: st == 'delivered' ? 'تم التسليم ✅' : (toPick ? '🏪 رايح للمحل' : '🏠 رايح للعميل'),
                  route: [if (me != null && st != 'delivered') me, target],
                  pins: [
                    MapPin(pick, '🏪', color: kPurple),
                    MapPin(drop, '🏠', color: kRed),
                    if (me != null && st != 'delivered') MapPin(me, '🛵', color: kOrange, size: 40, glow: true),
                  ],
                ),
                SizedBox(height: 12),
                if (st != 'delivered' && st != 'cancelled')
                  Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Btn3D(toPick ? '🗺️ امشي باللوكيشن للمحل' : '🗺️ امشي باللوكيشن للعميل',
                        colors: kBtnBlue, onTap: () => navigateTo(target.latitude, target.longitude)),
                  ),
                Box(child: Column(children: [
                  _contact('🏪', 'الاستلام من', '${o['projectName']}', o['projectPhone'] ?? ''),
                  Divider(color: kLine),
                  _contact('🏠', 'التسليم لـ', '${o['custName']}', o['custPhone'] ?? ''),
                  if ((o['addr'] ?? '').toString().isNotEmpty) Note('📍 ${o['addr']}', color: kBlue),
                  if (o['cod'] == true) Note('💵 حصّل من العميل: ${money(o['value'])}', color: kGreen),
                  if ((o['note'] ?? '').toString().isNotEmpty) Note('📝 ${o['note']}'),
                  KV('التوصيلة بتاعتك', money(o['fee']), color: kGreen),
                  KV('عمولة التطبيق 5%', money(commOf(o)), color: kOrange2),
                ])),
                if (st == 'cancelled') Box(border: kRed, child: Text('الأوردر ده اتلغى من صاحب المشروع', textAlign: TextAlign.center)),
                if (st == 'accepted') Btn3D('📦 وصلت واستلمت الأوردر', busy: busy, onTap: () => _set('picked')),
                if (st == 'picked') Btn3D('🚀 ابدأ التوصيل للعميل', busy: busy, onTap: () => _set('onway')),
                if (st == 'onway') Btn3D('🏠 وصلت للعميل', busy: busy, onTap: () => _set('arrived')),
                if (st == 'arrived')
                  Box(
                    border: kGold,
                    child: Column(children: [
                      BoxTitle('اطلب كود التسليم من العميل', emoji: '🔐'),
                      TextField(
                        controller: otp,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 12, color: kGold),
                        decoration: InputDecoration(hintText: '____', counterText: ''),
                      ),
                      SizedBox(height: 10),
                      Btn3D('تأكيد التسليم ✅', colors: kBtnGreen, busy: busy, onTap: _deliver),
                    ]),
                  ),
                if (st == 'delivered')
                  Box(
                    border: kGreen,
                    child: Column(children: [
                      Icon3D('🎉', colors: G3.gr, size: 76),
                      SizedBox(height: 12),
                      Text('برافو! كسبت ${money(o['fee'])} + 10 نقط', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      Text('عمولة التطبيق: ${money(commOf(o))}', style: TextStyle(color: kMuted)),
                      if (toI(o['rating']) > 0) ...[
                        SizedBox(height: 8),
                        Text(starsTxt(toD(o['rating'])), style: TextStyle(color: kGold, fontSize: 22)),
                        if ((o['ratingNote'] ?? '').toString().isNotEmpty) Text('"${o['ratingNote']}"', style: TextStyle(color: kMuted)),
                      ],
                    ]),
                  ),
                SizedBox(height: 10),
                Box(child: OrderTimeline(st)),
              ]);
            },
          ),
        );
      },
    );
  }

  Widget _contact(String emoji, String label, String name, String phone) => Row(children: [
        Text(emoji, style: TextStyle(fontSize: 24)),
        SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: kMuted, fontSize: 12)),
            Text(name, style: TextStyle(fontWeight: FontWeight.w800)),
            Text(phone, style: TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
        IconButton.filledTonal(onPressed: () => callPhone(phone), icon: Icon(Icons.call)),
        SizedBox(width: 4),
        IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: kGreen),
            onPressed: () => openWhatsApp(phone, 'أهلاً، أنا كابتن التوصيل من «أورد على السريع» 🛵'),
            icon: Icon(Icons.chat)),
      ]);
}

// ======================== المحفظة ========================

class WalletScreen extends StatefulWidget {
  final Map<String, dynamic> c;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> orders;
  final AppSettings settings;
  const WalletScreen({super.key, required this.c, required this.orders, required this.settings});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  String? shot;
  String method = 'انستا باي';
  bool busy = false;

  Future<void> _pay() async {
    final unpaid = widget.orders.where((d) => d.data()['status'] == 'delivered' && d.data()['commPaid'] == 'no').toList();
    if (unpaid.isEmpty) return;
    if (shot == null) return toast(context, 'ارفع صورة التحويل الأول', error: true);
    setState(() => busy = true);
    try {
      final b = db.batch();
      b.set(paymentsCol.doc(), {
        'captainUid': uid,
        'captainName': widget.c['name'] ?? '',
        'amount': dueOf(widget.orders),
        'method': method,
        'img': shot,
        'orderIds': unpaid.map((d) => d.id).toList(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      for (final d in unpaid) {
        b.update(d.reference, {'commPaid': 'pending'});
      }
      await b.commit();
      if (mounted) {
        setState(() => shot = null);
        toast(context, '📨 اتبعت للإدارة.. هتتأكد قريب وتاخد 20 نقطة');
      }
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _num(String label, String n, Color color) => Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: kDeep, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .6))),
        child: Row(children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w800)),
          Spacer(),
          Text(n, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
          IconButton(
              icon: Icon(Icons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: n));
                toast(context, '📋 اتنسخ $n');
              }),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final orders = widget.orders;
    final due = dueOf(orders);
    final pendingPay = orders.where((d) => d.data()['commPaid'] == 'pending').fold<double>(0, (s, d) => s + commOf(d.data()));
    final done = orders.where((d) => d.data()['status'] == 'delivered').toList();
    final earned = done.fold<double>(0, (s, d) => s + toD(d.data()['fee']));
    return ListView(children: [
      Header('💸', 'محفظتي', 'العمولة الثابتة 5% بس', colors: G3.gd),
      sectionPad([
        statsRow([
          StatBox('${done.length}', 'رحلة'),
          StatBox(money(earned), 'إجمالي كسبك', color: kGreen),
          StatBox(money(done.fold<double>(0, (s, d) => s + commOf(d.data()))), 'إجمالي العمولة'),
        ]),
        Box(
          border: due > 0 ? kOrange : null,
          child: Column(children: [
            Text('العمولة المستحقة عليك', style: TextStyle(color: kMuted)),
            Text(money(due), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: kOrange2)),
            if (pendingPay > 0) Pill('⏳ ${money(pendingPay)} مستني تأكيد الإدارة', kOrange2),
            if (due > widget.settings.maxDue)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Note('⚠️ عديت الحد المسموح (${money(widget.settings.maxDue)}).. مش هتقدر تبقى أونلاين غير لما تحوّل', color: kRed),
              ),
            SizedBox(height: 12),
            _num('🟣 انستا باي', widget.settings.insta, kPurple),
            _num('🔴 فودافون كاش', widget.settings.voda, kRed),
            Text('باسم: $kPayName', style: TextStyle(color: kMuted)),
            if (due > 0) ...[
              SizedBox(height: 14),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'انستا باي', label: Text('انستا باي')),
                  ButtonSegment(value: 'فودافون كاش', label: Text('فودافون كاش')),
                ],
                selected: {method},
                onSelectionChanged: (s) => setState(() => method = s.first),
              ),
              SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final img = await pickImageB64(context, maxWidth: 900);
                  if (img != null) setState(() => shot = img);
                },
                child: Container(
                  height: 130,
                  width: double.infinity,
                  decoration: BoxDecoration(
                      color: kDeep, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine, width: 2)),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: shot == null
                      ? Text('📸 ارفع سكرين التحويل', style: TextStyle(color: kMuted, fontWeight: FontWeight.w700))
                      : B64Image(shot, fit: BoxFit.contain, height: 130),
                ),
              ),
              SizedBox(height: 12),
              Btn3D('✅ حوّلت ${money(due)}', busy: busy, onTap: _pay),
            ],
          ]),
        ),
        Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BoxTitle('سجل الرحلات', emoji: '📜'),
          if (done.isEmpty) Text('لسه مفيش رحلات', style: TextStyle(color: kMuted)),
          for (final d in done.take(50))
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('#${d.data()['no']} · ${d.data()['projectName']}', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(ago(d.data()['createdAt']), style: TextStyle(color: kMuted, fontSize: 12)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('+${money(d.data()['fee'])}', style: TextStyle(color: kGreen, fontWeight: FontWeight.w900)),
                  Text(
                      'عمولة ${money(commOf(d.data()))} ${d.data()['commPaid'] == 'yes' ? '✅' : d.data()['commPaid'] == 'pending' ? '⏳' : '❗'}',
                      style: TextStyle(color: kMuted, fontSize: 12)),
                ]),
              ]),
            ),
        ])),
        SizedBox(height: 20),
      ]),
    ]);
  }
}

// ======================== الهدايا ========================

class GiftsScreen extends StatelessWidget {
  final Map<String, dynamic> c;
  const GiftsScreen({super.key, required this.c});

  Future<void> _redeem(BuildContext context, Gift g) async {
    if (!await confirm(context, '${g.emoji} ${g.title}', 'هيتخصم ${g.points} نقطة والإدارة هتكلمك تسلّمك الهدية. موافق؟',
        ok: 'استبدل')) {
      return;
    }
    try {
      final b = db.batch();
      b.update(captainsCol.doc(uid), {'points': FieldValue.increment(-g.points)});
      b.set(redeemsCol.doc(), {
        'captainUid': uid,
        'captainName': c['name'] ?? '',
        'captainPhone': c['phone'] ?? '',
        'gift': g.title,
        'points': g.points,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await b.commit();
      if (context.mounted) toast(context, '🎁 طلبك اتبعت للإدارة');
    } catch (e) {
      if (context.mounted) toast(context, authError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pts = toI(c['points']);
    return ListView(children: [
      Header('🎁', 'الهدايا والمكافآت', '$pts نقطة', colors: G3.rd),
      sectionPad([
        Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BoxTitle('إزاي تكسب نقط؟', emoji: '💡'),
          Text('✅ كل أوردر بتسلّمه = 10 نقط\n⭐ تقييم 5 نجوم = 15 نقطة بونص\n💸 تحويل العمولة = 20 نقطة\n🏆 كابتن الأسبوع = هدية نقط من الإدارة',
              style: TextStyle(height: 1.9, color: kMuted)),
        ])),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .95,
          children: [
            for (final g in kGifts)
              Opacity(
                opacity: pts >= g.points ? 1 : .45,
                child: Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(18), border: Border.all(color: kLine)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon3D(g.emoji, colors: G3.rd),
                    SizedBox(height: 10),
                    Text(g.title, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    Text('${g.points} نقطة', style: TextStyle(color: kGold, fontSize: 12)),
                    SizedBox(height: 6),
                    pts >= g.points
                        ? FilledButton(
                            style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact, padding: EdgeInsets.symmetric(horizontal: 16)),
                            onPressed: () => _redeem(context, g),
                            child: Text('استبدل'))
                        : Text('🔒', style: TextStyle(fontSize: 18)),
                  ]),
                ),
              ),
          ],
        ),
        SizedBox(height: 14),
        Box(child: Column(children: [
          BoxTitle('أحسن الكباتن', emoji: '🏆'),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: captainsCol.orderBy('points', descending: true).limit(5).snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              return Column(children: [
                for (var i = 0; i < docs.length; i++)
                  CaptainTile(docs[i].data(),
                      trailing: Padding(
                        padding: EdgeInsetsDirectional.only(start: 8),
                        child: Text(i < 3 ? ['🥇', '🥈', '🥉'][i] : '${i + 1}', style: TextStyle(fontSize: 24)),
                      )),
              ]);
            },
          ),
        ])),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: redeemsCol.where('captainUid', isEqualTo: uid).snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return SizedBox();
            return Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              BoxTitle('طلبات الهدايا بتاعتي', emoji: '📦'),
              for (final d in docs)
                KV('${d.data()['gift']}',
                    d.data()['status'] == 'done' ? 'اتسلمت ✅' : d.data()['status'] == 'rejected' ? 'اترفضت' : 'قيد التجهيز ⏳'),
            ]));
          },
        ),
        SizedBox(height: 20),
      ]),
    ]);
  }
}

// ======================== حسابي ========================

class CaptainProfile extends StatelessWidget {
  final Map<String, dynamic> c;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> orders;
  const CaptainProfile({super.key, required this.c, required this.orders});

  Future<void> _edit(BuildContext context, String field, String title) async {
    final v = await askText(context, title, initial: (c[field] ?? '').toString());
    if (v == null || v.isEmpty) return;
    await captainsCol.doc(uid).update({field: v});
    if (field == 'name') await usersCol.doc(uid).update({'name': v});
  }

  Future<void> _uploadId(BuildContext context, String field) async {
    final img = await pickImageB64(context, maxWidth: 900);
    if (img == null) return;
    await usersCol.doc(uid).update({field: img});
    await captainsCol.doc(uid).update({'idSent': true});
    if (context.mounted) toast(context, '📨 اتبعتت للمراجعة');
  }

  @override
  Widget build(BuildContext context) {
    final notes = orders.where((d) => (d.data()['ratingNote'] ?? '').toString().isNotEmpty).toList();
    final r = ratingOf(c);
    return ListView(children: [
      Header('👤', 'حسابي', 'بروفايل الكابتن', colors: G3.gr),
      sectionPad([
        Box(
          child: Column(children: [
            GestureDetector(
              onTap: () async {
                final img = await pickImageB64(context, maxWidth: 400);
                if (img == null) return;
                await captainsCol.doc(uid).update({'photo': img});
                if (context.mounted) toast(context, '✅ الصورة اتحفظت');
              },
              child: Stack(children: [
                Avatar(c['photo'], size: 110),
                Positioned(
                    bottom: 0,
                    left: 0,
                    child: CircleAvatar(radius: 16, backgroundColor: kOrange, child: Icon(Icons.camera_alt, size: 16, color: Colors.white))),
              ]),
            ),
            SizedBox(height: 10),
            Text('${c['name'] ?? ''} ${c['verified'] == true ? '✅' : ''}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text('${starsTxt(r)}  ${r == 0 ? 'لسه مفيش تقييم' : '${r.toStringAsFixed(1)} من ${toI(c['ratingCount'])} تقييم'}',
                style: TextStyle(color: kGold)),
            Text('${c['phone'] ?? ''}', style: TextStyle(color: kMuted)),
          ]),
        ),
        Box(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            ListTile(
                leading: Text('🧑', style: TextStyle(fontSize: 22)),
                title: Text('الاسم'),
                subtitle: Text((c['name'] ?? '').toString()),
                trailing: Icon(Icons.edit_outlined),
                onTap: () => _edit(context, 'name', 'اسمك')),
            ListTile(
                leading: Text('🛵', style: TextStyle(fontSize: 22)),
                title: Text('وسيلة التوصيل'),
                subtitle: Text((c['vehicle'] ?? '').toString()),
                trailing: Icon(Icons.edit_outlined),
                onTap: () => _edit(context, 'vehicle', 'وسيلة التوصيل')),
          ]),
        ),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: usersCol.doc(uid).snapshots(),
          builder: (context, us) {
            final u = us.data?.data() ?? {};
            return Box(
              border: c['verified'] == true ? null : kOrange,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                BoxTitle('توثيق الحساب (البطاقة)', emoji: '🪪',
                    trailing: c['verified'] == true
                        ? Pill('موثق ✅', kGreen)
                        : c['idSent'] == true
                            ? Pill('قيد المراجعة', kOrange2)
                            : Pill('مش موثق', kRed)),
                if (c['verified'] != true)
                  Text('ارفع صورة البطاقة وش وضهر عشان الإدارة توثّق حسابك وتبدأ تستقبل أوردرات',
                      style: TextStyle(color: kMuted, fontSize: 13)),
                SizedBox(height: 10),
                Row(children: [
                  for (final f in [('idFront', '🪪 وش البطاقة'), ('idBack', '🔄 ضهر البطاقة')]) ...[
                    if (f.$1 == 'idBack') SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: c['verified'] == true ? null : () => _uploadId(context, f.$1),
                        child: Container(
                          height: 100,
                          decoration: BoxDecoration(
                              color: kDeep, borderRadius: BorderRadius.circular(14), border: Border.all(color: kLine, width: 2)),
                          clipBehavior: Clip.antiAlias,
                          alignment: Alignment.center,
                          child: (u[f.$1] ?? '').toString().isEmpty
                              ? Text(f.$2, style: TextStyle(color: kMuted, fontWeight: FontWeight.w700))
                              : B64Image(u[f.$1], height: 100, width: double.infinity),
                        ),
                      ),
                    ),
                  ],
                ]),
              ]),
            );
          },
        ),
        if (notes.isNotEmpty)
          Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BoxTitle('ملاحظات أصحاب المشاريع عليك', emoji: '💬'),
            for (final d in notes.take(20))
              Note('${starsTxt(toD(d.data()['rating']))}  "${d.data()['ratingNote']}" — ${d.data()['projectName']}', color: kGold),
          ])),
        Btn3D('🚪 خروج', colors: [kPanel2, kLine], onTap: () async {
          if (!await confirm(context, 'خروج', 'متأكد إنك عاوز تخرج؟ هتبقى مش متاح للأوردرات.', ok: 'خروج')) return;
          await LocationPusher.stop();
          try {
            await captainsCol.doc(uid).update({'online': false});
          } catch (_) {}
          await auth.signOut();
        }),
        SizedBox(height: 30),
      ]),
    ]);
  }
}
