import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? userRole = '';
  String? userName = '';

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    //loadUserInfo();
  }
  
  void _checkUserRole() async {
  final prefs = await SharedPreferences.getInstance();
  final role = prefs.getString('role');

  if (role == 'admin') {
    // biarkan di sini (admin bisa semua)
  } else if (role == 'kasir') {
    // misalnya redirect langsung ke input penjualan
    Navigator.pushReplacementNamed(context, '/input_penjualan');
  } else {
    // jika role tidak dikenali, keluar
    Navigator.pushReplacementNamed(context, '/login');
  }
}

  // Future<void> loadUserInfo() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   setState(() {
  //     userRole = prefs.getString('role');
  //     userName = prefs.getString('nama');
  //   });
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Selamat datang, $userName')),
      drawer: Drawer(
        child: ListView(
          children: [
            ListTile(title: const Text('Penjualan'), onTap: () => Navigator.pushNamed(context, '/input_penjualan')),
            if (userRole != 'kasir') // hanya admin/owner
              ListTile(title: const Text('Kelola Produk'), onTap: () => Navigator.pushNamed(context, '/produk')),
            ListTile(title: const Text('Riwayat'), onTap: () => Navigator.pushNamed(context, '/riwayat')),
          ],
        ),
      ),
      body: const Center(child: Text('Dashboard Kasir')),
    );
  }
}
