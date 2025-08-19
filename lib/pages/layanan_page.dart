import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard_page.dart';
import 'laporan_page.dart';
import 'input_penjualan_page.dart';
import 'stok_page.dart';

class LayananPage extends StatefulWidget {
  const LayananPage({super.key});

  @override
  State<LayananPage> createState() => _LayananPageState();
}

class _LayananPageState extends State<LayananPage> {
  String? role;
  List<Map<String, dynamic>> menuLayanan = [];

  final List<Map<String, dynamic>> semuaMenu = [
    {
      'icon': Icons.analytics,
      'title': 'Dashboard Penjualan Harian',
      'page': const DashboardPage(),
      'akses': ['admin'], // hanya admin
    },
    {
      'icon': Icons.receipt_long,
      'title': 'Laporan Penjualan Harian',
      'page': const LaporanPage(),
      'akses': ['admin', 'kasir'], // semua
    },
    {
      'icon': Icons.add_shopping_cart,
      'title': 'Input Penjualan',
      'page': const InputPenjualanPage(),
      'akses': ['admin', 'kasir'], // semua
    },
    {
      'icon': Icons.inventory,
      'title': 'Manajemen Stok',
      'page': const StokPage(),
      'akses': ['admin'], // hanya admin
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final storedRole = prefs.getString('role') ?? '';
    setState(() {
      role = storedRole;
      menuLayanan = semuaMenu.where((item) => item['akses'].contains(role)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Menu Penjualan Risol')),
      body: menuLayanan.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: menuLayanan.length,
              itemBuilder: (context, index) {
                final item = menuLayanan[index];
                return Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    leading: Icon(item['icon'], color: Colors.deepPurple),
                    title: Text(item['title']),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => item['page']),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
