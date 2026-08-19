<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\SettingResource;
use App\Models\Setting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use OpenApi\Attributes as OA;

/**
 * Pengaturan toko & pajak milik tenant aktif.
 * Semua role boleh MELIHAT (nama toko dipakai di struk / header aplikasi),
 * tetapi hanya pemilik hak `view_data_master` (atau Superadmin) yang boleh MENGUBAH.
 */
class SettingController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/settings',
        operationId: 'settingShow',
        summary: 'Lihat pengaturan toko & pajak',
        description: 'Mengambil pengaturan toko milik tenant aktif (nama toko, alamat, telepon, persentase pajak). Bila tenant belum punya baris pengaturan, baris default otomatis dibuat. Endpoint ini boleh diakses semua role karena datanya dipakai untuk struk dan tampilan aplikasi.',
        tags: ['Setting'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Pengaturan toko', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Berhasil.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'id', type: 'integer', example: 1),
                        new OA\Property(property: 'store_name', type: 'string', example: 'Warung Nusantara'),
                        new OA\Property(property: 'address', type: 'string', example: 'Jl. Merdeka No. 10, Jakarta', nullable: true),
                        new OA\Property(property: 'phone', type: 'string', example: '0217654321', nullable: true),
                        new OA\Property(property: 'tax_rate', type: 'integer', example: 10),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function show(): JsonResponse
    {
        return $this->ok(new SettingResource(Setting::forCurrentTenant()));
    }

    #[OA\Put(
        path: '/api/v1/settings',
        operationId: 'settingUpdate',
        summary: 'Ubah pengaturan toko & pajak',
        description: 'Memperbarui nama toko, alamat, telepon, dan persentase pajak milik tenant aktif. Hanya user dengan hak akses `view_data_master` (atau role Superadmin) yang diizinkan; selain itu balasan `403`. Nilai `tax_rate` adalah persen (0 - 100) dan dipakai untuk menghitung pajak pada transaksi kasir.',
        tags: ['Setting'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['store_name', 'tax_rate'],
                properties: [
                    new OA\Property(property: 'store_name', type: 'string', maxLength: 255, example: 'Warung Nusantara'),
                    new OA\Property(property: 'address', type: 'string', example: 'Jl. Merdeka No. 10, Jakarta', nullable: true),
                    new OA\Property(property: 'phone', type: 'string', maxLength: 30, example: '0217654321', nullable: true),
                    new OA\Property(property: 'tax_rate', type: 'number', format: 'float', maximum: 100, minimum: 0, example: 10),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Pengaturan diperbarui', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Pengaturan toko dan pajak berhasil diperbarui!'),
                    new OA\Property(property: 'data', type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 403, description: 'Tidak punya hak mengubah pengaturan toko'),
            new OA\Response(response: 422, description: 'Data tidak valid'),
        ]
    )]
    public function update(Request $request): JsonResponse
    {
        // Superadmin otomatis lolos lewat Gate::before, jadi cukup periksa satu ability.
        if (! $request->user()->can('view_data_master')) {
            return $this->fail('Anda tidak punya hak mengubah pengaturan toko.', 403);
        }

        $data = $request->validate([
            'store_name' => ['required', 'string', 'max:255'],
            'address' => ['nullable', 'string'],
            'phone' => ['nullable', 'string', 'max:30'],
            'tax_rate' => ['required', 'numeric', 'min:0', 'max:100'],
        ], [
            'store_name.required' => 'Nama toko wajib diisi.',
            'store_name.max' => 'Nama toko maksimal 255 karakter.',
            'phone.max' => 'Nomor telepon maksimal 30 karakter.',
            'tax_rate.required' => 'Persentase pajak wajib diisi.',
            'tax_rate.numeric' => 'Persentase pajak harus berupa angka.',
            'tax_rate.min' => 'Persentase pajak minimal 0.',
            'tax_rate.max' => 'Persentase pajak maksimal 100.',
        ]);

        $setting = Setting::forCurrentTenant();

        $setting->update([
            'store_name' => $data['store_name'],
            'address' => $data['address'] ?? null,
            'phone' => $data['phone'] ?? null,
            'tax_rate' => $data['tax_rate'],
        ]);

        return $this->ok(
            new SettingResource($setting->fresh()),
            'Pengaturan toko dan pajak berhasil diperbarui!'
        );
    }
}
