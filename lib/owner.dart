import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'common.dart';
import 'core.dart';
import 'map_view.dart';

/// الكباتن المتاحين دلوقتي (أونلاين + موثقين + مش موقوفين + لوكيشن حديث)
Stream<List<Map<String, dynamic>>> availableCaptains() =>
    captainsCol.where('online', isEqualTo: true).snapshots().map((s) {
      final now = DateTime.now();
      return s.docs
          .map((d) => {...d.data(), 'id': d.id})
          .where((c) =>
              c['verified'] == true &&
              c['blocked'] != true &&
              latLngOf(c) != null &&
              now.difference(tsToDate(c['locAt']) ?? DateTime(2000)).inHours < 3)
          .toList();
    });

List<Map<String, dynamic>> sortByDistance(List<Map<String, dynamic>> caps, LatLng from, List favs) {
  for (final c in caps) {
    final p = latLngOf(c)!;
    c['_km'] = kmBetween(from.latitude, from.longitude, p.latitude, p.longitude);
  }
  caps.sort((a, b) {
    final fa = favs.contains(a['id']) ? 0 : 1, fb = favs.contains(b['id']) ? 0 : 1;
    if (fa != fb) return fa - fb;
    return (a['_km'] as double).compareTo(b['_km'] as double);
  });
  return caps;
}

class OwnerHome extends StatefulWidget {
  const OwnerHome({super.key});
  @override
  State<OwnerHome> createState() => _OwnerHomeState();
}

class _OwnerHomeState extends State<OwnerHome> {
  int tab = 0;
  late final me = projectsCol.doc(uid).snapshots();
  late final unread = unreadMessages('owners');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: me,
      builder: (context, snap) {
        if (!snap.hasData) return Scaffold(body: Loading());
        final p = snap.data!.data();
        if (p == null) return Scaffold(body: Loading());
        final pages = [
          _OwnerMain(p: p, openMsgs: () => setState(() => tab = 2)),
          _OwnerOrders(),
          MessagesScreen('owners'),
          OwnerProfile(p: p),
        ];
        return Scaffold(
          body: SafeArea(child: pages[tab]),
          bottomNavigationBar: StreamBuilder<int>(
            stream: unread,
            builder: (context, u) => OrodNav(
              index: tab,
              onTap: (i) => setState(() => tab = i),
              badges: {2: tab == 2 ? 0 : (u.data ?? 0)},
              items: [('🏠', 'الرئيسية'), ('🧾', 'أوردراتي'), ('📢', 'الرسايل'), ('👤', 'حسابي')],
            ),
          ),
        );
      },
    );
  }
}

class _OwnerMain extends StatelessWidget {
  final Map<String, dynamic> p;
  final VoidCallback openMsgs;
  const _OwnerMain({required this.p, required this.openMsgs});

