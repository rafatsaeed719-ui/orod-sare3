import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'common.dart';
import 'core.dart';
import 'map_view.dart';

typedef Docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>;

Stream<Docs> allOrders() => ordersCol.orderBy('createdAt', descending: true).limit(2000).snapshots().map((s) => s.docs);
Stream<Docs> allCaptains() => captainsCol.snapshots().map((s) => s.docs);
Stream<Docs> allProjects() => projectsCol.snapshots().map((s) => s.docs);

double dueFor(Docs orders, String captainId) => double.parse(orders
    .where((d) => d.data()['captainUid'] == captainId && d.data()['status'] == 'delivered' && d.data()['commPaid'] != 'yes')
    .fold<double>(0, (s, d) => s + commOf(d.data()))
    .toStringAsFixed(2));

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      AdminDashboard(open: (i) => setState(() => tab = i)),
      CaptainsAdmin(),
      ProjectsAdmin(),
      OrdersAdmin(),
      AdminMore(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: OrodNav(
        index: tab,
        onTap: (i) => setState(() => tab = i),
        items: [('📊', 'الرئيسية'), ('🛵', 'الكباتن'), ('🏪', 'المشاريع'), ('📦', 'الأوردرات'), ('⚙️', 'المزيد')],
      ),
    );
  }
}

// ======================== الرئيسية ========================

class AdminDashboard extends StatelessWidget {
  final ValueChanged<int> open;
  const AdminDashboard({super.key, required this.open});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Docs>(
      stream: allOrders(),
      builder: (context, os) => StreamBuilder<Docs>(
        stream: allCaptains(),
        builder: (context, cs) => StreamBuilder<Docs>(
          stream: allProjects(),
          builder: (context, ps) {
            final orders = os.data ?? [];
            final caps = cs.data ?? [];
            final projs = ps.data ?? [];
            final del = orders.where((d) => d.data()['status'] == 'delivered').toList();
            final totC = del.fold<double>(0, (s, d) => s + commOf(d.data()));
            final paid = del.where((d) => d.data()['commPaid'] == 'yes').fold<double>(0, (s, d) => s + commOf(d.data()));
            final totFee = del.fold<double>(0, (s, d) => s + toD(d.data()['fee']));
            final now = DateTime.now();
            final today = orders.where((d) {
              final t = tsToDate(d.data()['createdAt']);
              return t != null && sameDay(t, now);
            }).toList();
            final todayC = today.where((d) => d.data()['status'] == 'delivered').fold<double>(0, (s, d) => s + commOf(d.data()));
            final monthC = del.where((d) {
              final t = tsToDate(d.data()['createdAt']);
              return t != null && t.year == now.year && t.month == now.month;
            }).fold<double>(0, (s, d) => s + commOf(d.data()));
            final online = caps.where((d) => d.data()['online'] == true && latLngOf(d.data()) != null).toList();
            final pendingVerify = caps.where((d) => d.data()['verified'] != true && d.data()['blocked'] != true).length;
            final active = orders.where((d) => kActive.contains(d.data()['status'])).length;
            return ListView(children: [
              Header('👑', 'لوحة التحكم', 'أهلاً يا رأفت', colors: G3.gd),
              sectionPad([
                Box(
                  gradient: LinearGradient(colors: [kOrange, kRed]),
                  border: Colors.transparent,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('💰 إجمالي العمولات (5%)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                    Text(money(totC), style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.white)),
                    Row(children: [
                      Expanded(child: Text('✅ اتحصّل: ${money(paid)}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                      Text('⏳ متبقي: ${money(totC - paid)}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ]),
                    SizedBox(height: 6),
                    Text('النهارده: ${money(todayC)} · الشهر ده: ${money(monthC)}',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
                ),
                statsRow([
                  StatBox('${orders.length}', 'كل الأوردرات'),
                  StatBox('${today.length}', 'أوردرات النهارده', color: kOrange2),
                  StatBox('$active', 'شغالة دلوقتي', color: kBlue),
                ]),
                statsRow([
                  StatBox(money(totFee), 'إجمالي التوصيلات', color: kGreen),
                  StatBox('${online.length}/${caps.length}', 'كابتن أونلاين'),
                  StatBox('${projs.length}', 'مشروع'),
                ]),
                _Alerts(pendingVerify: pendingVerify, open: open),
                Box(child: Column(children: [
                  BoxTitle('الكباتن الأونلاين والمشاريع', emoji: '🗺️'),
                  OrodMap(
                    height: 260,
                    zoom: 11,
                    center: online.isNotEmpty ? latLngOf(online.first.data()) : null,
                    hint: '🛵 كابتن · 🏪 مشروع',
                    pins: [
                      for (final p in projs)
                        if (latLngOf(p.data()) != null) MapPin(latLngOf(p.data())!, '🏪', color: kPurple, size: 28),
                      for (final c in online) MapPin(latLngOf(c.data())!, '🛵', color: kGreen, size: 30),
                    ],
                  ),
                ])),
                _TopCaptains(caps: caps),
              ]),
            ]);
          },
        ),
      ),
    );
  }
}

class _Alerts extends StatelessWidget {
  final int pendingVerify;
  final ValueChanged<int> open;
  const _Alerts({required this.pendingVerify, required this.open});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: paymentsCol.where('status', isEqualTo: 'pending').snapshots(),
        builder: (context, pay) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: redeemsCol.where('status', isEqualTo: 'pending').snapshots(),
          builder: (context, red) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: sosCol.where('status', isEqualTo: 'open').snapshots(),
            builder: (context, sos) {
              final p = pay.data?.size ?? 0, r = red.data?.size ?? 0, s = sos.data?.size ?? 0;
              if (p + r + s + pendingVerify == 0) return SizedBox();
              return Box(
                border: s > 0 ? kRed : kOrange2,
                child: Column(children: [
                  BoxTitle('محتاج مراجعتك', emoji: '⚠️'),
                  if (s > 0) _alert('🆘 $s طوارئ من الكباتن!', kRed, () => _push(context, SosAdmin())),
                  if (pendingVerify > 0) _alert('🪪 $pendingVerify كابتن مستني توثيق', kOrange, () => open(1)),
                  if (p > 0) _alert('💸 $p تحويل عمولة مستني تأكيد', kGold, () => _push(context, CommissionsAdmin())),
                  if (r > 0) _alert('🎁 $r طلب هدية', kPurple, () => _push(context, RedeemsAdmin())),
                ]),
              );
            },
          ),
        ),
      );

