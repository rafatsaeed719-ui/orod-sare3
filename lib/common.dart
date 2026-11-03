import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core.dart';

/// رسايل الإدارة (للكباتن / لأصحاب المشاريع / للكل)
Stream<List<Map<String, dynamic>>> messagesFor(String audience) => messagesCol
    .orderBy('createdAt', descending: true)
    .limit(40)
    .snapshots()
    .map((s) => s.docs.map((d) => d.data()).where((m) => m['to'] == audience || m['to'] == 'all').toList());

class MessagesScreen extends StatelessWidget {
  final String audience;
  const MessagesScreen(this.audience, {super.key});
  @override
  Widget build(BuildContext context) {
    markMessagesSeen();
    return ListView(children: [
      Header('📢', 'رسايل الإدارة', 'آخر الأخبار والعروض', colors: G3.rd),
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: messagesFor(audience),
        builder: (context, snap) {
          if (!snap.hasData) return Loading();
          final list = snap.data!;
          if (list.isEmpty) return EmptyView('مفيش رسايل لسه', emoji: '📭');
          return sectionPad([
            for (final m in list)
              Box(
                padding: EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((m['text'] ?? '').toString(), style: TextStyle(fontSize: 15, height: 1.6)),
                  SizedBox(height: 6),
                  Text(ago(m['createdAt']), style: TextStyle(color: kMuted, fontSize: 11)),
                ]),
              ),
          ]);
        },
      ),
    ]);
  }
}

Future<void> markMessagesSeen() async {
  try {
    final p = await SharedPreferences.getInstance();
    await p.setInt('msgSeen', DateTime.now().millisecondsSinceEpoch);
  } catch (_) {}
}

/// عدد الرسايل الجديدة من آخر مرة اتفتحت
Stream<int> unreadMessages(String audience) async* {
  int seen = 0;
  try {
    final p = await SharedPreferences.getInstance();
    seen = p.getInt('msgSeen') ?? 0;
  } catch (_) {}
  yield* messagesFor(audience).map((l) => l.where((m) {
        final d = tsToDate(m['createdAt']);
        return d != null && d.millisecondsSinceEpoch > seen;
      }).length);
}

/// آخر رسالة من الإدارة (كارت صغير في الرئيسية)
class LatestMessage extends StatelessWidget {
  final String audience;
  final VoidCallback onOpen;
  const LatestMessage(this.audience, {super.key, required this.onOpen});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: messagesFor(audience),
        builder: (context, snap) {
          final l = snap.data ?? [];
          if (l.isEmpty) return SizedBox();
          final m = l.first;
          return Box(
            onTap: onOpen,
            border: kOrange.withValues(alpha: .6),
            child: Row(children: [
              Icon3D('📢', colors: G3.rd, size: 42),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('رسالة من الإدارة · ${ago(m['createdAt'])}', style: TextStyle(color: kMuted, fontSize: 12)),
                  Text((m['text'] ?? '').toString(),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
          );
        },
      );
}

/// شريط التنقل السفلي بأيقونات بارزة
class OrodNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(String, String)> items;
  final Map<int, int> badges;
  const OrodNav({super.key, required this.index, required this.onTap, required this.items, this.badges = const {}});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Color(0xF2121530), border: Border(top: BorderSide(color: kLine))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onTap(i),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Stack(clipBehavior: Clip.none, children: [
                        AnimatedScale(
                          scale: index == i ? 1.2 : 1,
                          duration: Duration(milliseconds: 200),
                          child: AnimatedOpacity(
                            opacity: index == i ? 1 : .55,
                            duration: Duration(milliseconds: 200),
                            child: Text(items[i].$1,
                                style: TextStyle(fontSize: 23, shadows: [
                                  if (index == i) Shadow(color: kOrange.withValues(alpha: .7), blurRadius: 12, offset: Offset(0, 4)),
                                ])),
                          ),
                        ),
                        if ((badges[i] ?? 0) > 0)
                          Positioned(
                            top: -4,
                            left: -8,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: kRed, borderRadius: BorderRadius.circular(99)),
                              child: Text('${badges[i]}',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
                            ),
                          ),
                      ]),
                      SizedBox(height: 3),
                      Text(items[i].$2,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700, color: index == i ? kOrange2 : kMuted)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// مراحل الأوردر
class OrderTimeline extends StatelessWidget {
  final String status;
  const OrderTimeline(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    const steps = ['pending', 'accepted', 'picked', 'onway', 'arrived', 'delivered'];
    const labels = ['الأوردر اتبعت', 'الكابتن وافق وجاي يستلم', 'استلم الأوردر', 'في الطريق للعميل', 'وصل للعميل', 'تم التسليم 🎉'];
    final cur = steps.indexOf(status);
    return Column(children: [
      for (var k = 0; k < steps.length; k++)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: k < cur || status == 'delivered' ? kGreen : (k == cur ? kOrange : kLine),
                boxShadow: k == cur && status != 'delivered'
                    ? [BoxShadow(color: kOrange.withValues(alpha: .6), blurRadius: 10, spreadRadius: 2)]
                    : (k < cur ? [BoxShadow(color: kGreen.withValues(alpha: .5), blurRadius: 8)] : null),
              ),
            ),
            if (k < steps.length - 1) Container(width: 2, height: 22, color: k < cur ? kGreen : kLine),
          ]),
          SizedBox(width: 12),
          Text(labels[k],
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: k == cur && status != 'delivered' ? kOrange2 : (k <= cur ? kTxt : kMuted))),
        ]),
    ]);
  }
}

/// آخر رقم أوردر (عشوائي قصير من الوقت)
int newOrderNo() => DateTime.now().millisecondsSinceEpoch % 1000000;

/// كل الأوردرات بتاعة حقل معين (بدون orderBy عشان مايحتاجش index) ومترتبة من الأحدث
Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> ordersWhere(String field, String value) =>
    ordersCol.where(field, isEqualTo: value).snapshots().map((s) {
      final l = s.docs.toList();
      l.sort((a, b) {
        final x = tsToDate(a.data()['createdAt']) ?? DateTime.now();
        final y = tsToDate(b.data()['createdAt']) ?? DateTime.now();
        return y.compareTo(x);
      });
      return l;
    });

/// زرار خروج
Future<void> signOutAsk(BuildContext context) async {
  if (await confirm(context, 'خروج', 'متأكد إنك عاوز تخرج من الحساب؟', ok: 'خروج')) {
    await auth.signOut();
  }
}
