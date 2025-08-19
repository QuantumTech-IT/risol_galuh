import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class StokPage extends StatefulWidget {
  const StokPage({super.key});
  @override
  State<StokPage> createState() => _StokPageState();
}

class _StokPageState extends State<StokPage> {
  List<Map<String, dynamic>> barangList = [];
  bool isLoading = false;
  String search = '';
  int currentPage = 1;
  final int itemsPerPage = 10;

  // Form field
  final kodeController = TextEditingController();
  final namaController = TextEditingController();
  final hBeliController = TextEditingController();
  final hJualController = TextEditingController();
  final stokController = TextEditingController();
  final persenProfitController = TextEditingController(text: '30');
  bool isSaving = false;
  bool editMode = false;

  @override
  void initState() {
    super.initState();
    fetchBarang();
  }

  Future<void> fetchBarang() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('https://bpjsapi.quantumtechapp.com/risol-api/get_obat.php'));
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        setState(() {
          barangList = data.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      } else {
        showError('Gagal load data: ${res.statusCode}');
      }
    } catch (e) {
      showError('Gagal load data: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  void showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  int bulatRibu(num angka) {
    if (angka == 0) return 0;
    return ((angka / 1000).ceil() * 1000);
  }

  double hitungProfitPersen(int hargaBeli, int hargaJual) {
    if (hargaJual == 0) return 0;
    return ((hargaJual - hargaBeli) / hargaJual) * 100;
  }

  int hargaJualMargin(int hargaModal, double persen) {
    if (persen >= 100) return 0;
    final hasil = hargaModal / (1 - persen / 100);
    return bulatRibu(hasil);
  }

  void startEdit(Map<String, dynamic> barang) {
    setState(() {
      editMode = true;
      kodeController.text = barang['kode_brng'].toString();
      namaController.text = barang['nama_brng'] ?? '';
      hBeliController.text = barang['h_beli'].toString();
      stokController.text = barang['stok'].toString();

      final hBeli = int.tryParse(barang['h_beli'].toString()) ?? 0;
      final hJual = int.tryParse(barang['h_jual'].toString()) ?? 0;
      final profit = hitungProfitPersen(hBeli, hJual);
      persenProfitController.text = profit.toStringAsFixed(2);
      hJualController.text = hJual.toString();
    });
  }

  void resetForm() {
    setState(() {
      editMode = false;
      kodeController.clear();
      namaController.clear();
      hBeliController.clear();
      hJualController.clear();
      stokController.clear();
      persenProfitController.text = '30';
    });
  }

  Future<void> simpanBarang() async {
    final kode = kodeController.text.trim();
    final nama = namaController.text.trim();
    final hBeli = int.tryParse(hBeliController.text) ?? 0;
    final hJual = int.tryParse(hJualController.text) ?? 0;
    final stok = int.tryParse(stokController.text) ?? 0;

    if (kode.isEmpty || nama.isEmpty || hBeli <= 0 || hJual <= 0) {
      showError('Isi kode, nama, harga beli, dan harga jual dengan benar');
      return;
    }

    setState(() => isSaving = true);

    final data = {
      'kode_brng': kode,
      'nama_brng': nama,
      'h_beli': hBeli,
      'h_jual': hJual,
      'stok': stok,
    };

    final url = editMode
        ? 'https://bpjsapi.quantumtechapp.com/risol-api/edit-obat.php'
        : 'https://bpjsapi.quantumtechapp.com/risol-api/tambah-obat.php';

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      final text = res.body;
      final json = jsonDecode(text);
      if (json['success'] == true || (json['message']?.toString().contains("berhasil") ?? false)) {
        showSuccess(json['message'] ?? (editMode ? 'Barang diupdate!' : 'Barang ditambah!'));
        resetForm();
        fetchBarang();
      } else {
        showError(json['message'] ?? 'Gagal simpan data');
      }
    } catch (e) {
      showError('Error: $e');
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = barangList
        .where((item) =>
            item['nama_brng'].toString().toLowerCase().contains(search.toLowerCase()))
        .toList();

    final paginatedList = filteredList
        .skip((currentPage - 1) * itemsPerPage)
        .take(itemsPerPage)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Stok & Barang Baru')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Form Tambah/Edit Barang
                  Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            editMode ? 'Edit Barang' : 'Tambah Barang Baru',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: kodeController,
                            decoration: const InputDecoration(labelText: 'Kode Barang'),
                            enabled: !editMode,
                          ),
                          TextField(
                            controller: namaController,
                            decoration: const InputDecoration(labelText: 'Nama Barang'),
                          ),
                          TextField(
                            controller: hBeliController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Harga Beli'),
                            onChanged: (val) {
                              final hBeli = int.tryParse(val) ?? 0;
                              double persen = double.tryParse(persenProfitController.text) ?? 0;
                              if (hBeli > 0 && persen < 100) {
                                final hj = hargaJualMargin(hBeli, persen);
                                hJualController.text = hj.toString();
                              } else {
                                hJualController.text = '';
                              }
                            },
                          ),
                          Row(
                            children: [
                              const Text('Profit (%)'),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 70,
                                child: TextField(
                                  controller: persenProfitController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    suffixText: '%',
                                  ),
                                  onChanged: (val) {
                                    double persen = double.tryParse(val) ?? 0;
                                    if (persen < 0) persen = 0;
                                    if (persen > 99) persen = 99;
                                    final hBeli = int.tryParse(hBeliController.text) ?? 0;
                                    if (hBeli > 0 && persen < 100) {
                                      final hj = hargaJualMargin(hBeli, persen);
                                      hJualController.text = hj.toString();
                                    } else {
                                      hJualController.text = '';
                                    }
                                    setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                          TextField(
                            controller: hJualController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Harga Jual (otomatis/manual)'),
                            onChanged: (val) {
                              final hJual = int.tryParse(val) ?? 0;
                              final hBeli = int.tryParse(hBeliController.text) ?? 0;
                              if (hBeli > 0 && hJual > 0) {
                                final profit = hitungProfitPersen(hBeli, hJual);
                                persenProfitController.text = profit.toStringAsFixed(2);
                              }
                            },
                          ),
                          TextField(
                            controller: stokController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Stok (boleh 0)'),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ElevatedButton(
                                onPressed: isSaving ? null : simpanBarang,
                                child: Text(isSaving
                                    ? (editMode
                                        ? 'Menyimpan...'
                                        : 'Menyimpan...')
                                    : (editMode
                                        ? 'Simpan Perubahan'
                                        : 'Tambah Barang')),
                              ),
                              const SizedBox(width: 10),
                              if (editMode)
                                OutlinedButton(
                                  onPressed: resetForm,
                                  child: const Text('Batal'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Search bar
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Cari barang...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      setState(() {
                        search = val;
                        currentPage = 1;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  // List barang
                  Expanded(
                    child: paginatedList.isEmpty
                        ? const Center(child: Text('Tidak ada data'))
                        : ListView.builder(
                            itemCount: paginatedList.length,
                            itemBuilder: (ctx, idx) {
                              final item = paginatedList[idx];
                              final hBeli = int.tryParse(item['h_beli'].toString()) ?? 0;
                              final hJual = int.tryParse(item['h_jual'].toString()) ?? 0;
                              final profit = hitungProfitPersen(hBeli, hJual);
                              return Card(
  margin: const EdgeInsets.only(bottom: 8),
  child: Padding(
    padding: const EdgeInsets.all(10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item['nama_brng'], style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Kode: ${item['kode_brng']}'),
              Text('Stok: ${item['stok']} | Profit: ${profit.isFinite ? profit.toStringAsFixed(2) : '-'}%'),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Beli: Rp${item['h_beli']}'),
            Text('Jual: Rp${item['h_jual']}'),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: Size(50, 30),
                padding: EdgeInsets.zero,
              ),
              child: const Text('Edit', style: TextStyle(fontSize: 12)),
              onPressed: () => startEdit(item),
            ),
          ],
        ),
      ],
    ),
  ),
);
                            },
                          ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: currentPage > 1
                            ? () => setState(() => currentPage--)
                            : null,
                        child: const Text('Sebelumnya'),
                      ),
                      Text('Halaman $currentPage'),
                      ElevatedButton(
                        onPressed: (currentPage * itemsPerPage < filteredList.length)
                            ? () => setState(() => currentPage++)
                            : null,
                        child: const Text('Selanjutnya'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
