import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:risol_galuh/pages/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
//import '../utils/bluetooth_printer_helper.dart';
import '../utils/print_helper_stub.dart'
    if (dart.library.js) '../utils/print_helper_web.dart';
//import 'package:flutter/material.dart';
//import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:blue_thermal_printer/blue_thermal_printer.dart';

class InputPenjualanPage extends StatefulWidget {
  const InputPenjualanPage({super.key});

  @override
  State<InputPenjualanPage> createState() => _InputPenjualanPageState();
}

class _InputPenjualanPageState extends State<InputPenjualanPage> {
  // Variabel State
  
  List<Map<String, dynamic>> semuaBarang = [];
  List<Map<String, dynamic>> filteredList = [];
  List<Map<String, dynamic>> keranjang = [];
  List<Map<String, dynamic>> riwayatPenjualan = [];
  String metodeBayar = 'Cash';
  final List<String> opsiBayar = ['Cash', 'QRIS', 'Go Food'];
  final List<Map<String, dynamic>> _riwayatSementara = [];
  Map<String, dynamic>? selectedBarang;
  String cari = '';
  int currentPage = 1;
  int itemsPerPage = 5;
  final jumlahController = TextEditingController(text: '1');
  String satuan = 'PCS';
  bool _isAdmin = false;
  
  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadData();
  }

  Future<void> _loadRole() async {
  final prefs = await SharedPreferences.getInstance();
  final role = (prefs.getString('role') ?? '').toLowerCase();
  setState(() => _isAdmin = role == 'admin');
}
  Future<void> _loadData() async {
    await Future.wait([
      fetchBarang(),
      _loadRiwayatPenjualan(),
    ]);
  }

  // ==================== FUNGSI UTAMA ====================
  Future<void> fetchBarang() async {
    try {
      final res = await http.get(
        Uri.parse('https://bpjsapi.quantumtechapp.com/risol-api/get_obat.php'),
      );
      if (res.statusCode == 200) {
        setState(() {
          semuaBarang = List<Map<String, dynamic>>.from(jsonDecode(res.body));
          filteredList = semuaBarang;
        });
      }
    } catch (e) {
      _showError('Gagal memuat barang: $e');
    }
  }

  Future<void> _loadRiwayatPenjualan() async {
    try {
      final res = await http.get(
        Uri.parse('https://bpjsapi.quantumtechapp.com/risol-api/get_penjualan.php?limit=50'),
      );
      if (res.statusCode == 200) {
        setState(() {
          riwayatPenjualan = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      }
    } catch (e) {
      _showError('Gagal memuat riwayat: $e');
    }
  }

  // ==================== FUNGSI PENJUALAN ====================
  void handleCari(String keyword) {
    setState(() {
      cari = keyword;
      filteredList = semuaBarang
          .where((item) => item['nama_brng'].toLowerCase().contains(keyword.toLowerCase()))
          .toList();
      currentPage = 1;
    });
  }

  void tambahKeKeranjang(Map<String, dynamic> barang, int qty, String satuanInput) {
    final isi = satuanInput == 'BOX' ? (barang['isi'] ?? 1) : 1;
    final jumlahPcs = qty * isi;
    final hargaTotal = satuanInput == 'BOX'
        ? (barang['h_jual'] * isi * qty)
        : (barang['h_jual'] * qty);

    final index = keranjang.indexWhere((item) =>
        item['kode_brng'] == barang['kode_brng'] && item['satuan'] == satuanInput);

    setState(() {
      if (index != -1) {
        keranjang[index]['jumlah'] += qty;
        keranjang[index]['jumlah_pcs'] += jumlahPcs;
        keranjang[index]['harga_total'] += hargaTotal;
      } else {
        keranjang.add({
          ...barang,
          'jumlah': qty,
          'satuan': satuanInput,
          'jumlah_pcs': jumlahPcs,
          'harga_total': hargaTotal,
        });
      }
      selectedBarang = null;
      jumlahController.text = '1';
      satuan = 'PCS';
      cari = '';
      filteredList = semuaBarang;
    });
  }
  bool _isSaving = false;

Future<void> simpanTransaksi() async {
  // Cegah double tap
  if (_isSaving) return;

  _isSaving = true;
  setState(() {});

  try {
    if (keranjang.isEmpty) {
      _showError('Keranjang kosong!');
      return;
    }

    // Validasi stok
    final gagalStok = <String>[];
    for (var item in keranjang) {
      final stokTersedia = item['stok'] ?? 0;
      final jumlahPcs = item['jumlah_pcs'];
      if (jumlahPcs > stokTersedia) {
        gagalStok.add("${item['nama_brng']} (tersedia $stokTersedia, diminta $jumlahPcs)");
      }
    }

    if (gagalStok.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Stok tidak cukup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: gagalStok.map((e) => Text("❌ $e")).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
      return;
    }

    // Siapkan data items
    final items = keranjang.map((item) => {
      'kode_brng': item['kode_brng'],
      'jumlah': item['jumlah_pcs'],
      'satuan': item['satuan'],
      'jumlah_input': item['jumlah'],
      'harga_total': item['harga_total'],
    }).toList();

    final payload = {
      'kd_bangsal': '001',
      'items': items,
      'nama_bayar': metodeBayar,
    };

    // Debug request
    debugPrint('=== SIMPAN TRANSAKSI ===');
    debugPrint('URL: https://bpjsapi.quantumtechapp.com/risol-api/tambah_penjualan.php');
    debugPrint('REQUEST JSON: ${const JsonEncoder.withIndent("  ").convert(payload)}');

    // Kirim request
    final res = await http.post(
      Uri.parse('https://bpjsapi.quantumtechapp.com/risol-api/tambah_penjualan.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    // Debug response
    debugPrint('HTTP STATUS: ${res.statusCode}');
    debugPrint('RAW RESPONSE: ${res.body}');

    if (res.statusCode != 200) {
      _showError('HTTP ${res.statusCode}: Server error.');
      return;
    }

    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      final nota = data['nota'] ?? 'NOTA-${DateTime.now().millisecondsSinceEpoch}';
      final total = keranjang.fold<double>(0, (sum, item) => sum + item['harga_total']);

      await _cetakStruk(nota, DateFormat('yyyy-MM-dd').format(DateTime.now()), keranjang);
      setState(() {
        _riwayatSementara.insert(0, {
          'nota': nota,
          'tanggal': DateFormat('dd/MM/yy HH:mm').format(DateTime.now()),
          'items': List<Map<String, dynamic>>.from(keranjang),
          'total': total
        });
        keranjang.clear();
      });
      await _loadRiwayatPenjualan();
      _showSuccess('Transaksi $nota tersimpan!');
    } else {
      _showError(data['message'] ?? 'Gagal menyimpan transaksi');
    }
  } catch (e) {
    _showError('Error: $e');
  } finally {
    _isSaving = false;
    setState(() {});
  }
}
  // Future<void> simpanTransaksi() async {
  //   if (keranjang.isEmpty) {
  //     _showError('Keranjang kosong!');
  //     return;
  //   }

  //   // Validasi stok
  //   final gagalStok = <String>[];
  //   for (var item in keranjang) {
  //     final stokTersedia = item['stok'] ?? 0;
  //     final jumlahPcs = item['jumlah_pcs'];
  //     if (jumlahPcs > stokTersedia) {
  //       gagalStok.add("${item['nama_brng']} (tersedia $stokTersedia, diminta $jumlahPcs)");
  //     }
  //   }

  //   if (gagalStok.isNotEmpty) {
  //     showDialog(
  //       context: context,
  //       builder: (_) => AlertDialog(
  //         title: const Text('Stok tidak cukup'),
  //         content: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           children: gagalStok.map((e) => Text("❌ $e")).toList(),
  //         ),
  //         actions: [
  //           TextButton(
  //             onPressed: () => Navigator.pop(context),
  //             child: const Text('Tutup'),
  //           ),
  //         ],
  //       ),
  //     );
  //     return;
  //   }

  //   try {
  //     final items = keranjang.map((item) => {
  //       'kode_brng': item['kode_brng'],
  //       'jumlah': item['jumlah_pcs'],
  //       'satuan': item['satuan'],
  //       'jumlah_input': item['jumlah'],
  //       'harga_total': item['harga_total'],
  //     }).toList();

  //     final res = await http.post(
  //       Uri.parse('https://bpjsapi.quantumtechapp.com/risol-api/tambah_penjualan.php'),
  //       headers: {'Content-Type': 'application/json'},
  //       body: jsonEncode({'kd_bangsal': '001', 'items': items, 'nama_bayar': metodeBayar,}),
  //     );

  //     final data = jsonDecode(res.body);
  //     if (data['success'] == true) {
  //       final nota = data['nota'] ?? 'NOTA-${DateTime.now().millisecondsSinceEpoch}';
  //       final total = keranjang.fold<double>(0, (sum, item) => sum + item['harga_total']);

  //       await _cetakStruk(nota, DateFormat('yyyy-MM-dd').format(DateTime.now()), keranjang);
  //       setState(() {
  //       _riwayatSementara.insert(0, { // Tambahkan di awal list
  //         'nota': nota,
  //         'tanggal': DateFormat('dd/MM/yy HH:mm').format(DateTime.now()),
  //         'items': List<Map<String, dynamic>>.from(keranjang),
  //         'total': total
  //       });
  //       keranjang.clear();
  //     });
  //       await _loadRiwayatPenjualan();
  //        _showSuccess('Transaksi $nota tersimpan!');
  //     } else {
  //       _showError(data['message'] ?? 'Gagal menyimpan transaksi');
  //     }
  //   } catch (e) {
  //     _showError('Error: $e');
  //   }
  // }

  // ==================== FUNGSI HAPUS TRANSAKSI ====================
  Future<void> hapusPenjualan(String nota) async {
    try {
      final res = await http.delete(
        Uri.parse('https://bpjsapi.quantumtechapp.com/risol-api/tambah_penjualan.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'nota': nota}),
      );

      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        await _loadRiwayatPenjualan();
        _showSuccess('Penjualan $nota berhasil dihapus');
      } else {
        _showError(data['message'] ?? 'Gagal menghapus penjualan');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  void _showConfirmDelete(String nota) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Penjualan?'),
        content: Text('Yakin hapus transaksi $nota? Tindakan ini tidak dapat dibatalkan!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              hapusPenjualan(nota);
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

// ==================== FUNGSI CETAK STRUK ====================
Future<void> _cetakStruk(String nota, String tanggal, List<Map<String, dynamic>> keranjang) async {
  final grandTotal = keranjang.fold<double>(0, (acc, item) => acc + (item['harga_total'] ?? 0));

  try {
    if (kIsWeb) {
      // WEB: Cetak struk via HTML & window.print()
      final html = '''
        <html>
          <head><title>Struk $nota</title></head>
          <body onload="window.print()">
            <div style="text-align:center;font-weight:bold">Risol Galuh Shop</div>
            <div>Nota: $nota</div>
            <div>Tanggal: $tanggal</div>
            <hr>
            ${keranjang.map((item) => '''
              <div>
                ${item['nama_brng']} 
                (${item['jumlah']} ${item['satuan']})
                Rp${item['harga_total']}
              </div>
            ''').join('')}
            <hr>
            <div>Total: Rp$grandTotal</div>
          </body>
        </html>
      ''';
      // Panggil JS untuk print di Web (implementasi callJsPrint bisa disesuaikan)
      callJsPrint(html); // Pastikan fungsi ini ter-define di web
    } else {
      // ANDROID: Bluetooth printer
      bool isConnected = await bluetooth.isConnected ?? false;

      if (!isConnected) {
        List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
        if (devices.isEmpty) {
          throw Exception("Tidak ada printer terhubung.");
        }
        await bluetooth.connect(devices.first);
      }

      bluetooth.printNewLine();
      bluetooth.printCustom("Risol Galuh Shop", 2, 1);
      bluetooth.printCustom("=======================", 1, 1);
      bluetooth.printLeftRight("Nota", nota, 1);
      bluetooth.printLeftRight("Tanggal", tanggal, 1);
      bluetooth.printCustom("-----------------------", 1, 1);

      for (var item in keranjang) {
        bluetooth.printCustom("${item['nama_brng']} (${item['jumlah']} ${item['satuan']})", 1, 0);
        bluetooth.printLeftRight("Subtotal", "Rp${item['harga_total']}", 1);
      }

      bluetooth.printCustom("-----------------------", 1, 1);
      bluetooth.printLeftRight("TOTAL", "Rp${grandTotal.toStringAsFixed(0)}", 2);
      bluetooth.printNewLine();
      bluetooth.printCustom("Terima Kasih 🙏", 1, 1);
      bluetooth.printNewLine();
      bluetooth.paperCut();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Struk berhasil dicetak')),
      );
    }
  } catch (e) {
    _showError('Gagal cetak struk: $e');
    _showStrukDialog(nota, tanggal, keranjang, grandTotal);
  }
}

void _showStrukDialog(String nota, String tanggal, List<Map<String, dynamic>> keranjang, double grandTotal) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Struk $nota'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tanggal: $tanggal'),
            ...keranjang.map((item) => Text(
              "${item['nama_brng']} x${item['jumlah']} ${item['satuan']} = Rp${item['harga_total']}",
            )),
            const Divider(),
            Text("TOTAL: Rp${grandTotal.toStringAsFixed(0)}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

  // // ==================== FUNGSI CETAK STRUK ====================
  // Future<void> _cetakStruk(String nota, String tanggal) async {
  //   final grandTotal = keranjang.fold<double>(0, (acc, item) => acc + (item['harga_total'] ?? 0));

  //   try {
  //     if (kIsWeb) {
  //       final html = '''
  //         <html>
  //           <head><title>Struk $nota</title></head>
  //           <body onload="window.print()">
  //             <div style="text-align:center;font-weight:bold">Risol Galuh Shop</div>
  //             <div>Nota: $nota</div>
  //             <div>Tanggal: $tanggal</div>
  //             <hr>
  //             ${keranjang.map((item) => '''
  //               <div>
  //                 ${item['nama_brng']} 
  //                 (${item['jumlah']} ${item['satuan']})
  //                 Rp${item['harga_total']}
  //               </div>
  //             ''').join('')}
  //             <hr>
  //             <div>Total: Rp$grandTotal</div>
  //           </body>
  //         </html>
  //       ''';
  //       callJsPrint(html);
  //     } else {
  //       await BluetoothPrinterHelper.cetakStruk(
  //         nota: nota,
  //         tanggal: tanggal,
  //         keranjang: keranjang,
  //       );
  //     }
  //   } catch (e) {
  //     _showError('Gagal cetak struk: $e');
  //     _showStrukDialog(nota, tanggal, grandTotal);
  //   }
  // }

  // void _showStrukDialog(String nota, String tanggal, double grandTotal) {
  //   showDialog(
  //     context: context,
  //     builder: (_) => AlertDialog(
  //       title: Text('Struk $nota'),
  //       content: SingleChildScrollView(
  //         child: Column(
  //           children: [
  //             Text('Tanggal: $tanggal'),
  //             ...keranjang.map((item) => Text(
  //               "${item['nama_brng']} x${item['jumlah']} ${item['satuan']} = Rp${item['harga_total']}",
  //             )),
  //             const Divider(),
  //             Text("TOTAL: Rp${grandTotal.toStringAsFixed(0)}", 
  //                 style: const TextStyle(fontWeight: FontWeight.bold)),
  //           ],
  //         ),
  //       ),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context),
  //           child: const Text('Tutup'),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // ==================== UI COMPONENTS ====================
  void _showRiwayatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Riwayat Penjualan'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: riwayatPenjualan.length,
            itemBuilder: (context, index) {
              final item = riwayatPenjualan[index];
              return Card(
                child: ListTile(
                  title: Text('Nota: ${item['nota_jual']}'),
                  subtitle: Text('Tanggal: ${item['tgl_jual']}\nTotal: Rp${item['total']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _showConfirmDelete(item['nota_jual']),
                  ),
                ),
              );
            },
          )
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get paginatedItems {
    final start = (currentPage - 1) * itemsPerPage;
    final end = (start + itemsPerPage).clamp(0, filteredList.length);
    return filteredList.sublist(start, end);
  }

  // ==================== HELPER FUNCTIONS ====================
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  // ==================== BUILD METHOD ====================
  @override
  Widget build(BuildContext context) {
    final totalPages = (filteredList.length / itemsPerPage).ceil();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Input Penjualan'),
        actions: [
          if (_isAdmin)  
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showRiwayatDialog,
            tooltip: 'Riwayat Penjualan',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              onChanged: handleCari,
              decoration: const InputDecoration(
                labelText: 'Cari barang...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  ...paginatedItems.map((item) => ListTile(
                        title: Text(item['nama_brng']),
                        subtitle: Text('Harga: Rp${item['h_jual']} | Stok: ${item['stok']}'),
                        onTap: () {
                          setState(() {
                            selectedBarang = item;
                            jumlahController.text = '1';
                            satuan = 'PCS';
                          });
                        },
                      )),
                  if (selectedBarang != null) ...[
                    const Divider(),
                    Text('Tambah: ${selectedBarang!['nama_brng']}'),
                    TextField(
                      controller: jumlahController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Jumlah'),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('PCS'),
                          selected: satuan == 'PCS',
                          onSelected: (_) => setState(() => satuan = 'PCS'),
                        ),
                        if ((selectedBarang!['isi'] ?? 0) > 0)
                          ChoiceChip(
                            label: Text('BOX (${selectedBarang!['isi']} pcs)'),
                            selected: satuan == 'BOX',
                            onSelected: (_) => setState(() => satuan = 'BOX'),
                          ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () {
                        tambahKeKeranjang(
                          selectedBarang!,
                          int.tryParse(jumlahController.text) ?? 1,
                          satuan,
                        );
                      },
                      child: const Text('Tambah ke Keranjang'),
                    ),
                  ],
                  if (keranjang.isNotEmpty) ...[
                    const Divider(),
                    const Text('Keranjang:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...keranjang.map((item) => ListTile(
                          title: Text('${item['nama_brng']} (${item['jumlah']} ${item['satuan']})'),
                          subtitle: Text('Total: Rp${item['harga_total']}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setState(() => keranjang.remove(item));
                            },
                          ),
                        )),
                        // === Tambahkan ini untuk metode bayar ===
                      DropdownButtonFormField<String>(
                        value: metodeBayar,
                        decoration: const InputDecoration(labelText: "Metode Pembayaran"),
                        items: opsiBayar
                            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                            .toList(),
                        onChanged: (val) => setState(() => metodeBayar = val ?? 'Cash'),
                      ),
                      
                    ElevatedButton(
                      onPressed: _isSaving ? null : simpanTransaksi,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Simpan Transaksi'),
                    ),
                  ],
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: currentPage > 1 ? () => setState(() => currentPage--) : null,
                  child: const Text('← Sebelumnya'),
                ),
                Text('Halaman $currentPage/$totalPages'),
                ElevatedButton(
                  onPressed: currentPage < totalPages ? () => setState(() => currentPage++) : null,
                  child: const Text('Selanjutnya →'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}