  Widget _alert(String t, Color c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Note('$t  ←  راجع', color: c),
      );
}

void _push(BuildContext context, Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

class _TopCaptains extends StatelessWidget {
  final Docs caps;
  const _TopCaptains({required this.caps});
  @override
  Widget build(BuildContext context) {
    final list = caps.map((d) => {...d.data(), 'id': d.id}).toList()
      ..sort((a, b) => toI(b['points']).compareTo(toI(a['points'])));
    if (list.isEmpty) return SizedBox();
    return Box(child: Column(children: [
      BoxTitle('أحسن الكباتن (كابتن الأسبوع)', emoji: '🏆'),
      for (var i = 0; i < list.length && i < 3; i++)
        CaptainTile(list[i],
            onTap: () => _push(context, CaptainDetail(list[i]['id'])),
            trailing: Text(['🥇', '🥈', '🥉'][i], style: TextStyle(fontSize: 24))),
    ]));
  }
}

// ======================== الكباتن ========================

class CaptainsAdmin extends StatefulWidget {
  const CaptainsAdmin({super.key});
  @override
  State<CaptainsAdmin> createState() => _CaptainsAdminState();
}

class _CaptainsAdminState extends State<CaptainsAdmin> {
  String q = '';
  int f = 0;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Docs>(
      stream: allCaptains(),
      builder: (context, snap) => StreamBuilder<Docs>(
        stream: allOrders(),
        builder: (context, os) {
          final orders = os.data ?? [];
          var list = (snap.data ?? []).where((d) {
            final c = d.data();
            if (q.isNotEmpty && !'${c['name']} ${c['phone']}'.contains(q)) return false;
            if (f == 1) return c['verified'] != true;
            if (f == 2) return c['online'] == true;
            if (f == 3) return c['blocked'] == true;
            return true;
          }).toList();
          list.sort((a, b) => (a.data()['verified'] == true ? 1 : 0).compareTo(b.data()['verified'] == true ? 1 : 0));
          return ListView(children: [
            Header('🛵', 'الكباتن', '${snap.data?.length ?? 0} كابتن', colors: G3.gr,
                trailing: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: kOrange),
                    onPressed: () => addAccountDialog(context, 'captain'),
                    icon: Icon(Icons.add))),
            sectionPad([
              TextField(
                  onChanged: (v) => setState(() => q = v.trim()),
                  decoration: InputDecoration(hintText: 'بحث بالاسم أو الرقم', prefixIcon: Icon(Icons.search))),
              SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (i, t) in [(0, 'الكل'), (1, 'مستني توثيق'), (2, 'أونلاين'), (3, 'موقوفين')])
                    Padding(
                      padding: EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(label: Text(t), selected: f == i, onSelected: (_) => setState(() => f = i)),
                    ),
                ]),
              ),
              SizedBox(height: 10),
              if (snap.hasData && list.isEmpty) EmptyView('مفيش كباتن هنا', emoji: '🛵'),
              for (final d in list)
                CaptainTile(
                  {...d.data(), 'id': d.id},
                  onTap: () => _push(context, CaptainDetail(d.id)),
                  trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (d.data()['blocked'] == true)
                      Pill('موقوف', kRed)
                    else if (d.data()['verified'] != true)
                      Pill(d.data()['idSent'] == true ? 'بطاقة مرفوعة' : 'مش موثق', kOrange2)
                    else if (d.data()['online'] == true)
                      Pill('أونلاين', kGreen),
                    SizedBox(height: 4),
                    Text('عليه ${money(dueFor(orders, d.id))}', style: TextStyle(color: kOrange2, fontSize: 11)),
                  ]),
                ),
            ]),
          ]);
        },
      ),
    );
  }
}

class CaptainDetail extends StatelessWidget {
  final String id;
  const CaptainDetail(this.id, {super.key});