  @override
  Widget build(BuildContext context) {
    final loc = latLngOf(p);
    return ListView(children: [
      Header('🏪', (p['name'] ?? '').toString(), 'صاحب مشروع · ${p['type'] ?? ''}',
          colors: G3.pu, trailing: Avatar(p['photo'], emoji: '🏪', size: 44)),
      sectionPad([
        if (loc == null)
          Box(
            border: kOrange,
            child: Column(children: [
              BoxTitle('حدد مكان مشروعك الأول', emoji: '📍'),
              Text('عشان نعرف نجيبلك أقرب كابتن ونحسب المسافة', style: TextStyle(color: kMuted)),
              SizedBox(height: 12),
              Btn3D('📍 حدد المكان على الخريطة', onTap: () => pickProjectLocation(context, p)),
            ]),
          ),
        StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: ordersWhere('ownerUid', uid),
          builder: (context, snap) {
            final all = snap.data ?? [];
            final active = all.where((d) => kActive.contains(d.data()['status']) || d.data()['status'] == 'rejected').toList();
            final delivered = all.where((d) => d.data()['status'] == 'delivered').toList();
            final now = DateTime.now();
            final month = delivered.where((d) {
              final t = tsToDate(d.data()['createdAt']);
              return t != null && t.year == now.year && t.month == now.month;
            });
            return Column(children: [
              for (final d in active)
                Box(
                  border: d.data()['status'] == 'rejected' ? kRed : kOrange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(d.id))),
                  child: Row(children: [
                    Icon3D('📦', size: 44),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text('#${d.data()['no']}', style: TextStyle(fontWeight: FontWeight.w900)),
                          Spacer(),
                          statusPill(d.data()['status']),
                        ]),
                        SizedBox(height: 4),
                        Text('🏠 ${d.data()['custName']} · 🛵 ${d.data()['captainName']}',
                            style: TextStyle(color: kMuted, fontSize: 13)),
                        Text('دوس للتتبع 📍', style: TextStyle(color: kOrange2, fontSize: 12, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                ),
              Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Btn3D('⚡ اطلب كابتن دلوقتي', fontSize: 19, onTap: () {
                  if (loc == null) {
                    pickProjectLocation(context, p);
                    return;
                  }
                  Navigator.push(context, MaterialPageRoute(builder: (_) => NewOrderScreen(p: p)));
                }),
              ),
              statsRow([
                StatBox('${all.length}', 'كل الأوردرات'),
                StatBox('${month.length}', 'اتسلمت الشهر ده', color: kGreen),
                StatBox(money(month.fold<double>(0, (s, d) => s + toD(d.data()['fee']))), 'توصيل الشهر ده', color: kOrange2),
              ]),
            ]);
          },
        ),
        if (loc != null)
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: availableCaptains(),
            builder: (context, snap) {
              final caps = sortByDistance(snap.data ?? [], loc, (p['favs'] as List?) ?? []);
              return Box(
                child: Column(children: [
                  BoxTitle('الكباتن المتاحين حواليك (${caps.length})', emoji: '🛵'),
                  OrodMap(
                    center: loc,
                    zoom: 13,
                    hint: '🟢 كابتن متاح · 🏪 مشروعك',
                    pins: [
                      MapPin(loc, '🏪', color: kPurple, size: 38),
                      for (final c in caps) MapPin(latLngOf(c)!, '🛵', color: kGreen, size: 32),
                    ],
                  ),
                  SizedBox(height: 12),
                  if (caps.isEmpty)
                    Text('مفيش كباتن أونلاين دلوقتي حواليك', style: TextStyle(color: kMuted))
                  else
                    for (final c in caps.take(3)) CaptainTile(c, km: c['_km'], fav: ((p['favs'] as List?) ?? []).contains(c['id'])),
                ]),
              );
            },
          ),
        LatestMessage('owners', onOpen: openMsgs),
      ]),
    ]);
  }
}

Future<void> pickProjectLocation(BuildContext context, Map<String, dynamic> p) async {
  final r = await Navigator.push<LatLng>(
    context,
    MaterialPageRoute(builder: (_) => PickLocationScreen(title: 'مكان المشروع', initial: latLngOf(p))),
  );
  if (r == null) return;
  await projectsCol.doc(uid).update({'lat': r.latitude, 'lng': r.longitude});
  if (context.mounted) toast(context, '📍 اتحفظ مكان المشروع');
}

// ======================== أوردر جديد ========================

class NewOrderScreen extends StatefulWidget {
  final Map<String, dynamic> p;
  const NewOrderScreen({super.key, required this.p});
  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  LatLng? drop;
  Map<String, dynamic>? captain;
  final cust = TextEditingController();
  final cphone = TextEditingController();
  final addr = TextEditingController();
  final note = TextEditingController();
  final fee = TextEditingController();
  final value = TextEditingController();
  bool cod = true;
  bool busy = false;
  late final caps = availableCaptains();

  LatLng get pick => latLngOf(widget.p)!;

