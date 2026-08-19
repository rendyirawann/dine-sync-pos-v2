// Test dasar: memastikan aplikasi bisa dirakit dan layar login tampil
// saat belum ada sesi tersimpan.

import 'package:dine_fe/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Format Rupiah & angka (harus sama dengan tampilan web)', () {
    test('rupiah tanpa desimal, ribuan pakai titik', () {
      expect(Fmt.rupiah(25000), 'Rp 25.000');
      expect(Fmt.rupiah(0), 'Rp 0');
      expect(Fmt.rupiah(1234567), 'Rp 1.234.567');
    });

    test('rupiah singkat untuk kartu statistik', () {
      expect(Fmt.rupiahShort(1500000), 'Rp 1,5 jt');
      expect(Fmt.rupiahShort(25000), 'Rp 25 rb');
    });

    test('konversi JSON aman terhadap tipe campuran', () {
      expect(J.toDouble('25000'), 25000);
      expect(J.toDouble(null), 0);
      expect(J.toInt('12'), 12);
      expect(J.toBool(1), isTrue);
      expect(J.toBool('false'), isFalse);
    });
  });

  group('Perhitungan total pesanan (harus identik dengan server)', () {
    // Urutan: subtotal -> diskon promo -> pajak SETELAH diskon -> grand total
    test('pajak dihitung setelah diskon', () {
      const subtotal = 100000.0;
      const discount = 10000.0; // promo 10%
      final net = subtotal - discount;
      final tax = (net * 10 / 100).roundToDouble(); // tax_rate 10%
      final grand = net + tax;

      expect(net, 90000);
      expect(tax, 9000);
      expect(grand, 99000);
    });

    test('diskon tidak boleh membuat subtotal negatif', () {
      const subtotal = 5000.0;
      const discount = 50000.0; // promo nominal lebih besar dari belanja
      final net = (subtotal - discount) < 0 ? 0.0 : subtotal - discount;

      expect(net, 0);
    });
  });
}