  Future<void> _gift(BuildContext context) async {
    final v = await askText(context, '🎁 هدية نقط', hint: 'عدد النقط (مثلاً 50)', type: TextInputType.number);
    final n = int.tryParse(v ?? '');
    if (n == null || n == 0) return;
    await captainsCol.doc(id).update({'points': FieldValue.increment(n)});
    if (context.mounted) toast(context, '🎁 اتبعت $n نقطة');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: captainsCol.doc(id).snapshots(),
      builder: (context, snap) {
        final c = snap.data?.data();
        if (c == null) return Scaffold(appBar: AppBar(), body: snap.hasData ? EmptyView('الكابتن اتحذف') : Loading());
        return Scaffold(
          appBar: AppBar(title: Text((c['name'] ?? '').toString())),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: usersCol.doc(id).snapshots(),
            builder: (context, us) {
              final u = us.data?.data() ?? {};
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ordersCol.where('captainUid', isEqualTo: id).snapshots(),
                builder: (context, os) {
                  final orders = os.data?.docs ?? [];
                  final del = orders.where((d) => d.data()['status'] == 'delivered').toList();
                  final due = dueFor(orders, id);
                  final notes = del.where((d) => (d.data()['ratingNote'] ?? '').toString().isNotEmpty);
                  final r = ratingOf(c);
                  return ListView(padding: EdgeInsets.all(16), children: [
                    Box(child: Column(children: [
                      GestureDetector(
                          onTap: (c['photo'] ?? '').toString().isEmpty ? null : () => showPhoto(context, c['photo']),
                          child: Avatar(c['photo'], size: 96)),
                      SizedBox(height: 8),
                      Text('${c['name']} ${c['verified'] == true ? '✅' : ''}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      Text('${starsTxt(r)} ${r.toStringAsFixed(1)} (${toI(c['ratingCount'])})', style: TextStyle(color: kGold)),
                      Text('${c['phone']} · ${c['vehicle']}', style: TextStyle(color: kMuted)),
                      Text('${levelOf(toI(c['points'])).emoji} ${toI(c['points'])} نقطة', style: TextStyle(color: kMuted)),
                      SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton.filledTonal(onPressed: () => callPhone(c['phone'] ?? ''), icon: Icon(Icons.call)),
                        SizedBox(width: 8),
                        IconButton.filled(
                            style: IconButton.styleFrom(backgroundColor: kGreen),
                            onPressed: () => openWhatsApp(c['phone'] ?? '', 'أهلاً يا كابتن ${c['name']}، معاك إدارة «أورد على السريع»'),
                            icon: Icon(Icons.chat)),
                        if (latLngOf(c) != null) ...[
                          SizedBox(width: 8),
                          IconButton.filledTonal(
                              onPressed: () => navigateTo(latLngOf(c)!.latitude, latLngOf(c)!.longitude),
                              icon: Icon(Icons.location_on)),
                        ],
                      ]),
                    ])),
                    statsRow([
                      StatBox('${del.length}', 'رحلة'),
                      StatBox(money(del.fold<double>(0, (s, d) => s + toD(d.data()['fee']))), 'أخد', color: kGreen),
                      StatBox(money(due), 'عمولة عليه', color: kOrange2),
                    ]),
                    Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      BoxTitle('البطاقة', emoji: '🪪', trailing: c['verified'] == true ? Pill('موثق', kGreen) : Pill('مش موثق', kOrange2)),
                      Row(children: [
                        for (final f in ['idFront', 'idBack']) ...[
                          if (f == 'idBack') SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: (u[f] ?? '').toString().isEmpty ? null : () => showPhoto(context, u[f]),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: (u[f] ?? '').toString().isEmpty
                                    ? Container(
                                        height: 100,
                                        color: kDeep,
                                        alignment: Alignment.center,
                                        child: Text('لسه مرفعهاش', style: TextStyle(color: kMuted)))
                                    : B64Image(u[f], height: 100, width: double.infinity),
                              ),
                            ),
                          ),
                        ],
                      ]),
                      SizedBox(height: 12),
                      Btn3D(c['verified'] == true ? 'إلغاء التوثيق' : '✅ توثيق الكابتن',
                          colors: c['verified'] == true ? [kPanel2, kLine] : kBtnGreen,
                          onTap: () => captainsCol.doc(id).update({'verified': c['verified'] != true})),
                    ])),
                    if (notes.isNotEmpty)
                      Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        BoxTitle('ملاحظات أصحاب المشاريع', emoji: '💬'),
                        for (final d in notes.take(30))
                          Note('${starsTxt(toD(d.data()['rating']))} "${d.data()['ratingNote']}" — ${d.data()['projectName']}', color: kGold),
                      ])),
                    Box(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        ListTile(leading: Text('🎁', style: TextStyle(fontSize: 22)), title: Text('هدية نقط'), onTap: () => _gift(context)),
                        ListTile(
                          leading: Text(c['blocked'] == true ? '✅' : '⛔', style: TextStyle(fontSize: 22)),
                          title: Text(c['blocked'] == true ? 'تفعيل الحساب' : 'إيقاف الحساب'),
                          onTap: () => setBlocked(id, c['blocked'] != true, captain: true),
                        ),
                        ListTile(
                            leading: Text('🔑', style: TextStyle(fontSize: 22)),
                            title: Text('تغيير كلمة السر'),
                            subtitle: Text('الحالية: ${u['password'] ?? '—'}'),
                            onTap: () => changePasswordDialog(context, id, u)),
                        ListTile(
                          leading: Text('🗑️', style: TextStyle(fontSize: 22)),
                          title: Text('حذف الكابتن نهائي', style: TextStyle(color: kRed)),
                          onTap: () async {
                            if (!await confirm(context, 'حذف ${c['name']}', 'هيتحذف الحساب نهائي. متأكد؟', ok: 'حذف', danger: true)) return;
                            await deleteAccount(id);
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      ]),
                    ),
                    Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      BoxTitle('آخر الأوردرات', emoji: '📦'),
                      for (final d in orders.take(30)) OrderTile(d.data(), forCaptain: true, onTap: () => showOrderSheet(context, d)),
                    ])),
                  ]);
                },
              );
            },
          ),
        );
      },
    );
  }
}