  Future<void> _pickDrop() async {
    final r = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
          builder: (_) => PickLocationScreen(title: 'مكان العميل', initial: drop, reference: pick, refEmoji: '🏪')),
    );
    if (r != null) setState(() => drop = r);
  }

  Future<void> _send() async {
    final f = double.tryParse(fee.text.trim()) ?? 0;
    if (drop == null) return toast(context, '⚠️ حدد مكان العميل على الخريطة', error: true);
    if (cust.text.trim().isEmpty || !validPhone(cphone.text)) {
      return toast(context, '⚠️ اكتب اسم العميل ورقم موبايل صحيح', error: true);
    }
    if (f <= 0) return toast(context, '⚠️ قيمة التوصيلة إجبارية', error: true);
    if (captain == null) return toast(context, '⚠️ اختار الكابتن', error: true);
    setState(() => busy = true);
    try {
      final ref = ordersCol.doc();
      final batch = db.batch();
      batch.set(ref, {
        'no': newOrderNo(),
        'ownerUid': uid,
        'projectName': widget.p['name'] ?? '',
        'projectPhone': widget.p['phone'] ?? '',
        'pickLat': pick.latitude,
        'pickLng': pick.longitude,
        'dropLat': drop!.latitude,
        'dropLng': drop!.longitude,
        'captainUid': captain!['id'],
        'captainName': captain!['name'] ?? '',
        'captainPhone': captain!['phone'] ?? '',
        'custName': cust.text.trim(),
        'custPhone': normPhone(cphone.text),
        'addr': addr.text.trim(),
        'note': note.text.trim(),
        'fee': f,
        'value': double.tryParse(value.text.trim()) ?? 0,
        'cod': cod,
        'commission': double.parse((f * kRate).toStringAsFixed(2)),
        'commPaid': 'no',
        'status': 'pending',
        'rating': 0,
        'ratingNote': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(ref.collection('secret').doc('otp'), {'code': randomCode(), 'ownerUid': uid});
      await batch.commit();
      if (!mounted) return;
      toast(context, '✅ الأوردر اتبعت للكابتن ${captain!['name']}');
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TrackScreen(ref.id)));
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _toggleFav(String id) async {
    final favs = List<String>.from((widget.p['favs'] as List?) ?? []);
    final on = favs.contains(id);
    await projectsCol.doc(uid).update({
      'favs': on ? FieldValue.arrayRemove([id]) : FieldValue.arrayUnion([id])
    });
    if (mounted) toast(context, on ? 'اتشال من المفضلة' : '⭐ اتضاف للمفضلة.. هيظهرلك الأول دايماً');
  }

  @override
  Widget build(BuildContext context) {
    final f = double.tryParse(fee.text.trim()) ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text('📦 أوردر جديد')),
      body: ListView(padding: EdgeInsets.all(16), children: [
        Box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BoxTitle('1️⃣ مكان العميل'),
            if (drop != null) ...[
              OrodMap(
                key: ValueKey(drop),
                fit: true,
                height: 180,
                route: [pick, drop!],
                pins: [MapPin(pick, '🏪', color: kPurple), MapPin(drop!, '🏠', color: kRed)],
              ),
              SizedBox(height: 8),
              Text('المسافة: ${kmTxt(kmBetween(pick.latitude, pick.longitude, drop!.latitude, drop!.longitude))}',
                  style: TextStyle(color: kOrange2, fontWeight: FontWeight.w800)),
              SizedBox(height: 8),
            ],
            OutlinedButton.icon(
                onPressed: _pickDrop,
                icon: Icon(Icons.location_on_outlined),
                label: Text(drop == null ? 'حدد مكان العميل على الخريطة' : 'تغيير المكان')),
          ]),
        ),
        Box(
          child: Column(children: [
            BoxTitle('2️⃣ بيانات العميل'),
            TextField(controller: cust, decoration: InputDecoration(labelText: 'اسم العميل *')),
            SizedBox(height: 10),
            TextField(
                controller: cphone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: 'موبايل العميل *')),
            SizedBox(height: 10),
            TextField(controller: addr, decoration: InputDecoration(labelText: 'العنوان بالتفصيل (الشارع - العمارة - الدور)')),
            SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: 'ملاحظات للكابتن (مثلاً: قابل للكسر)')),
          ]),
        ),
        Box(
          child: Column(children: [
            BoxTitle('3️⃣ الحساب'),
            TextField(
              controller: fee,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'قيمة التوصيلة للكابتن (إجباري) *', suffixText: 'ج'),
            ),
            SizedBox(height: 10),
            TextField(
              controller: value,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'قيمة الأوردر نفسه', suffixText: 'ج'),
            ),
            SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text('💵 الكابتن يحصّل تمن الأوردر من العميل', style: TextStyle(color: kMuted))),
              Toggle(cod, (v) => setState(() => cod = v)),
            ]),
            Container(
              margin: EdgeInsets.only(top: 6),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: kDeep, borderRadius: BorderRadius.circular(14), border: Border.all(color: kOrange.withValues(alpha: .6))),
              child: Column(children: [
                KV('الكابتن ياخد', money(f)),
                KV('عمولة التطبيق 5% (على الكابتن)', money(f * kRate), color: kOrange2),
              ]),
            ),
          ]),
        ),
        Box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BoxTitle('4️⃣ اختار الكابتن', emoji: null),
            Text('مترتبين بالأقرب ليك (المفضلين الأول) · دوسة طويلة = مفضلة ⭐', style: TextStyle(color: kMuted, fontSize: 12)),
            SizedBox(height: 10),
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: caps,
              builder: (context, snap) {
                if (!snap.hasData) return Loading();
                final favs = (widget.p['favs'] as List?) ?? [];
                final caps = sortByDistance(snap.data!, pick, favs);
                if (caps.isEmpty) {
                  return EmptyView('مفيش كباتن متاحين دلوقتي', emoji: '🛵', text: 'جرّب كمان شوية');
                }
                return Column(children: [
                  for (final c in caps)
                    GestureDetector(
                      onLongPress: () => _toggleFav(c['id']),
                      child: CaptainTile(c,
                          km: c['_km'],
                          fav: favs.contains(c['id']),
                          selected: captain?['id'] == c['id'],
                          onTap: () => setState(() => captain = c)),
                    ),
                ]);
              },
            ),
          ]),
        ),
        Btn3D('🚀 ابعت الأوردر', onTap: _send, busy: busy, fontSize: 18),
        SizedBox(height: 30),
      ]),
    );
  }
}

