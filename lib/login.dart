import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'core.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool register = false;
  String role = 'owner';
  bool busy = false;
  bool hide = true;
  bool adminMode = false;
  final phone = TextEditingController();
  final name = TextEditingController();
  final extra = TextEditingController();
  final pass = TextEditingController();
  final pass2 = TextEditingController();
  String error = '';

  Future<void> _go() async {
    setState(() => error = '');
    final input = phone.text.trim();
    final isEmail = input.contains('@');
    if (isEmail && input.toLowerCase() != kAdminEmail.toLowerCase()) {
      setState(() => error = 'ادخل برقم موبايلك');
      return;
    }
    if (!isEmail && !validPhone(input)) {
      setState(() => error = 'اكتب رقم موبايل صحيح زي 01012345678');
      return;
    }
    if (pass.text.length < 6) {
      setState(() => error = 'كلمة السر لازم تكون 6 حروف أو أرقام على الأقل');
      return;
    }
    if (register && !isEmail) {
      if (name.text.trim().isEmpty) {
        setState(() => error = role == 'owner' ? 'اكتب اسم المشروع' : 'اكتب اسمك');
        return;
      }
      if (pass.text != pass2.text) {
        setState(() => error = 'كلمتين السر مش زي بعض');
        return;
      }
    }
    setState(() => busy = true);
    try {
      if (register) {
        final cred = await auth.createUserWithEmailAndPassword(email: loginToEmail(input), password: pass.text);
        if (!isEmail) {
          final id = cred.user!.uid;
          final p = normPhone(input);
          final n = name.text.trim();
          await usersCol.doc(id).set({
            'role': role,
            'phone': p,
            'name': n,
            'password': pass.text,
            'disabled': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          if (role == 'captain') {
            await captainsCol.doc(id).set(newCaptainDoc(n, p, extra.text.trim().isEmpty ? 'موتوسيكل' : extra.text.trim()));
          } else {
            await projectsCol.doc(id).set(newProjectDoc(n, p, n, extra.text.trim()));
          }
        }
      } else {
        await auth.signInWithEmailAndPassword(email: loginToEmail(input), password: pass.text);
      }
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _role(String r, String emoji, String title, String sub, List<Color> colors) {
    final on = role == r;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => role = r),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: on ? kPanel2 : kDeep,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? kOrange : kLine, width: on ? 2 : 1),
          ),
          child: Column(children: [
            Icon3D(emoji, colors: colors, size: 46),
            SizedBox(height: 10),
            Text(title, style: TextStyle(fontWeight: FontWeight.w800)),
            Text(sub, textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 11)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(center: Alignment(.6, -1.1), radius: 1.4, colors: [Color(0xFF2A1640), kBg]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 440),
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Image.asset('assets/icon.png', width: 96, height: 96),
                  ),
                  SizedBox(height: 14),
                  ShaderMask(
                    shaderCallback: (r) => LinearGradient(colors: [kOrange2, kRed]).createShader(r),
                    child: Text(kAppName, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                  Text('أقرب كابتن ليك.. في ثواني ⚡', style: TextStyle(color: kMuted, fontSize: 15)),
                  SizedBox(height: 22),
                  Container(
                    padding: EdgeInsets.all(5),
                    decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      for (final r in [false, true])
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              register = r;
                              error = '';
                            }),
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                gradient: register == r ? LinearGradient(colors: [kOrange, kRed]) : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(r ? 'حساب جديد' : 'دخول',
                                  style: TextStyle(fontWeight: FontWeight.w800, color: register == r ? Colors.white : kMuted)),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  SizedBox(height: 16),
                  if (register && !adminMode) ...[
                    Row(children: [
                      _role('owner', '🏪', 'صاحب مشروع', 'عاوز أبعت أوردرات', G3.pu),
                      SizedBox(width: 10),
                      _role('captain', '🛵', 'كابتن توصيل', 'عاوز أوصّل وأكسب', G3.gr),
                    ]),
                    SizedBox(height: 14),
                    TextField(
                      controller: name,
                      decoration: InputDecoration(
                          labelText: role == 'owner' ? 'اسم المشروع' : 'اسمك بالكامل',
                          prefixIcon: Icon(role == 'owner' ? Icons.storefront : Icons.person_outline)),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: extra,
                      decoration: InputDecoration(
                          labelText: role == 'owner' ? 'نوع المشروع (أكل، ملابس، ...)' : 'وسيلة التوصيل (موتوسيكل، عجلة، عربية)',
                          prefixIcon: Icon(role == 'owner' ? Icons.category_outlined : Icons.two_wheeler)),
                    ),
                    SizedBox(height: 12),
                  ],
                  TextField(
                    key: ValueKey(adminMode),
                    controller: phone,
                    keyboardType: adminMode ? TextInputType.emailAddress : TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                        labelText: adminMode ? 'إيميل الإدارة' : 'رقم الموبايل',
                        prefixIcon: Icon(adminMode ? Icons.admin_panel_settings_outlined : Icons.phone_iphone)),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: pass,
                    obscureText: hide,
                    decoration: InputDecoration(
                      labelText: 'كلمة السر',
                      prefixIcon: Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                          icon: Icon(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => hide = !hide)),
                    ),
                  ),
                  if (register) ...[
                    SizedBox(height: 12),
                    TextField(
                      controller: pass2,
                      obscureText: hide,
                      decoration: InputDecoration(labelText: 'كلمة السر تاني', prefixIcon: Icon(Icons.lock_outline)),
                    ),
                  ],
                  if (error.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(error, textAlign: TextAlign.center, style: TextStyle(color: kRed, fontWeight: FontWeight.w700)),
                    ),
                  SizedBox(height: 18),
                  Btn3D(register ? 'يلا نبدأ 🚀' : 'دخول', onTap: _go, busy: busy, fontSize: 18),
                  SizedBox(height: 6),
                  TextButton(
                    onPressed: () => setState(() {
                      adminMode = !adminMode;
                      phone.clear();
                    }),
                    child: Text(adminMode ? 'رجوع لدخول برقم الموبايل' : '👑 دخول الإدارة',
                        style: TextStyle(color: kMuted, fontSize: 12)),
                  ),
                  SizedBox(height: 8),
                  Text('⚡ أقرب كابتن · 📍 تتبع لحظي · 🔐 كود تسليم · 🎁 نقط وهدايا',
                      textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
