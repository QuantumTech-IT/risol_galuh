// lib/pages/dashboard_page.dart
import 'dart:convert';
import 'dart:math' show max, pow;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // --- State umum
  bool isLoading = true;
  bool _isAdmin = false;
  int _currentIndex = 0; // 0: Dashboard, 1: Omset Harian

  // --- Filter bulan
  String bulan = _getCurrentMonth();
  static String _getCurrentMonth() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}";
  }
  List<String> _generateBulanOptions() {
    final now = DateTime.now();
    return List.generate(12, (i) {
      final m = (i + 1).toString().padLeft(2, '0');
      return "${now.year}-$m";
    });
  }

  // --- Data utama
  double totalOmset = 0;
  double totalUntung = 0;
  List<String> labels = [];
  List<double> dataset = [];        // omset / total
  List<double> datasetUntung = [];  // untung
  List<Map<String, dynamic>> topObat = [];
  List<Map<String, dynamic>> stokTipis = [];
  List<Map<String, dynamic>> penjualan7Hari = [];

  // --- Omset harian tab
  DateTime _selectedDate = DateTime.now();

  // --- Chart preferences
  bool _useBarChart = true; // true: Bar, false: Line
  bool _showProfit = false; // false: Omset, true: Untung

  // --- Formatter
  final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);
  String fr(num n) => _rupiah.format(n);
  final _moneyCompact =
      NumberFormat.compactCurrency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

  // --- Helpers
  List<double> _currentSeries() => _showProfit ? datasetUntung : dataset;
  String _seriesName() => _showProfit ? 'Keuntungan' : 'Omset';
  Color _seriesColor() => _showProfit ? Colors.green : Colors.deepPurple;

  String _dayFrom(String tgl) {
    try {
      final d = DateTime.parse(tgl);
      return d.day.toString().padLeft(2, '0');
    } catch (_) {
      return tgl.length >= 10 ? tgl.substring(8, 10) : tgl;
    }
  }

  double _niceCeil(double v) {
    if (v <= 0) return 1000;
    final p = pow(10, v.toStringAsFixed(0).length - 1);
    final ceil = (v / p).ceil() * p;
    return ceil.toDouble();
  }

  // --- Lifecycle
  @override
  void initState() {
    super.initState();
    _loadRole();
    fetchDashboardData();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('role') ?? '').toLowerCase();
    setState(() => _isAdmin = role == 'admin');
  }

  // --- Networking
  Future<void> fetchDashboardData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final url = Uri.parse(
          'https://bpjsapi.quantumtechapp.com/risol-api/get_dashboard_data.php?bulan=$bulan');
      final res = await http.get(url);

      if (res.statusCode != 200) {
        debugPrint('Dashboard HTTP ${res.statusCode}: ${res.body}');
        if (!mounted) return;
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat dashboard (${res.statusCode})')),
        );
        return;
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final penjualan = (json['penjualan_7_hari'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final top = (json['top_obat'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final tipis = (json['stok_tipis'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      final newLabels = <String>[];
      final newDataset = <double>[];
      final newUntung = <double>[];

      for (final m in penjualan) {
        newLabels.add(_dayFrom('${m['tanggal']}'));
        final total = double.tryParse('${m['total']}') ?? 0;
        newDataset.add(total);

        if (m.containsKey('untung') && m['untung'] != null) {
          newUntung.add(double.tryParse('${m['untung']}') ?? 0);
        } else if (m.containsKey('total_h_beli')) {
          final modal = double.tryParse('${m['total_h_beli']}') ?? 0;
          newUntung.add(total - modal);
        } else {
          newUntung.add(0);
        }
      }

      if (!mounted) return;
      setState(() {
        labels = newLabels;
        dataset = newDataset;
        datasetUntung = newUntung;
        totalOmset = newDataset.fold(0, (a, b) => a + b);
        totalUntung = newUntung.fold(0, (a, b) => a + b);
        topObat = top;
        stokTipis = tipis;
        penjualan7Hari = penjualan;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Gagal ambil data: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat data: $e')),
      );
    }
  }

  // --- (Opsional) Bottom-sheet Riwayat, hanya admin
  static const String _riwayatEndpoint =
      'https://bpjsapi.quantumtechapp.com/risol-api/get_penjualan.php?limit=50';
  static const String _hapusEndpoint =
      'https://bpjsapi.quantumtechapp.com/risol-api/tambah_penjualan.php';

  List<Map<String, dynamic>> _cachedRiwayat = [];
  Future<List<Map<String, dynamic>>> _fetchRiwayat({int limit = 50}) async {
    final uri = Uri.parse('$_riwayatEndpoint?limit=$limit');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body);
    final list = (data is List)
        ? data
        : (data['data'] ?? data['riwayat'] ?? data) as List;
    return List<Map<String, dynamic>>.from(list.map((e) => {
          'nota': e['nota'] ?? e['nota_jual'],
          'tanggal': e['tanggal'] ?? e['tgl_jual'],
          'total': double.tryParse('${e['total'] ?? 0}') ?? 0,
        }));
  }

  Future<void> _hapusNota(
      String nota, void Function(void Function()) setSheetState) async {
    try {
      final req = http.Request('DELETE', Uri.parse(_hapusEndpoint))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'nota': nota});
      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200) {
        throw Exception('HTTP ${streamed.statusCode}: $body');
      }
      final json = jsonDecode(body);
      if (json['success'] != true) {
        throw Exception(json['message'] ?? 'Gagal menghapus');
      }

      final data = await _fetchRiwayat();
      setSheetState(() {
        _cachedRiwayat = data;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nota $nota dihapus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal hapus: $e')),
      );
    }
  }

  void _openRiwayatSheet() {
    if (!_isAdmin) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future:
                _cachedRiwayat.isEmpty ? _fetchRiwayat() : Future.value(_cachedRiwayat),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Riwayat Penjualan',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text('Gagal memuat: ${snap.error}'),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            setSheetState(() {
                              _cachedRiwayat = [];
                            });
                          },
                          child: const Text('Coba lagi'),
                        ),
                      )
                    ],
                  ),
                );
              }

              _cachedRiwayat = snap.data ?? [];

              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Riwayat Penjualan',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _cachedRiwayat.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final x = _cachedRiwayat[i];
                            return ListTile(
                              title: Text('Nota: ${x['nota']}'),
                              subtitle: Text(
                                  'Tanggal: ${x['tanggal']}\nTotal: ${fr(x['total'])}'),
                              trailing: _isAdmin
                                  ? IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _hapusNota(x['nota'], setSheetState),
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        });
      },
    );
  }

  // --- Logout helper
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
  }

  // --- UI builders
  Widget _buildDashboardView() {
    final bulanOptions = _generateBulanOptions();
    final series = _currentSeries();

    return ListView(
      children: [
        // Filter Bulan
        DropdownButton<String>(
          value: bulan,
          onChanged: (value) {
            if (value != null) {
              setState(() => bulan = value);
              fetchDashboardData();
            }
          },
          items: bulanOptions
              .map((b) => DropdownMenuItem(value: b, child: Text(b)))
              .toList(),
        ),

        const SizedBox(height: 12),

        // Ringkasan
        Text('Total Omset: ${fr(totalOmset)}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
        const SizedBox(height: 6),
        Text('Potensi Keuntungan: ${fr(totalUntung)}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),

        const SizedBox(height: 16),

        // Kontrol Chart
        Row(
          children: [
            ToggleButtons(
              isSelected: [_useBarChart, !_useBarChart],
              onPressed: (i) => setState(() => _useBarChart = (i == 0)),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.bar_chart),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.show_chart),
                ),
              ],
            ),
            const SizedBox(width: 8),
            ToggleButtons(
              isSelected: [!_showProfit, _showProfit],
              onPressed: (i) => setState(() => _showProfit = (i == 1)),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('Omset'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text('Untung'),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Text(_seriesName(),
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: _seriesColor())),
          ],
        ),
        const SizedBox(height: 10),

        // Chart
        SizedBox(
          height: 260,
          child: Card(
            elevation: 2,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Builder(
                builder: (context) {
                  if (series.isEmpty) {
                    return const Center(child: Text('Tidak ada data'));
                  }
                  final yMax = _niceCeil(series.reduce(max));

                  return _useBarChart
                      ? BarChart(
                          BarChartData(
                            maxY: yMax,
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipItem: (group, _, rod, __) {
                                  final idx = group.x.toInt();
                                  final day =
                                      (idx >= 0 && idx < labels.length) ? labels[idx] : '';
                                  return BarTooltipItem(
                                    'Tgl $day\n${_seriesName()}: ${_moneyCompact.format(rod.toY)}',
                                    const TextStyle(fontWeight: FontWeight.w600),
                                  );
                                },
                              ),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 56,
                                  getTitlesWidget: (v, _) =>
                                      Text(_moneyCompact.format(v)),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        (i >= 0 && i < labels.length) ? labels[i] : '',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              topTitles:
                                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles:
                                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (v) => const FlLine(strokeWidth: 0.4),
                            ),
                            borderData: FlBorderData(show: false),
                            barGroups: List.generate(series.length, (i) {
                              return BarChartGroupData(
                                x: i,
                                barsSpace: 2,
                                barRods: [
                                  BarChartRodData(
                                    toY: series[i],
                                    gradient: LinearGradient(
                                      colors: [
                                        _seriesColor().withOpacity(0.95),
                                        _seriesColor().withOpacity(0.55),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    width: 10,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ],
                              );
                            }),
                          ),
                        )
                      : LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: yMax,
                            lineTouchData: LineTouchData(
                              enabled: true,
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (spots) => spots.map((s) {
                                  final i = s.x.toInt();
                                  final day =
                                      (i >= 0 && i < labels.length) ? labels[i] : '';
                                  return LineTooltipItem(
                                    'Tgl $day\n${_seriesName()}: ${_moneyCompact.format(s.y)}',
                                    const TextStyle(fontWeight: FontWeight.w600),
                                  );
                                }).toList(),
                              ),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 56,
                                  getTitlesWidget: (v, _) =>
                                      Text(_moneyCompact.format(v)),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, _) {
                                    final i = v.toInt();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        (i >= 0 && i < labels.length) ? labels[i] : '',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              topTitles:
                                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles:
                                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (v) => const FlLine(strokeWidth: 0.4),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                isCurved: true,
                                barWidth: 3,
                                color: _seriesColor(),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    colors: [
                                      _seriesColor().withOpacity(0.30),
                                      _seriesColor().withOpacity(0.05),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                                dotData: FlDotData(show: true),
                                spots: List.generate(
                                  series.length,
                                  (i) => FlSpot(i.toDouble(), series[i]),
                                ),
                              ),
                            ],
                          ),
                        );
                },
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Top risol
        const Text('Top 5 Risol Terlaris',
            style: TextStyle(fontWeight: FontWeight.bold)),
        ...topObat.asMap().entries.map((e) {
          final i = e.key;
          final m = e.value;
          return Text('${i + 1}. ${m['nama_brng']} - ${m['jumlah']}x');
        }),

        const SizedBox(height: 16),

        // Stok tipis
        const Text('Stok Tipis (≤ 5)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        ...stokTipis.asMap().entries.map((e) {
          final i = e.key;
          final m = e.value;
          return Text('${i + 1}. ${m['nama_brng']} - ${m['stok']} item');
        }),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 16 * 2 - 12) / 2,
      child: Card(
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.1),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 4),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOmsetHarianView() {
    final tglKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    Map<String, dynamic>? rec;
    try {
      rec = penjualan7Hari.firstWhere(
        (e) => (e['tanggal'] ?? '').toString().startsWith(tglKey),
      );
    } catch (_) {
      rec = null;
    }

    final total = double.tryParse('${rec?['total'] ?? 0}') ?? 0;
    double untung;
    if (rec != null && rec.containsKey('untung') && rec['untung'] != null) {
      untung = double.tryParse('${rec['untung']}') ?? 0;
    } else if (rec != null && rec.containsKey('total_h_beli')) {
      final modal = double.tryParse('${rec['total_h_beli']}') ?? 0;
      untung = total - modal;
    } else {
      untung = 0;
    }
    final qris = double.tryParse('${rec?['qris'] ?? 0}') ?? 0;
    final cash = double.tryParse('${rec?['cash'] ?? 0}') ?? 0;
    final gofood = double.tryParse('${rec?['gofood'] ?? 0}') ?? 0;

    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.today),
                label: Text(
                  DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(_selectedDate),
                ),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(DateTime.now().year, 1, 1),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    locale: const Locale('id', 'ID'),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: fetchDashboardData,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _statCard('Total Omset', fr(total), Icons.bar_chart, Colors.blue),
            _statCard('Perkiraan Untung', fr(untung), Icons.trending_up, Colors.green),
            _statCard('QRIS', fr(qris), Icons.qr_code, Colors.deepPurple),
            _statCard('Cash', fr(cash), Icons.payments, Colors.orange),
           _statCard('Go Food',fr(gofood), Icons.delivery_dining, const Color.fromARGB(255, 4, 240, 149)),
          ],
        ),
        const SizedBox(height: 12),
        if (rec == null)
          const Text('Belum ada data untuk tanggal ini atau di luar jangkauan 7 hari.',
              style: TextStyle(color: Colors.grey))
        else if ((qris + cash + gofood == 0) && total > 0)
          const Text('Catatan: rincian QRIS/Cash/Go Food belum tersedia dari API untuk tanggal ini.',
              style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  // --- Build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_currentIndex == 0 ? 'Dashboard Penjualan' : 'Omset Harian'),
        automaticallyImplyLeading: true, // biarkan sesuai navigator
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Riwayat Penjualan',
              onPressed: _openRiwayatSheet,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: fetchDashboardData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child:
                  _currentIndex == 0 ? _buildDashboardView() : _buildOmsetHarianView(),
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.insights),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.attach_money),
            label: 'Omset Harian',
          ),
        ],
      ),
    );
    }
}
