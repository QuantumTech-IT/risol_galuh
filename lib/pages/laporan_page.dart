import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:risol_galuh/pages/login_page.dart';

final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

/* ---------- Helpers & models ---------- */

class ItemSummary {
  final int pcs;
  final double omzet; // qty * harga
  const ItemSummary({this.pcs = 0, this.omzet = 0});
  ItemSummary add(int q, double h) => ItemSummary(pcs: pcs + q, omzet: omzet + q * h);
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  final s = v.toString().replaceAll(RegExp(r'[^0-9-]'), '');
  return int.tryParse(s) ?? 0;
}

double _toDouble(dynamic v) {
  if (v == null) return 0;
  final s = v.toString().replaceAll(RegExp(r'[^0-9.-]'), '');
  return double.tryParse(s) ?? 0.0;
}

String rupiah(num v) => 'Rp${v.toStringAsFixed(0).replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';

/* -------------------------------------- */

class LaporanPage extends StatefulWidget {
  const LaporanPage({super.key});
  @override
  State<LaporanPage> createState() => _LaporanPageState();
}

class _LaporanPageState extends State<LaporanPage> {
  final _idr = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

  // data mentah dari API (flat/tiap baris 1 item)
  List<Map<String, dynamic>> data = [];
  bool isLoading = true;

  // filter tanggal (default hari ini)
  DateTime tglAwal = DateTime.now();
  DateTime tglAkhir = DateTime.now();

  // ringkasan total
  double totalPenjualan = 0;
  int totalItemTerjual = 0;

  // ringkasan per item (di-state)
  Map<String, ItemSummary> ringkasanPerItem = {};
  List<MapEntry<String, ItemSummary>> ringkasanSorted = [];

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
      ringkasanPerItem = {};
      ringkasanSorted = [];
    });

    final tAwal = DateFormat('yyyy-MM-dd').format(tglAwal);
    final tAkhir = DateFormat('yyyy-MM-dd').format(tglAkhir);

    try {
      final res = await http.get(Uri.parse(
        'https://bpjsapi.quantumtechapp.com/risol-api/get_riwayat_transaksi.php?tgl_awal=$tAwal&tgl_akhir=$tAkhir',
      ));
      final json = jsonDecode(res.body);

      if (json['success'] == true) {
        final list = List<Map<String, dynamic>>.from(json['data']);

        double sumRp = 0;
        int sumQty = 0;
        final Map<String, ItemSummary> perItem = {};

        for (final r in list) {
          // total semua
          sumRp += _toDouble(r['total']);   // ini subtotal baris (qty * h_jual)
          sumQty += _toInt(r['jumlah']);

          // ringkasan per item dari kolom yang dipakai di UI
          final nama  = (r['nama_brng'] ?? '').toString().trim().toUpperCase();
          final qty   = _toInt(r['jumlah']);
          final harga = _toDouble(r['h_jual']);
          if (nama.isEmpty || qty == 0) continue;
          perItem[nama] = (perItem[nama] ?? const ItemSummary()).add(qty, harga);
        }

        final sorted = perItem.entries.toList()
          ..sort((a, b) => b.value.pcs.compareTo(a.value.pcs));

        setState(() {
          data = list;
          totalPenjualan = sumRp;
          totalItemTerjual = sumQty;
          ringkasanPerItem = perItem;
          ringkasanSorted = sorted;
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

  // group baris flat menjadi per nota
  Map<String, List<Map<String, dynamic>>> _groupByNota(List<Map<String, dynamic>> rows) {
    final g = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final k = r['nota_jual'].toString();
      g.putIfAbsent(k, () => []).add(r);
    }
    return g;
  }

  // cetak laporan (tetap seperti yang kamu punya)
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
          final j  = _toInt(r['jumlah']);
          final hj = _toInt(r['h_jual']);
          final sub = _toDouble(r['total']);
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Struk berhasil dicetak')),
        );
      }
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

  /* ---------- UI helpers inside State ---------- */

  Widget ringkasanChips() {
    if (ringkasanSorted.isEmpty) {
      return const Text(
        'Belum ada ringkasan untuk rentang tanggal ini',
        style: TextStyle(color: Colors.black54, fontSize: 12),
      );
    }
    final shown = ringkasanSorted.take(6).toList(); // tampilkan 6 dulu
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: shown.map((e) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 3, 228, 153),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xffE0E0E0)),
        ),
        child: Text(
          "${e.key}: ${e.value.pcs} pcs • ${rupiah(e.value.omzet)}",
          style: const TextStyle(fontSize: 12),
        ),
      )).toList(),
    );
  }

  void _lihatSemuaRingkasan(BuildContext ctx) {
    if (ringkasanSorted.isEmpty) return;
    Navigator.push(ctx, MaterialPageRoute(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Ringkasan Per Item')),
      body: ListView.separated(
        itemCount: ringkasanSorted.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = ringkasanSorted[i];
          return ListTile(
            title: Text(e.key),
            trailing: Text(
              "${e.value.pcs} pcs • ${rupiah(e.value.omzet)}",
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    )));
  }

  /* -------------------------------------------- */

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
            padding: const EdgeInsets.all(5.0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pilihTanggal(context, true),
                    child: _DateBoxMini(label: "Awal", date: tglAwal),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: InkWell(
                    onTap: () => _pilihTanggal(context, false),
                    child: _DateBoxMini(label: "Akhir", date: tglAkhir),
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

          // Ringkasan (Card)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "Ringkasan per Item",
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _lihatSemuaRingkasan(context),
                          icon: const Icon(Icons.list_alt, size: 16),
                          label: const Text("Lihat semua", style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ringkasanChips(),
                    const Divider(height: 24),
                    Row(
                      children: [
                        const Text('Total Penjualan: ', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(_idr.format(totalPenjualan),
                            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('Total Item Terjual: ', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text("$totalItemTerjual pcs",
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),

          // daftar per nota
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

                          double total = 0;
                          int totalItemNota = 0;
                          for (final r in rows) {
                            total += _toDouble(r['total']);
                            totalItemNota += _toInt(r['jumlah']);
                          }

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Nota: $nota", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text("Tanggal: ${first['tgl_jual']}"),
                                  Text("Cara Bayar: ${first['nama_bayar'] ?? '-'}"),
                                  const Divider(),
                                  ...rows.map((r) => Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(child: Text("${r['nama_brng']}")),
                                          Text("${r['jumlah']} x ${_idr.format(_toInt(r['h_jual']))}"),
                                          Text("= ${_idr.format(_toDouble(r['total']))}"),
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

/* ---------- Mini DateBox ---------- */

class _DateBoxMini extends StatelessWidget {
  final String label;
  final DateTime? date;

  const _DateBoxMini({required this.label, this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          Text(
            date != null ? "${date!.day}-${date!.month}-${date!.year}" : "-",
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}