Future<void> setBlocked(String id, bool blocked, {required bool captain}) async {
  final b = db.batch();
  b.update(usersCol.doc(id), {'disabled': blocked});
  b.update(captain ? captainsCol.doc(id) : projectsCol.doc(id), {'blocked': blocked, if (captain && blocked) 'online': false});
  await b.commit();
}

Future<void> changePasswordDialog(BuildContext context, String id, Map<String, dynamic> u) async {
  final v = await askText(context, '🔑 كلمة السر الجديدة', hint: '6 حروف أو أرقام على الأقل');
  if (v == null) return;
  if (v.length < 6) return toast(context, 'كلمة السر لازم تكون 6 على الأقل', error: true);
  try {
    await changeAccountPassword(id, u, v);
    if (context.mounted) toast(context, '✅ كلمة السر اتغيرت');
  } catch (e) {
    if (context.mounted) toast(context, 'مقدرتش أغيرها: ${authError(e)}', error: true);
  }
}

Future<void> addAccountDialog(BuildContext context, String role) async {
  final name = TextEditingController(), phone = TextEditingController(), extra = TextEditingController();
  final pass = TextEditingController(text: randomCode() + randomCode().substring(0, 2));
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(role == 'captain' ? '➕ كابتن جديد' : '➕ مشروع جديد'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: role == 'captain' ? 'الاسم' : 'اسم المشروع')),
          SizedBox(height: 10),
          TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: 'الموبايل')),
          SizedBox(height: 10),
          TextField(controller: extra, decoration: InputDecoration(labelText: role == 'captain' ? 'وسيلة التوصيل' : 'نوع المشروع')),
          SizedBox(height: 10),
          TextField(controller: pass, decoration: InputDecoration(labelText: 'كلمة السر')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text('إضافة')),
      ],
    ),
  );
  if (ok != true) return;
  if (name.text.trim().isEmpty || !validPhone(phone.text) || pass.text.length < 6) {
    if (context.mounted) toast(context, 'اكتب الاسم ورقم صحيح وكلمة سر 6 على الأقل', error: true);
    return;
  }
  try {
    await adminCreateAccount(
        role: role, phone: phone.text, name: name.text.trim(), password: pass.text, extra: extra.text.trim());
    if (context.mounted) {
      toast(context, '✅ اتضاف');
      openWhatsApp(phone.text,
          'أهلاً ${name.text.trim()} 👋\nحسابك على «أورد على السريع» جاهز\nالرقم: ${normPhone(phone.text)}\nكلمة السر: ${pass.text}');
    }
  } catch (e) {
    if (context.mounted) toast(context, authError(e), error: true);
  }
}

// ======================== المشاريع ========================

class ProjectsAdmin extends StatefulWidget {
  const ProjectsAdmin({super.key});
  @override
  State<ProjectsAdmin> createState() => _ProjectsAdminState();
}

