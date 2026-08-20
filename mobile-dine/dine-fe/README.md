# dine-fe — DineSync POS Mobile (Flutter)

Aplikasi mobile **DineSync POS**. Ringan, responsif, dan **hanya memanggil REST API**
dari [dine-be](https://github.com/rendyirawann/dine-be) — tidak ada akses database langsung.

Tema, modul, dan menunya disamakan dengan aplikasi web POS (Metronic 8.2),
tetapi tata letaknya dirancang untuk layar HP.

- **Stack:** Flutter (SDK ^3.12) · Riverpod · Dio · go_router · flutter_secure_storage
- **Pendukung:** fl_chart (grafik) · qr_flutter (QR meja) · cached_network_image · intl (locale id-ID)

---

## 1. Menjalankan

```bash
flutter pub get

# Android / iOS / desktop
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001     # emulator Android
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8001 # HP fisik (IP LAN)

# Debug di browser
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 8085 \
  --dart-define=API_BASE_URL=http://127.0.0.1:8001
```

`API_BASE_URL` wajib menunjuk ke host tempat **dine-be** berjalan
(default bila tidak diisi: `http://127.0.0.1:8001`).

### Windows — satu klik

Jalankan **`debug-web.bat`** untuk debug web di **Brave** pada `http://127.0.0.1:8085`
(hot reload aktif). Bisa diberi argumen:

```bat
debug-web.bat 9000 http://192.168.1.10:8001
```

---

## 2. Struktur

```
lib/
  core/          tema (token Metronic), router, api client (Dio),
                 penyimpanan token, format Rupiah/tanggal
  features/
    auth/        login, sesi, permission
    dashboard/   ringkasan omzet/HPP/laba + grafik
    kasir/       peta meja, pilih menu, keranjang, pembayaran
    kitchen/     antrian dapur, ubah status item
    queue/       antrian pelanggan
    shift/       buka & tutup shift
    master/      kategori, menu, meja, promo, bahan, supplier
    finance/     pengeluaran, target & budget, stok, opname
    report/      laporan penjualan & menu terlaris
    profile/     profil, ganti password
    settings/    pengaturan toko & pajak
```

---

## 3. Tema

Warna, radius, dan tipografi mengikuti token web (Metronic 8.2) agar konsisten:
primary `#1B84FF`, success `#17C653`, danger `#F8285A`, warning `#F6C000`;
kartu radius 24, input/tombol 13.6; font **Inter**
(`fw-semibold`→w500, `fw-bold`→w600, `fw-bolder`→w700).
Mode terang & gelap tersedia mengikuti tema perangkat.

Mata uang diformat gaya Indonesia: `Rp 1.234.567` (tanpa desimal).

---

## 4. Catatan

- Menu yang tampil menyesuaikan **permission** user (mis. kasir tidak melihat Data Master).
- Realtime (Reverb) belum dilanggan dari sisi mobile — layar memakai refresh/pull-to-refresh.
- Upload gambar dari mobile belum diaktifkan.
- Layar Manajemen (user/role/tenant) belum dibuat di mobile; API-nya sudah tersedia.
