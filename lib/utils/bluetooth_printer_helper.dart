import 'package:blue_thermal_printer/blue_thermal_printer.dart';
//import 'package:permission_handler/permission_handler.dart';

class BluetoothPrinterHelper {
  static final BlueThermalPrinter printer = BlueThermalPrinter.instance;

  // /// Fungsi untuk konek ke printer bluetooth pertama yang ditemukan
  // static Future<void> connectToPrinter() async {
  //   // Minta semua permission penting
  //   final bluetoothConnect = await Permission.bluetoothConnect.request();
  //   final bluetoothScan = await Permission.bluetoothScan.request();
  //   final location = await Permission.location.request();

  //   if (bluetoothConnect.isGranted && bluetoothScan.isGranted && location.isGranted) {
  //     List<BluetoothDevice> devices = await printer.getBondedDevices();

  //     if (devices.isEmpty) {
  //       throw Exception("❌ Tidak ada printer Bluetooth yang dipasangkan.");
  //     }

  //     await printer.connect(devices.first);
  //   } else {
  //     throw Exception("❌ Izin Bluetooth atau Lokasi ditolak.");
  //   }
  // }

  /// Fungsi untuk mencetak teks (opsional, bisa sesuaikan dengan kebutuhanmu)
  static Future<void> printText(String text) async {
    try {
      if (await printer.isConnected ?? false) {
        printer.printNewLine();
        printer.printCustom(text, 1, 0);
        printer.printNewLine();
        printer.paperCut();
      } else {
        throw Exception("Printer belum terkoneksi.");
      }
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> cetakStruk({
  required String nota,
  required String tanggal,
  required List<Map<String, dynamic>> keranjang,
}) async {
  try {
    List<BluetoothDevice> devices = await printer.getBondedDevices();
    if (devices.isEmpty) throw Exception("❌ Tidak ada printer Bluetooth yang dipasangkan.");

    await printer.connect(devices.first);

    await Future.delayed(const Duration(seconds: 1)); // tunggu koneksi stabil

    double grandTotal = keranjang.fold<double>(
      0,
      (sum, item) => sum + (item['harga_total'] ?? 0),
    );

    printer.printNewLine();
    printer.printCustom("Risol Galuh Shop", 3, 1); // bold, center
    printer.printNewLine();
    printer.printCustom("Nota: $nota", 1, 0);
    printer.printCustom("Tanggal: $tanggal", 1, 0);
    printer.printCustom("--------------------------------", 1, 0);

    for (var item in keranjang) {
      final nama = item['nama_brng'];
      final jumlah = item['jumlah'];
      final satuan = item['satuan'];
      final isi = item['isi'] ?? 1;
      final jumlahPcs = item['jumlah_pcs'];
      final harga = item['h_jual'];
      final total = item['harga_total'];

      if (satuan == 'BOX') {
        printer.printCustom(nama, 1, 0);
        printer.printCustom(
            "$jumlah box x $isi pcs = $jumlahPcs pcs", 1, 0);
        printer.printCustom("x Rp$harga = Rp${total.toStringAsFixed(0)}", 1, 0);
      } else {
        printer.printCustom("$nama", 1, 0);
        printer.printCustom("$jumlah pcs x Rp$harga = Rp${total.toStringAsFixed(0)}", 1, 0);
      }

      printer.printCustom("--------------------------------", 1, 0);
    }

    printer.printCustom("Total: Rp${grandTotal.toStringAsFixed(0)}", 2, 1); // Bold Center
    printer.printNewLine();
    printer.printCustom("Terima kasih 🙏", 1, 1);
    printer.printNewLine();
    printer.paperCut();
  } catch (e) {
    rethrow;
  }
}


  // static Future<void> printText(String text) async {
  //   try {
  //     if (await printer.isConnected ?? false) {
  //       printer.printNewLine();
  //       printer.printCustom(text, 1, 0);
  //       printer.printNewLine();
  //       printer.paperCut();
  //     } else {
  //       throw Exception("Printer belum terkoneksi.");
  //     }
  //   } catch (e) {
  //     rethrow;
  //   }
  // }

}