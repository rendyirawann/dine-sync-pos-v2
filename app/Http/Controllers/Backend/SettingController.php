<?php

namespace App\Http\Controllers\Backend;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\Setting;

class SettingController extends Controller
{
    // Menampilkan form pengaturan (karena cuma 1 baris, kita buat otomatis jika kosong)
    public function index()
    {
        // Per-tenant: ambil/buat baris setting milik tenant aktif.
        $setting = Setting::forCurrentTenant();

        return view('backend.settings.index', compact('setting'));
    }

    // Menyimpan perubahan pengaturan
    public function update(Request $request)
    {
        $request->validate([
            'store_name' => 'required|string|max:255',
            'tax_rate' => 'required|numeric|min:0|max:100',
        ]);

        $setting = Setting::forCurrentTenant();
        $setting->update($request->only(['store_name', 'address', 'phone', 'tax_rate']));

        return redirect()->back()->with('success', 'Pengaturan toko dan pajak berhasil diperbarui!');
    }
}