// ======================== تتبع الأوردر ========================

class TrackScreen extends StatefulWidget {
  final String id;
  const TrackScreen(this.id, {super.key});
  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  String otp = '';
  int stars = 0;
  final rateNote = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    ordersCol.doc(widget.id).collection('secret').doc('otp').get().then((s) {
      if (mounted) setState(() => otp = (s.data()?['code'] ?? '').toString());
    }).catchError((_) {});
  }

  Future<void> _rate(Map<String, dynamic> o) async {
    if (stars == 0) return toast(context, 'اختار عدد النجوم', error: true);
    setState(() => busy = true);
    try {
      final b = db.batch();
      b.update(ordersCol.doc(widget.id),
          {'rating': stars, 'ratingNote': rateNote.text.trim(), 'updatedAt': FieldValue.serverTimestamp()});
      b.update(captainsCol.doc(o['captainUid']), {
        'ratingSum': FieldValue.increment(stars),
        'ratingCount': FieldValue.increment(1),
        if (stars == 5) 'points': FieldValue.increment(15),
      });
      await b.commit();
      if (mounted) toast(context, stars == 5 ? '⭐ شكراً! الكابتن كسب 15 نقطة بونص' : '⭐ شكراً على تقييمك');
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reassign(Map<String, dynamic> o, Map<String, dynamic> p) async {
    final pick = LatLng(toD(o['pickLat']), toD(o['pickLng']));
    final c = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * .75,
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: availableCaptains(),
          builder: (ctx, snap) {
            final caps = sortByDistance(snap.data ?? [], pick, (p['favs'] as List?) ?? [])
                .where((c) => c['id'] != o['captainUid'])
                .toList();
            return ListView(padding: EdgeInsets.all(16), children: [
              BoxTitle('اختار كابتن تاني', emoji: '🛵'),
              if (caps.isEmpty) EmptyView('مفيش كباتن متاحين دلوقتي', emoji: '🛵'),
              for (final c in caps) CaptainTile(c, km: c['_km'], onTap: () => Navigator.pop(ctx, c)),
            ]);
          },
        ),
      ),
    );
    if (c == null) return;
    await ordersCol.doc(widget.id).update({
      'captainUid': c['id'],
      'captainName': c['name'] ?? '',
      'captainPhone': c['phone'] ?? '',
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) toast(context, '✅ الأوردر اتبعت للكابتن ${c['name']}');
  }

  Future<void> _cancel() async {
    if (!await confirm(context, 'إلغاء الأوردر', 'متأكد إنك عاوز تلغي الأوردر؟', ok: 'إلغاء الأوردر', danger: true)) return;
    await ordersCol.doc(widget.id).update({'status': 'cancelled', 'updatedAt': FieldValue.serverTimestamp()});
  }

  void _share(Map<String, dynamic> o, LatLng? cap) {
    final t = StringBuffer()
      ..writeln('أوردرك من ${o['projectName']} في الطريق ليك 🛵')
      ..writeln('الكابتن: ${o['captainName']} - ${o['captainPhone']}')
      ..writeln('🔐 كود الاستلام: $otp (قوله للكابتن بس لما تستلم)');
    if (cap != null) t.writeln('📍 مكان الكابتن دلوقتي: ${mapsLink(cap.latitude, cap.longitude)}');
    t.write('— أورد على السريع ⚡');
    openWhatsApp(o['custPhone'] ?? '', t.toString());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ordersCol.doc(widget.id).snapshots(),
      builder: (context, snap) {
        final o = snap.data?.data();
        if (o == null) return Scaffold(appBar: AppBar(), body: Loading());
        final st = (o['status'] ?? '').toString();
        final pick = LatLng(toD(o['pickLat']), toD(o['pickLng']));
        final drop = LatLng(toD(o['dropLat']), toD(o['dropLng']));
        return Scaffold(
          appBar: AppBar(title: Text('تتبع الأوردر #${o['no']}')),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: captainsCol.doc(o['captainUid']).snapshots(),
            builder: (context, cs) {
              final c = cs.data?.data() ?? {};
              final cap = latLngOf(c);
              final toPick = st == 'pending' || st == 'accepted';
              double left = 0;
              if (cap != null) {
                left = toPick
                    ? kmBetween(cap.latitude, cap.longitude, pick.latitude, pick.longitude) +
                        kmBetween(pick.latitude, pick.longitude, drop.latitude, drop.longitude)
                    : kmBetween(cap.latitude, cap.longitude, drop.latitude, drop.longitude);
              }
              final live = kActive.contains(st) && st != 'arrived';
              return ListView(padding: EdgeInsets.all(16), children: [
                Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: OrodMap(
                    fit: true,
                    height: 280,
                    hint: live && cap != null ? '⏱️ الوقت المتوقع ~ ${etaTxt(left)} · ${kmTxt(left)}' : (kStatus[st] ?? ''),
                    route: [if (cap != null && live) cap, if (toPick) pick, drop],
                    pins: [
                      MapPin(pick, '🏪', color: kPurple),
                      MapPin(drop, '🏠', color: kRed),
                      if (cap != null && st != 'delivered') MapPin(cap, '🛵', color: kOrange, size: 40, glow: true),
                    ],
                  ),
                ),
                Box(
                  child: Row(children: [
                    Avatar(c['photo'], size: 52),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${o['captainName']} ${c['verified'] == true ? '✅' : ''}',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(starsTxt(ratingOf(c)), style: TextStyle(color: kGold)),
                        Text('${c['vehicle'] ?? ''} · ${o['captainPhone']}', style: TextStyle(color: kMuted, fontSize: 12)),
                      ]),
                    ),
                    IconButton.filledTonal(onPressed: () => callPhone(o['captainPhone'] ?? ''), icon: Icon(Icons.call)),
                    SizedBox(width: 6),
                    IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: kGreen),
                        onPressed: () => openWhatsApp(o['captainPhone'] ?? '', 'أهلاً يا كابتن، بخصوص الأوردر #${o['no']}'),
                        icon: Icon(Icons.chat)),
                  ]),
                ),
                if (st == 'rejected')
                  Box(
                    border: kRed,
                    child: Column(children: [
                      Text('😕 الكابتن رفض الأوردر', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      SizedBox(height: 10),
                      Btn3D('🛵 اختار كابتن تاني', onTap: () async {
                        final p = (await projectsCol.doc(uid).get()).data() ?? {};
                        if (mounted) _reassign(o, p);
                      }),
                    ]),
                  ),
                if (kActive.contains(st) || st == 'delivered')
                  Box(
                    border: kGold.withValues(alpha: .6),
                    child: Column(children: [
                      BoxTitle('كود التسليم', emoji: '🔐'),
                      Text(otp.isEmpty ? '----' : otp.split('').join(' '),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: kGold, letterSpacing: 6)),
                      SizedBox(height: 6),
                      Text('ابعته للعميل.. الكابتن مش هيقدر يقفل الأوردر غير لما العميل يقوله الكود',
                          textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 13)),
                      if (st != 'delivered') ...[
                        SizedBox(height: 12),
                        Btn3D('📤 ابعت الكود ومكان الكابتن للعميل (واتساب)', colors: kBtnGreen, fontSize: 14, onTap: () => _share(o, cap)),
                      ],
                    ]),
                  ),
                Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  BoxTitle('مراحل الأوردر', emoji: '🧭'),
                  if (st == 'cancelled') Pill('الأوردر اتلغى', kRed) else OrderTimeline(st == 'rejected' ? 'pending' : st),
                ])),
                if (st == 'delivered') _rateBox(o),
                Box(child: Column(children: [
                  KV('العميل', '${o['custName']} · ${o['custPhone']}'),
                  if ((o['addr'] ?? '').toString().isNotEmpty) KV('العنوان', o['addr']),
                  KV('التوصيلة', money(o['fee'])),
                  KV('قيمة الأوردر', '${money(o['value'])}${o['cod'] == true ? ' (يحصّلها الكابتن)' : ''}'),
                  KV('اتعمل', ago(o['createdAt'])),
                ])),
                if (st == 'pending' || st == 'rejected')
                  TextButton.icon(
                      onPressed: _cancel,
                      icon: Icon(Icons.close, color: kRed),
                      label: Text('إلغاء الأوردر', style: TextStyle(color: kRed))),
                SizedBox(height: 20),
              ]);
            },
          ),
        );
      },
    );
  }

  Widget _rateBox(Map<String, dynamic> o) {
    if (toI(o['rating']) > 0) {
      return Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        BoxTitle('تقييمك للكابتن', emoji: '⭐'),
        Text(starsTxt(toD(o['rating'])), style: TextStyle(color: kGold, fontSize: 24)),
        if ((o['ratingNote'] ?? '').toString().isNotEmpty) Text('"${o['ratingNote']}"', style: TextStyle(color: kMuted)),
      ]));
    }
    return Box(
      border: kGold,
      child: Column(children: [
        BoxTitle('قيّم الكابتن', emoji: '⭐'),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            GestureDetector(
              onTap: () => setState(() => stars = i),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: AnimatedScale(
                  scale: i <= stars ? 1.15 : 1,
                  duration: Duration(milliseconds: 150),
                  child: Text(i <= stars ? '★' : '☆', style: TextStyle(fontSize: 40, color: kGold)),
                ),
              ),
            ),
        ]),
        SizedBox(height: 8),
        TextField(controller: rateNote, maxLines: 2, decoration: InputDecoration(labelText: 'ملاحظاتك على الكابتن')),
        SizedBox(height: 10),
        Btn3D('ابعت التقييم', onTap: () => _rate(o), busy: busy),
      ]),
    );
  }
}