class _ProjectsAdminState extends State<ProjectsAdmin> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Docs>(
      stream: allProjects(),
      builder: (context, snap) => StreamBuilder<Docs>(
        stream: allOrders(),
        builder: (context, os) {
          final orders = os.data ?? [];
          final list = (snap.data ?? []).where((d) => q.isEmpty || '${d.data()['name']} ${d.data()['phone']}'.contains(q)).toList();
          return ListView(children: [
            Header('🏪', 'المشاريع', '${snap.data?.length ?? 0} مشروع', colors: G3.pu,
                trailing: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: kOrange),
                    onPressed: () => addAccountDialog(context, 'owner'),
                    icon: Icon(Icons.add))),
            sectionPad([
              TextField(
                  onChanged: (v) => setState(() => q = v.trim()),
                  decoration: InputDecoration(hintText: 'بحث بالاسم أو الرقم', prefixIcon: Icon(Icons.search))),
              SizedBox(height: 12),
              if (snap.hasData && list.isEmpty) EmptyView('مفيش مشاريع', emoji: '🏪'),
              for (final d in list) _projectCard(context, d, orders.where((o) => o.data()['ownerUid'] == d.id).toList()),
            ]),
          ]);
        },
      ),
    );
  }

  Widget _projectCard(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d, Docs os) {
    final p = d.data();
    final del = os.where((o) => o.data()['status'] == 'delivered');
    return Box(
      onTap: () => _push(context, ProjectDetail(d.id)),
      padding: EdgeInsets.all(12),
      child: Row(children: [
        Avatar(p['photo'], emoji: '🏪', size: 50),
        SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((p['name'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text('${p['owner'] ?? ''} · ${p['phone'] ?? ''} · ${p['type'] ?? ''}', style: TextStyle(color: kMuted, fontSize: 12)),
            Text('${os.length} أوردر · ${money(del.fold<double>(0, (s, o) => s + toD(o.data()['fee'])))} توصيل · عمولة ${money(del.fold<double>(0, (s, o) => s + commOf(o.data())))}',
                style: TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
        if (p['blocked'] == true) Pill('موقوف', kRed),
      ]),
    );
  }
}

class ProjectDetail extends StatelessWidget {
  final String id;
  const ProjectDetail(this.id, {super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: projectsCol.doc(id).snapshots(),
      builder: (context, snap) {
        final p = snap.data?.data();
        if (p == null) return Scaffold(appBar: AppBar(), body: snap.hasData ? EmptyView('المشروع اتحذف') : Loading());
        return Scaffold(
          appBar: AppBar(title: Text((p['name'] ?? '').toString())),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: usersCol.doc(id).snapshots(),
            builder: (context, us) {
              final u = us.data?.data() ?? {};
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ordersCol.where('ownerUid', isEqualTo: id).snapshots(),
                builder: (context, os) {
                  final orders = os.data?.docs ?? [];
                  final del = orders.where((d) => d.data()['status'] == 'delivered');
                  final loc = latLngOf(p);
                  return ListView(padding: EdgeInsets.all(16), children: [
                    Box(child: Column(children: [
                      Avatar(p['photo'], emoji: '🏪', size: 90),
                      SizedBox(height: 8),
                      Text((p['name'] ?? '').toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      Text('${p['owner'] ?? ''} · ${p['phone'] ?? ''}', style: TextStyle(color: kMuted)),
                      SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        IconButton.filledTonal(onPressed: () => callPhone(p['phone'] ?? ''), icon: Icon(Icons.call)),
                        SizedBox(width: 8),
                        IconButton.filled(
                            style: IconButton.styleFrom(backgroundColor: kGreen),
                            onPressed: () => openWhatsApp(p['phone'] ?? '', 'أهلاً ${p['name']}، معاك إدارة «أورد على السريع»'),
                            icon: Icon(Icons.chat)),
                      ]),
                    ])),
                    if (loc != null)
                      Padding(
                        padding: EdgeInsets.only(bottom: 14),
                        child: OrodMap(center: loc, height: 170, pins: [MapPin(loc, '🏪', color: kPurple)]),
                      ),
                    statsRow([
                      StatBox('${orders.length}', 'أوردر'),
                      StatBox(money(del.fold<double>(0, (s, d) => s + toD(d.data()['fee']))), 'توصيلات', color: kGreen),
                      StatBox(money(del.fold<double>(0, (s, d) => s + commOf(d.data()))), 'عمولتك', color: kOrange2),
                    ]),
                    Box(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Column(children: [
                        ListTile(
                          leading: Text(p['blocked'] == true ? '✅' : '⛔', style: TextStyle(fontSize: 22)),
                          title: Text(p['blocked'] == true ? 'تفعيل المشروع' : 'إيقاف المشروع'),
                          onTap: () => setBlocked(id, p['blocked'] != true, captain: false),
                        ),
                        ListTile(
                            leading: Text('🔑', style: TextStyle(fontSize: 22)),
                            title: Text('تغيير كلمة السر'),
                            subtitle: Text('الحالية: ${u['password'] ?? '—'}'),
                            onTap: () => changePasswordDialog(context, id, u)),
                        ListTile(
                          leading: Text('🗑️', style: TextStyle(fontSize: 22)),
                          title: Text('حذف المشروع نهائي', style: TextStyle(color: kRed)),
                          onTap: () async {
                            if (!await confirm(context, 'حذف ${p['name']}', 'هيتحذف الحساب نهائي. متأكد؟', ok: 'حذف', danger: true)) return;
                            await deleteAccount(id);
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      ]),
                    ),
                    Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      BoxTitle('الأوردرات', emoji: '📦'),
                      for (final d in orders.take(40)) OrderTile(d.data(), onTap: () => showOrderSheet(context, d)),
                    ])),
                  ]);
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ======================== الأوردرات ========================

class OrdersAdmin extends StatefulWidget {
  const OrdersAdmin({super.key});
  @override
  State<OrdersAdmin> createState() => _OrdersAdminState();
}

class _OrdersAdminState extends State<OrdersAdmin> {
  int f = 0;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Docs>(
      stream: allOrders(),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final list = all.where((d) {
          final s = d.data()['status'];
          if (f == 1) return kActive.contains(s);
          if (f == 2) return s == 'delivered';
          if (f == 3) return s == 'cancelled' || s == 'rejected';
          return true;
        }).toList();
        return ListView(children: [
          Header('📦', 'كل الأوردرات', '${all.length} أوردر', colors: G3.or),
          sectionPad([
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (i, t) in [(0, 'الكل'), (1, 'شغالة'), (2, 'اتسلمت'), (3, 'اتلغت / اترفضت')])
                  Padding(
                    padding: EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(label: Text(t), selected: f == i, onSelected: (_) => setState(() => f = i)),
                  ),
              ]),
            ),
            SizedBox(height: 12),
            if (snap.hasData && list.isEmpty) EmptyView('مفيش أوردرات هنا', emoji: '📦'),
            for (final d in list.take(300)) OrderTile(d.data(), forCaptain: true, onTap: () => showOrderSheet(context, d)),
          ]),
        ]);
      },
    );
  }
}

void showOrderSheet(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d) {
  final o = d.data();
  final pick = LatLng(toD(o['pickLat']), toD(o['pickLng']));
  final drop = LatLng(toD(o['dropLat']), toD(o['dropLng']));
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => SizedBox(
      height: MediaQuery.of(c).size.height * .85,
      child: ListView(padding: EdgeInsets.all(16), children: [
        Row(children: [
          Text('📦 #${o['no']}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Spacer(),
          statusPill(o['status'] ?? ''),
        ]),
        SizedBox(height: 12),
        OrodMap(fit: true, height: 200, route: [pick, drop], pins: [MapPin(pick, '🏪', color: kPurple), MapPin(drop, '🏠', color: kRed)]),
        SizedBox(height: 12),
        KV('المشروع', '${o['projectName']} · ${o['projectPhone']}'),
        KV('الكابتن', '${o['captainName']} · ${o['captainPhone']}'),
        KV('العميل', '${o['custName']} · ${o['custPhone']}'),
        if ((o['addr'] ?? '').toString().isNotEmpty) KV('العنوان', o['addr']),
        KV('المسافة', kmTxt(kmBetween(pick.latitude, pick.longitude, drop.latitude, drop.longitude))),
        KV('التوصيلة (الكابتن أخد)', money(o['fee']), color: kGreen),
        KV('عمولتك 5%', '${money(commOf(o))} ${o['commPaid'] == 'yes' ? '✅ اتحصّلت' : o['commPaid'] == 'pending' ? '⏳ مستنية تأكيد' : '❗ لسه'}',
            color: kOrange2),
        KV('قيمة الأوردر', '${money(o['value'])}${o['cod'] == true ? ' (كاش مع الكابتن)' : ''}'),
        KV('اتعمل', ago(o['createdAt'])),
        if (toI(o['rating']) > 0) KV('التقييم', '${starsTxt(toD(o['rating']))} ${o['ratingNote'] ?? ''}', color: kGold),
        SizedBox(height: 14),
        if (o['status'] == 'delivered' && o['commPaid'] != 'yes')
          Btn3D('✅ العمولة دي اتحصّلت', colors: kBtnGreen, onTap: () async {
            await d.reference.update({'commPaid': 'yes'});
            if (c.mounted) Navigator.pop(c);
          }),
        if (kActive.contains(o['status'])) ...[
          SizedBox(height: 10),
          Btn3D('إلغاء الأوردر', colors: kBtnRed, onTap: () async {
            await d.reference.update({'status': 'cancelled', 'updatedAt': FieldValue.serverTimestamp()});
            if (c.mounted) Navigator.pop(c);
          }),
        ],
      ]),
    ),
  );
}

// ======================== المزيد ========================

class AdminMore extends StatelessWidget {
  const AdminMore({super.key});
  @override
  Widget build(BuildContext context) {
    final items = [
      ('💸', 'العمولات والتحويلات', G3.gd, CommissionsAdmin()),
      ('📢', 'رسالة جماعية', G3.rd, BroadcastAdmin()),
      ('🎁', 'طلبات الهدايا', G3.pu, RedeemsAdmin()),
      ('🆘', 'الطوارئ', G3.rd, SosAdmin()),
      ('⚙️', 'الإعدادات', G3.bl, SettingsAdmin()),
    ];
    return ListView(children: [
      Header('⚙️', 'المزيد', 'إدارة التطبيق', colors: G3.bl),
      sectionPad([
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.15,
          children: [
            for (final it in items)
              GestureDetector(
                onTap: () => _push(context, it.$4),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [kPanel2, kPanel]),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: kLine),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon3D(it.$1, colors: it.$3, size: 56),
                    SizedBox(height: 12),
                    Text(it.$2, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
          ],
        ),
        SizedBox(height: 16),
        Btn3D('🚪 خروج', colors: [kPanel2, kLine], onTap: () => signOutAsk(context)),
        SizedBox(height: 20),
      ]),
    ]);
  }
}

class CommissionsAdmin extends StatelessWidget {
  const CommissionsAdmin({super.key});

  Future<void> _decide(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> p, bool ok) async {
    final b = db.batch();
    b.update(p.reference, {'status': ok ? 'ok' : 'rejected', 'decidedAt': FieldValue.serverTimestamp()});
    for (final id in (p.data()['orderIds'] as List?) ?? []) {
      b.update(ordersCol.doc(id.toString()), {'commPaid': ok ? 'yes' : 'no'});
    }
    if (ok) b.update(captainsCol.doc(p.data()['captainUid']), {'points': FieldValue.increment(20)});
    try {
      await b.commit();
      if (context.mounted) toast(context, ok ? '✅ اتأكد + 20 نقطة للكابتن' : 'اترفض والعمولة رجعت عليه');
    } catch (e) {
      if (context.mounted) toast(context, authError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('💸 العمولات')),
      body: StreamBuilder<Docs>(
        stream: allOrders(),
        builder: (context, os) => StreamBuilder<Docs>(
          stream: allCaptains(),
          builder: (context, cs) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: paymentsCol.orderBy('createdAt', descending: true).limit(100).snapshots(),
            builder: (context, ps) {
              final orders = os.data ?? [];
              final caps = (cs.data ?? []).toList()..sort((a, b) => dueFor(orders, b.id).compareTo(dueFor(orders, a.id)));
              final pays = ps.data?.docs ?? [];
              return ListView(padding: EdgeInsets.all(16), children: [
                Box(child: Column(children: [
                  BoxTitle('أرقام التحويل', emoji: '🏦'),
                  StreamBuilder<AppSettings>(
                    stream: settingsStream(),
                    builder: (context, s) {
                      final st = s.data ?? AppSettings(null);
                      return Column(children: [
                        KV('🟣 انستا باي', st.insta),
                        KV('🔴 فودافون كاش', st.voda),
                        KV('الحد الأقصى للعمولة المتأخرة', money(st.maxDue)),
                      ]);
                    },
                  ),
                ])),
                Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  BoxTitle('تحويلات الكباتن', emoji: '📨'),
                  if (pays.isEmpty) Text('مفيش تحويلات لسه', style: TextStyle(color: kMuted)),
                  for (final p in pays)
                    Container(
                      margin: EdgeInsets.only(bottom: 10),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(16), border: Border.all(color: kLine)),
                      child: Row(children: [
                        GestureDetector(
                          onTap: (p.data()['img'] ?? '').toString().isEmpty ? null : () => showPhoto(context, p.data()['img']),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: B64Image(p.data()['img'], width: 56, height: 56, emoji: '🧾')),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${p.data()['captainName']} · ${money(p.data()['amount'])}', style: TextStyle(fontWeight: FontWeight.w800)),
                            Text('${p.data()['method']} · ${ago(p.data()['createdAt'])}', style: TextStyle(color: kMuted, fontSize: 12)),
                          ]),
                        ),
                        if (p.data()['status'] == 'pending') ...[
                          IconButton.filled(
                              style: IconButton.styleFrom(backgroundColor: kGreen),
                              onPressed: () => _decide(context, p, true),
                              icon: Icon(Icons.check)),
                          IconButton(onPressed: () => _decide(context, p, false), icon: Icon(Icons.close, color: kRed)),
                        ] else
                          Pill(p.data()['status'] == 'ok' ? 'اتأكد ✅' : 'اترفض', p.data()['status'] == 'ok' ? kGreen : kRed),
                      ]),
                    ),
                ])),
                Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  BoxTitle('العمولة على كل كابتن', emoji: '📊'),
                  for (final c in caps)
                    Builder(builder: (context) {
                      final del = orders.where((d) => d.data()['captainUid'] == c.id && d.data()['status'] == 'delivered');
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Avatar(c.data()['photo'], size: 38),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${c.data()['name']}', style: TextStyle(fontWeight: FontWeight.w700)),
                              Text('${del.length} رحلة · أخد ${money(del.fold<double>(0, (s, d) => s + toD(d.data()['fee'])))}',
                                  style: TextStyle(color: kMuted, fontSize: 12)),
                            ]),
                          ),
                          Text(money(dueFor(orders, c.id)), style: TextStyle(color: kOrange2, fontWeight: FontWeight.w900)),
                        ]),
                      );
                    }),
                ])),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class BroadcastAdmin extends StatefulWidget {
  const BroadcastAdmin({super.key});
  @override
  State<BroadcastAdmin> createState() => _BroadcastAdminState();
}

