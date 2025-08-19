import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/input_penjualan_page.dart';
import 'pages/laporan_page.dart';
import 'pages/produk_page.dart';
import 'pages/stok_page.dart';
import 'pages/layanan_page.dart';
import 'pages/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init locale Indonesia untuk DateFormat, dsb.
  await initializeDateFormatting('id_ID', null);
  Intl.defaultLocale = 'id_ID';

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aplikasi Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),

      // Aktifkan localization Material/Cupertino
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('id', 'ID'),
        Locale('en', 'US'), // fallback
      ],
      locale: const Locale('id', 'ID'),

      home: const LoginPage(), // Halaman awal
      routes: {
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/input_penjualan': (context) => const InputPenjualanPage(),
        '/laporan': (context) => const LaporanPage(),
        '/produk': (context) => const ProdukPage(),
        '/stok': (context) => const StokPage(),
        '/layanan': (context) => const LayananPage(),
        '/dashboard': (context) => const DashboardPage(),
        '/riwayat': (context) => const LaporanPage(),
      },
    );
  }
}
