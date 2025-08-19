import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:risol_galuh/pages/login_page.dart';

class LaporanPage extends StatefulWidget {
  const LaporanPage({super.key});
  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

class _LaporanPageState extends State<LaporanPage> {
  List<Map<String, dynamic>> data = [];
  bool isLoading = true;

  // filter tanggal (default hari ini)
  DateTime tglAwal = DateTime.now();
  DateTime tglAkhir = DateTime.now();

  // ringkasan
  double totalPenjualan = 0; // Rp
  int totalItemTerjual = 0;  // pcs

  final _idr = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    fetchRiwayat();
  }

  Future<void> fetchRiwayat() async {
    setState(() {
      isLoading = true;
      totalPenjualan = 0;
      totalItemTerjual = 0;
    });

    final tAwal = DateFormat('yyyy-MM-dd').format(tglAwal);
    final tAkhir = DateFormat('yyyy-MM-dd').format(tglAkhir);

    try {
      final res = await http.get(Uri.parse(
          'https://bpjsapi.quantumtechapp.com/risol-api/get_riwayat_transaksi.php?tgl_awal=$tAwal&tgl_akhir=$tAkhir'));
      final json = jsonDecode(res.body);

      if (json['success'] == true) {
        final list = List<Map<String, dynamic>>.from(json['data']);

        // hitung ringkasan
        double sumRp = 0;
        int sumQty = 0;
        for (final r in list) {
          sumRp += (double.tryParse(r['total'].toString()) ?? 0);
          sumQty += (int.tryParse(r['jumlah'].toString()) ?? 0);
        }

        setState(() {
          data = list;
          totalPenjualan = sumRp;
          totalItemTerjual = sumQty;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(json['message'] ?? "Gagal memuat data")),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal ambil data: $e")),
      );
    }
  }

  Future<void> _pilihTanggal(BuildContext context, bool isAwal) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isAwal ? tglAwal : tglAkhir,
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
      locale: const Locale('id', 'ID'),
    );
    if (picked != null) {
      setState(() {
        if (isAwal) {
          tglAwal = picked;
          if (tglAkhir.isBefore(tglAwal)) tglAkhir = picked;
        } else {
          tglAkhir = picked;
          if (tglAwal.isAfter(tglAkhir)) tglAwal = picked;
        }
      });
      fetchRiwayat();
    }
  }

  // group by nota_jual
  Map<String, List<Map<String, dynamic>>> _groupByNota(List<Map<String, dynamic>> rows) {
    final g = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final k = r['nota_jual'].toString();
      g.putIfAbsent(k, () => []).add(r);
    }
    return g;
  }

  // cetak laporan harian (opsional, tidak diubah)
  void cetakLaporanHarian() async {
    final tanggal = DateFormat('yyyy-MM-dd').format(tglAwal);
    final transaksiHariIni = data.where((e) => e['tgl_jual'].toString().startsWith(tanggal)).toList();

    if (transaksiHariIni.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada transaksi untuk tanggal ini.')),
      );
      return;
    }

    final g = _groupByNota(transaksiHariIni);

    try {
      bool isConnected = await bluetooth.isConnected ?? false;
      if (!isConnected) {
        final devices = await bluetooth.getBondedDevices();
        if (devices.isEmpty) throw Exception("Tidak ada printer terhubung.");
        await bluetooth.connect(devices.first);
      }

      double grandTotal = 0;
      int grandQty = 0;

      bluetooth.printNewLine();
      bluetooth.printCustom("LAPORAN HARIAN", 3, 1);
      bluetooth.printCustom("====================", 1, 1);
      bluetooth.printLeftRight("Tanggal", tanggal, 1);
      bluetooth.printCustom("--------------------", 1, 1);

      for (final entry in g.entries) {
        final rows = entry.value;
        final first = rows.first;
        double total = 0;
        int qty = 0;

        bluetooth.printCustom("${first['nota_jual']}", 1, 0);
        bluetooth.printLeftRight("Bayar", "${first['nama_bayar'] ?? '-'}", 1);

        for (final r in rows) {
          final nm = r['nama_brng'];
          final j = int.tryParse(r['jumlah'].toString()) ?? 0;
          final hj = int.tryParse(r['h_jual'].toString()) ?? 0;
          final sub = double.tryParse(r['total'].toString()) ?? 0;
          qty += j;
          total += sub;
          bluetooth.printCustom("$nm x$j @${_idr.format(hj)}", 1, 0);
        }

        bluetooth.printLeftRight("Subtotal", _idr.format(total), 1);
        bluetooth.printLeftRight("Item", "$qty pcs", 1);
        bluetooth.printCustom("--------------------", 1, 1);

        grandTotal += total;
        grandQty += qty;
      }

      bluetooth.printLeftRight("TOTAL", _idr.format(grandTotal), 2);
      bluetooth.printLeftRight("TOTAL ITEM", "$grandQty pcs", 2);
      bluetooth.printCustom("====================", 1, 1);
      bluetooth.printCustom("Close Kasir ✅", 1, 1);
      bluetooth.printNewLine();
      bluetooth.paperCut();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Struk berhasil dicetak')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Gagal cetak: $e")),
      );
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByNota(data).entries.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Riwayat Transaksi"),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Cetak Laporan (tgl awal)',
            onPressed: cetakLaporanHarian,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: logout,
          ),
        ],
      ),
      body: Column(
        children: [
          // filter tanggal
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pilihTanggal(context, true),
                    child: _DateBox(label: "Awal", date: tglAwal),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => _pilihTanggal(context, false),
                    child: _DateBox(label: "Akhir", date: tglAkhir),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Muat Ulang',
                  onPressed: fetchRiwayat,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),

          // ringkasan total rupiah + total item
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Text('Total Penjualan: ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(_idr.format(totalPenjualan),
                    style: const TextStyle(
                        color: Colors.blue, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Text('Total Item Terjual: ',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('$totalItemTerjual pcs',
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          ),

          const SizedBox(height: 4),

          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : grouped.isEmpty
                    ? const Center(child: Text("Belum ada riwayat transaksi."))
                    : ListView.builder(
                        itemCount: grouped.length,
                        itemBuilder: (context, index) {
                          final entry = grouped[index];
                          final nota = entry.key;
                          final rows = entry.value;
                          final first = rows.first;

                          // hitung total per nota + total item per nota
                          double total = 0;
                          int totalItemNota = 0;
                          for (final r in rows) {
                            total += (double.tryParse(r['total'].toString()) ?? 0);
                            totalItemNota += (int.tryParse(r['jumlah'].toString()) ?? 0);
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Nota: $nota",
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text("Tanggal: ${first['tgl_jual']}"),
                                  Text("Cara Bayar: ${first['nama_bayar'] ?? '-'}"),
                                  const Divider(),
                                  ...rows.map((r) => Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(child: Text("${r['nama_brng']}")),
                                          Text("${r['jumlah']} x ${_idr.format(int.tryParse(r['h_jual'].toString()) ?? 0)}"),
                                          Text("= ${_idr.format(double.tryParse(r['total'].toString()) ?? 0)}"),
                                        ],
                                      )),
                                  const Divider(),
                                  Text("TOTAL: ${_idr.format(total)}",
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text("TOTAL ITEM: $totalItemNota pcs",
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  final String label;
  final DateTime date;
  const _DateBox({required this.label, required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blueGrey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range),
          const SizedBox(width: 8),
          Text("$label: ${DateFormat('dd/MM/yyyy').format(date)}"),
        ],
      ),
    );
  }
}
