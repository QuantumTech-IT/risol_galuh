import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class RiwayatPage extends StatefulWidget {
  const RiwayatPage({super.key});

  @override
  State<RiwayatPage> createState() => _RiwayatPageState();
}

class _RiwayatPageState extends State<RiwayatPage> {
  List<Map<String, dynamic>> riwayat = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchRiwayat();
  }

  Future<void> fetchRiwayat() async {
    final res = await http.get(
      Uri.parse('https://bpjsapi.quantumtechapp.com/risol-api/get_penjualan.php'),
    );
    final data = jsonDecode(res.body);
    setState(() {
      riwayat = List<Map<String, dynamic>>.from(data);
      isLoading = false;
    });
  }

  void tampilkanDetail(Map<String, dynamic> data) {
    final items = List<Map<String, dynamic>>.from(data['items']);
    final detail = items.map((e) {
      return "- ${e['nama_brng']} (${e['jumlah']} ${e['satuan']}) = Rp${e['harga_total']}";
    }).join("\n");

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Nota: ${data['nota_jual']}"),
        content: Text("Tanggal: ${data['tgl_jual']}\n\n$detail"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Tutup"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Riwayat Transaksi")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : riwayat.isEmpty
              ? const Center(child: Text("Belum ada riwayat transaksi."))
              : ListView.builder(
                  itemCount: riwayat.length,
                  itemBuilder: (context, index) {
                    final item = riwayat[index];
                    return ListTile(
                      title: Text("Nota: ${item['nota_jual']}"),
                      subtitle: Text("Tanggal: ${item['tgl_jual']}\nTotal: Rp${item['total'] ?? 0}"),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.receipt),
                        onPressed: () => tampilkanDetail(item),
                      ),
                    );
                  },
                ),
    );
  }
}