// ======================== أوردراتي ========================

class _OwnerOrders extends StatefulWidget {
  @override
  State<_OwnerOrders> createState() => _OwnerOrdersState();
}

class _OwnerOrdersState extends State<_OwnerOrders> {
  int f = 0;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: ordersWhere('ownerUid', uid),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final list = all.where((d) {
          final s = d.data()['status'];
          if (f == 1) return kActive.contains(s) || s == 'rejected';
          if (f == 2) return s == 'delivered';
          return true;
        }).toList();
        final del = all.where((d) => d.data()['status'] == 'delivered');
        return ListView(children: [
          Header('🧾', 'أوردراتي', '${all.length} أوردر', colors: G3.bl),
          sectionPad([
            statsRow([
              StatBox('${del.length}', 'اتسلمت', color: kGreen),
              StatBox(money(del.fold<double>(0, (s, d) => s + toD(d.data()['fee']))), 'مصاريف التوصيل', color: kOrange2),
              StatBox(money(del.where((d) => d.data()['cod'] == true).fold<double>(0, (s, d) => s + toD(d.data()['value']))),
                  'اتحصّل كاش'),
            ]),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text('الكل')),
                ButtonSegment(value: 1, label: Text('شغالة')),
                ButtonSegment(value: 2, label: Text('اتسلمت')),
              ],
              selected: {f},
              onSelectionChanged: (s) => setState(() => f = s.first),
            ),
            SizedBox(height: 12),
            if (snap.hasData && list.isEmpty) EmptyView('مفيش أوردرات هنا', emoji: '📦'),
            for (final d in list)
              OrderTile(d.data(),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackScreen(d.id)))),
          ]),
        ]);
      },
    );
  }
}

