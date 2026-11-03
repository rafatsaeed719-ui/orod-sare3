import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'admin.dart';
import 'captain.dart';
import 'core.dart';
import 'firebase_options.dart';
import 'login.dart';
import 'owner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: orodFirebaseOptions);
  runApp(OrodApp());
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kOrange, brightness: Brightness.dark).copyWith(
    primary: kOrange,
    onPrimary: Colors.white,
    secondary: kOrange2,
    surface: kPanel,
    onSurface: kTxt,
    error: kRed,
    secondaryContainer: kOrange.withValues(alpha: .25),
    onSecondaryContainer: kTxt,
    surfaceContainerHighest: kPanel2,
    outline: kLine,
  );
  final radius = BorderRadius.circular(14);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Tajawal',
    scaffoldBackgroundColor: kBg,
    dividerColor: kLine,
    appBarTheme: AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kTxt,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(fontFamily: 'Tajawal', fontSize: 19, fontWeight: FontWeight.w800, color: kTxt),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: kLine)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: kLine)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: kOrange, width: 1.6)),
      filled: true,
      fillColor: Color(0xFF0F1330),
      labelStyle: TextStyle(color: kMuted),
      hintStyle: TextStyle(color: kMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: kOrange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
          foregroundColor: kTxt, side: BorderSide(color: kLine), padding: EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: kOrange2)),
    chipTheme: ChipThemeData(
      backgroundColor: kDeep,
      selectedColor: kOrange,
      side: BorderSide(color: kLine),
      labelStyle: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: kDeep,
        selectedBackgroundColor: kOrange,
        selectedForegroundColor: Colors.white,
        side: BorderSide(color: kLine),
      ),
    ),
    dialogTheme: DialogThemeData(backgroundColor: kPanel, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: kPanel, surfaceTintColor: Colors.transparent),
    listTileTheme: ListTileThemeData(textColor: kTxt, iconColor: kMuted),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class OrodApp extends StatelessWidget {
  const OrodApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      locale: Locale('ar'),
      supportedLocales: [Locale('ar'), Locale('en')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(),
      home: AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return Scaffold(body: Loading());
        final user = snap.data;
        if (user == null) return LoginScreen();
        if (isAdmin) return AdminHome(key: ValueKey('admin'));
        return _RoleGate(key: ValueKey(user.uid));
      },
    );
  }
}

class _RoleGate extends StatelessWidget {
  const _RoleGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: usersCol.doc(uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return Scaffold(body: Loading());
        final me = snap.data!.data();
        if (me == null) {
          return Scaffold(
            body: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              EmptyView('بنجهز حسابك...', emoji: '⏳', text: 'لو الشاشة دي فضلت كتير اخرج وادخل تاني'),
              TextButton(onPressed: () => auth.signOut(), child: Text('خروج')),
            ]),
          );
        }
        if (me['disabled'] == true) {
          return Scaffold(
            body: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              EmptyView('الحساب ده موقوف', emoji: '⛔', text: 'كلّم إدارة «أورد على السريع» عشان يتفعّل تاني'),
              TextButton(onPressed: () => auth.signOut(), child: Text('خروج')),
            ]),
          );
        }
        if (me['role'] == 'captain') return CaptainHome();
        return OwnerHome();
      },
    );
  }
}
