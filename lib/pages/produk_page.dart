import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ProdukPage extends StatefulWidget {
  const ProdukPage({super.key});

  @override
  State<ProdukPage> createState() => _ProdukPageState();
}

class _ProdukPageState extends State<ProdukPage> {
  List<Map<String, dynamic>> produk = [];
  List<Map<String, dynamic>> filtered = [];
  String cari = '';

  @override
  void initState() {
    super.initState();
    fetchProduk();
  }

  Future<void> fetchProduk() async {
    final res = await http.get(Uri.parse('https://bpjsapi.quantumtechapp.com/risol-api/get_obat.php'));
    final data = jsonDecode(res.body);

    setState(() {
      produk = List<Map<String, dynamic>>.from(data);
      filtered = produk;
    });
  }

  void filter(String keyword) {
    setState(() {
      cari = keyword;
      filtered = produk
          .where((item) =>
              item['nama_brng'].toString().toLowerCase().contains(keyword.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Produk'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Cari produk...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: filter,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Produk tidak ditemukan'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        return Card(
                          elevation: 2,
                          child: ListTile(
                            title: Text(item['nama_brng']),
                            subtitle: Text('Stok: ${item['stok']} | Harga: Rp${item['h_jual']}'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