// ======================== حسابي ========================

class OwnerProfile extends StatelessWidget {
  final Map<String, dynamic> p;
  const OwnerProfile({super.key, required this.p});

  Future<void> _edit(BuildContext context, String field, String title) async {
    final v = await askText(context, title, initial: (p[field] ?? '').toString());
    if (v == null || v.isEmpty) return;
    await projectsCol.doc(uid).update({field: v});
    if (field == 'name') await usersCol.doc(uid).update({'name': v});
  }

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      Header('👤', 'حسابي', 'بروفايل المشروع', colors: G3.pu),
      sectionPad([
        Box(
          child: Column(children: [
            GestureDetector(
              onTap: () async {
                final img = await pickImageB64(context, maxWidth: 400);
                if (img == null) return;
                await projectsCol.doc(uid).update({'photo': img});
                if (context.mounted) toast(context, '✅ الصورة اتحفظت');
              },
              child: Stack(children: [
                Avatar(p['photo'], emoji: '🏪', size: 110),
                Positioned(
                    bottom: 0,
                    left: 0,
                    child: CircleAvatar(radius: 16, backgroundColor: kOrange, child: Icon(Icons.camera_alt, size: 16, color: Colors.white))),
              ]),
            ),
            SizedBox(height: 10),
            Text((p['name'] ?? '').toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text((p['phone'] ?? '').toString(), style: TextStyle(color: kMuted)),
          ]),
        ),
        Box(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            ListTile(
                leading: Text('🏪', style: TextStyle(fontSize: 22)),
                title: Text('اسم المشروع'),
                subtitle: Text((p['name'] ?? '').toString()),
                trailing: Icon(Icons.edit_outlined),
                onTap: () => _edit(context, 'name', 'اسم المشروع')),
            ListTile(
                leading: Text('🧑‍💼', style: TextStyle(fontSize: 22)),
                title: Text('صاحب المشروع'),
                subtitle: Text((p['owner'] ?? '').toString()),
                trailing: Icon(Icons.edit_outlined),
                onTap: () => _edit(context, 'owner', 'اسم صاحب المشروع')),
            ListTile(
                leading: Text('🏷️', style: TextStyle(fontSize: 22)),
                title: Text('نوع المشروع'),
                subtitle: Text((p['type'] ?? '').toString()),
                trailing: Icon(Icons.edit_outlined),
                onTap: () => _edit(context, 'type', 'نوع المشروع')),
            ListTile(
                leading: Text('📍', style: TextStyle(fontSize: 22)),
                title: Text('مكان المشروع على الخريطة'),
                subtitle: Text(latLngOf(p) == null ? 'لسه متحددش' : 'متحدد ✅'),
                trailing: Icon(Icons.map_outlined),
                onTap: () => pickProjectLocation(context, p)),
          ]),
        ),
        Box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            BoxTitle('الكباتن المفضلين', emoji: '⭐'),
            if (((p['favs'] as List?) ?? []).isEmpty)
              Text('اعمل دوسة طويلة على أي كابتن وانت بتطلب أوردر عشان تضيفه هنا', style: TextStyle(color: kMuted)),
            for (final id in (p['favs'] as List?) ?? [])
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: captainsCol.doc(id.toString()).snapshots(),
                builder: (context, s) {
                  final c = s.data?.data();
                  if (c == null) return SizedBox();
                  return CaptainTile(c,
                      fav: true,
                      trailing: IconButton(
                          icon: Icon(Icons.close, color: kMuted),
                          onPressed: () => projectsCol.doc(uid).update({
                                'favs': FieldValue.arrayRemove([id])
                              })));
                },
              ),
          ]),
        ),
        Btn3D('🚪 خروج', colors: [kPanel2, kLine], onTap: () => signOutAsk(context)),
        SizedBox(height: 30),
      ]),
    ]);
  }
}