class _BroadcastAdminState extends State<BroadcastAdmin> {
  String to = 'captains';
  final text = TextEditingController();
  bool busy = false;

  Future<void> _send() async {
    if (text.text.trim().isEmpty) return toast(context, 'اكتب الرسالة', error: true);
    setState(() => busy = true);
    await messagesCol.add({'to': to, 'text': text.text.trim(), 'createdAt': FieldValue.serverTimestamp()});
    text.clear();
    if (mounted) {
      setState(() => busy = false);
      toast(context, '✅ الرسالة اتبعتت');
    }
  }

  @override
  Widget build(BuildContext context) {
    const names = {'captains': '🛵 الكباتن', 'owners': '🏪 أصحاب المشاريع', 'all': '👥 الكل'};
    return Scaffold(
      appBar: AppBar(title: Text('📢 رسالة جماعية')),
      body: ListView(padding: EdgeInsets.all(16), children: [
        Box(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          BoxTitle('ابعت لـ'),
          Wrap(spacing: 8, children: [
            for (final e in names.entries)
              ChoiceChip(label: Text(e.value), selected: to == e.key, onSelected: (_) => setState(() => to = e.key)),
          ]),
          SizedBox(height: 12),
          TextField(controller: text, maxLines: 4, decoration: InputDecoration(hintText: 'مثلاً: النهارده النقط مضاعفة 🎉')),
          SizedBox(height: 12),
          Btn3D('📤 ابعت', busy: busy, onTap: _send),
        ])),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: messagesCol.orderBy('createdAt', descending: true).limit(50).snapshots(),
          builder: (context, snap) => Column(children: [
            for (final d in snap.data?.docs ?? [])
              Box(
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((d.data()['text'] ?? '').toString()),
                      SizedBox(height: 4),
                      Text('${names[d.data()['to']] ?? ''} · ${ago(d.data()['createdAt'])}', style: TextStyle(color: kMuted, fontSize: 12)),
                    ]),
                  ),
                  IconButton(icon: Icon(Icons.delete_outline, color: kMuted), onPressed: () => d.reference.delete()),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

class RedeemsAdmin extends StatelessWidget {
  const RedeemsAdmin({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('🎁 طلبات الهدايا')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: redeemsCol.orderBy('createdAt', descending: true).limit(100).snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          if (snap.hasData && docs.isEmpty) return EmptyView('مفيش طلبات هدايا', emoji: '🎁');
          return ListView(padding: EdgeInsets.all(16), children: [
            for (final d in docs)
              Box(
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${d.data()['gift']}', style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('${d.data()['captainName']} · ${d.data()['captainPhone']} · ${d.data()['points']} نقطة',
                          style: TextStyle(color: kMuted, fontSize: 12)),
                      Text(ago(d.data()['createdAt']), style: TextStyle(color: kMuted, fontSize: 11)),
                    ]),
                  ),
                  if (d.data()['status'] == 'pending') ...[
                    IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: kGreen),
                        tooltip: 'اتسلمت',
                        onPressed: () => d.reference.update({'status': 'done'}),
                        icon: Icon(Icons.check)),
                    IconButton(
                        tooltip: 'رفض ورجّع النقط',
                        onPressed: () async {
                          final b = db.batch();
                          b.update(d.reference, {'status': 'rejected'});
                          b.update(captainsCol.doc(d.data()['captainUid']), {'points': FieldValue.increment(toI(d.data()['points']))});
                          await b.commit();
                        },
                        icon: Icon(Icons.close, color: kRed)),
                  ] else
                    Pill(d.data()['status'] == 'done' ? 'اتسلمت ✅' : 'اترفضت', d.data()['status'] == 'done' ? kGreen : kRed),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class SosAdmin extends StatelessWidget {
  const SosAdmin({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('🆘 الطوارئ')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: sosCol.orderBy('createdAt', descending: true).limit(50).snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          if (snap.hasData && docs.isEmpty) return EmptyView('مفيش طوارئ الحمد لله', emoji: '✅');
          return ListView(padding: EdgeInsets.all(16), children: [
            for (final d in docs)
              Box(
                border: d.data()['status'] == 'open' ? kRed : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('🆘 ${d.data()['name']} · ${d.data()['phone']}', style: TextStyle(fontWeight: FontWeight.w800)),
                  Text(ago(d.data()['createdAt']), style: TextStyle(color: kMuted, fontSize: 12)),
                  SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(onPressed: () => callPhone(d.data()['phone'] ?? ''), icon: Icon(Icons.call), label: Text('اتصل')),
                    if (latLngOf(d.data()) != null)
                      OutlinedButton.icon(
                          onPressed: () => navigateTo(latLngOf(d.data())!.latitude, latLngOf(d.data())!.longitude),
                          icon: Icon(Icons.location_on),
                          label: Text('مكانه')),
                    if (d.data()['status'] == 'open')
                      OutlinedButton.icon(
                          onPressed: () => d.reference.update({'status': 'closed'}), icon: Icon(Icons.check), label: Text('اتحلت')),
                  ]),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class SettingsAdmin extends StatefulWidget {
  const SettingsAdmin({super.key});
  @override
  State<SettingsAdmin> createState() => _SettingsAdminState();
}

class _SettingsAdminState extends State<SettingsAdmin> {
  final maxDue = TextEditingController(), insta = TextEditingController(), voda = TextEditingController();
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    settingsRef.get().then((s) {
      final st = AppSettings(s.data());
      maxDue.text = st.maxDue.toStringAsFixed(0);
      insta.text = st.insta;
      voda.text = st.voda;
      if (mounted) setState(() => loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('⚙️ الإعدادات')),
      body: !loaded
          ? Loading()
          : ListView(padding: EdgeInsets.all(16), children: [
              Box(child: Column(children: [
                BoxTitle('العمولة', emoji: '💸'),
                KV('نسبة العمولة', '5% ثابتة على كل أوردر'),
                SizedBox(height: 10),
                TextField(
                  controller: maxDue,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: 'أقصى عمولة متأخرة مسموحة للكابتن', suffixText: 'ج', helperText: 'لو عدّاها مايقدرش يبقى أونلاين لحد ما يحوّل'),
                ),
                SizedBox(height: 12),
                TextField(controller: insta, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'رقم انستا باي')),
                SizedBox(height: 12),
                TextField(controller: voda, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'رقم فودافون كاش')),
                SizedBox(height: 14),
                Btn3D('حفظ ✅', onTap: () async {
                  await settingsRef.set({
                    'maxDue': double.tryParse(maxDue.text.trim()) ?? 150,
                    'insta': insta.text.trim(),
                    'voda': voda.text.trim(),
                  }, SetOptions(merge: true));
                  if (context.mounted) toast(context, '✅ اتحفظ');
                }),
              ])),
            ]),
    );
  }
}
