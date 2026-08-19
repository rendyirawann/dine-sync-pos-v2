<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\UserResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use OpenApi\Attributes as OA;
use Spatie\Activitylog\Models\Activity;

/**
 * Profil user yang sedang login: lihat, ubah data, ganti avatar, riwayat aktivitas.
 * Avatar disimpan di folder per-tenant (tenants/{tenantId}/user/avatar) sama seperti web.
 */
class ProfileController extends BaseApiController
{
    #[OA\Get(
        path: '/api/v1/profile',
        operationId: 'profileShow',
        summary: 'Lihat profil saya',
        description: 'Mengembalikan profil user yang sedang login lengkap dengan role, daftar permission, dan tenant (UMKM) — dipakai Flutter untuk menyusun menu sesuai hak akses.',
        tags: ['Profil'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Data profil', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Berhasil.'),
                    new OA\Property(property: 'data', type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function show(Request $request): JsonResponse
    {
        return $this->ok(UserResource::withAccess($request->user()));
    }

    #[OA\Put(
        path: '/api/v1/profile',
        operationId: 'profileUpdate',
        summary: 'Ubah profil saya',
        description: 'Memperbarui nama, nomor WhatsApp, email, dan nomor telepon user yang sedang login. Email wajib unik (kecuali email milik sendiri).',
        tags: ['Profil'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['name', 'email'],
                properties: [
                    new OA\Property(property: 'name', type: 'string', maxLength: 255, example: 'Rendy Irawan'),
                    new OA\Property(property: 'no_wa', type: 'string', maxLength: 20, example: '08123456789', nullable: true),
                    new OA\Property(property: 'email', type: 'string', format: 'email', maxLength: 255, example: 'owner1@trial.test'),
                    new OA\Property(property: 'phone', type: 'string', maxLength: 15, example: '0217654321', nullable: true),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Profil diperbarui', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Profil berhasil diperbarui.'),
                    new OA\Property(property: 'data', type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 422, description: 'Data tidak valid / email sudah dipakai'),
        ]
    )]
    public function update(Request $request): JsonResponse
    {
        $user = $request->user();

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'no_wa' => ['nullable', 'string', 'max:20'],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')->ignore($user->id)],
            'phone' => ['nullable', 'string', 'max:15'],
        ], [
            'name.required' => 'Nama lengkap wajib diisi.',
            'name.max' => 'Nama lengkap maksimal 255 karakter.',
            'no_wa.max' => 'Nomor WhatsApp maksimal 20 karakter.',
            'email.required' => 'Email wajib diisi.',
            'email.email' => 'Format email tidak valid.',
            'email.max' => 'Email maksimal 255 karakter.',
            'email.unique' => 'Email sudah digunakan oleh pengguna lain.',
            'phone.max' => 'Nomor telepon maksimal 15 karakter.',
        ]);

        $payload = [
            'name' => $data['name'],
            'email' => $data['email'],
        ];

        // Kolom opsional hanya diubah bila memang dikirim (boleh dikosongkan dengan null).
        if ($request->has('no_wa')) {
            $payload['no_wa'] = $data['no_wa'] ?? null;
        }

        if ($request->has('phone')) {
            $payload['phone'] = $data['phone'] ?? null;
        }

        $user->update($payload);

        return $this->ok(UserResource::withAccess($user->fresh()), 'Profil berhasil diperbarui.');
    }

    #[OA\Post(
        path: '/api/v1/profile/avatar',
        operationId: 'profileUpdateAvatar',
        summary: 'Ganti foto profil (avatar)',
        description: 'Upload foto profil baru memakai `multipart/form-data`. Format yang diizinkan JPG/JPEG/PNG, maksimal 2 MB. Avatar lama otomatis dihapus. File disimpan di folder per-tenant `tenants/{tenantId}/user/avatar`.',
        tags: ['Profil'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\MediaType(
                mediaType: 'multipart/form-data',
                schema: new OA\Schema(
                    required: ['avatar'],
                    properties: [
                        new OA\Property(property: 'avatar', type: 'string', format: 'binary', description: 'Berkas gambar JPG/JPEG/PNG maksimal 2 MB.'),
                    ]
                )
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Avatar diperbarui', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Avatar berhasil diperbarui.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'avatar', type: 'string', example: 'avatar-9f1c-1763529600.jpg'),
                        new OA\Property(property: 'avatar_url', type: 'string', example: 'https://app.example.com/storage/tenants/1/user/avatar/avatar-9f1c-1763529600.jpg'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
            new OA\Response(response: 422, description: 'Berkas tidak valid / terlalu besar'),
        ]
    )]
    public function updateAvatar(Request $request): JsonResponse
    {
        $request->validate([
            'avatar' => ['required', 'image', 'mimes:jpg,jpeg,png', 'max:2048'],
        ], [
            'avatar.required' => 'Foto wajib diunggah.',
            'avatar.image' => 'Berkas harus berupa gambar.',
            'avatar.mimes' => 'Foto harus berformat JPG atau PNG.',
            'avatar.max' => 'Ukuran foto maksimal 2 MB.',
        ]);

        $user = $request->user();

        // Folder avatar per-tenant: tenants/{tenantId}/user/avatar
        $dir = app('tenant')->mediaDir('user/avatar');

        // Hapus avatar lama bila ada.
        if ($user->avatar && Storage::disk('public')->exists($dir . '/' . $user->avatar)) {
            Storage::disk('public')->delete($dir . '/' . $user->avatar);
        }

        $file = $request->file('avatar');
        $filename = 'avatar-' . $user->id . '-' . time() . '.' . $file->getClientOriginalExtension();

        Storage::disk('public')->putFileAs($dir, $file, $filename);

        $user->update(['avatar' => $filename]);

        return $this->ok([
            'avatar' => $filename,
            'avatar_url' => $user->fresh()->avatar_url,
        ], 'Avatar berhasil diperbarui.');
    }

    #[OA\Get(
        path: '/api/v1/profile/activities',
        operationId: 'profileActivities',
        summary: 'Riwayat aktivitas saya',
        description: 'Riwayat aktivitas (audit trail) yang dilakukan user yang sedang login, terbaru lebih dulu. Menyertakan IP, jenis perangkat, dan sistem operasi bila tercatat. Ukuran halaman diatur lewat query `per_page` (default 20, maksimal 100).',
        tags: ['Profil'],
        security: [['sanctum' => []]],
        parameters: [
            new OA\Parameter(name: 'per_page', in: 'query', required: false, description: 'Jumlah baris per halaman (default 20, maksimal 100).', schema: new OA\Schema(type: 'integer', default: 20, maximum: 100, minimum: 1)),
            new OA\Parameter(name: 'page', in: 'query', required: false, description: 'Halaman yang diminta.', schema: new OA\Schema(type: 'integer', default: 1, minimum: 1)),
        ],
        responses: [
            new OA\Response(response: 200, description: 'Riwayat aktivitas', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Riwayat aktivitas berhasil dimuat.'),
                    new OA\Property(property: 'data', type: 'array', items: new OA\Items(properties: [
                        new OA\Property(property: 'id', type: 'integer', example: 142),
                        new OA\Property(property: 'log_name', type: 'string', example: 'profile'),
                        new OA\Property(property: 'description', type: 'string', example: 'Mengubah Data Profile Akun'),
                        new OA\Property(property: 'ip', type: 'string', example: '192.168.1.10', nullable: true),
                        new OA\Property(property: 'device', type: 'string', example: 'Redmi Note 12', nullable: true),
                        new OA\Property(property: 'os', type: 'string', example: 'AndroidOS', nullable: true),
                        new OA\Property(property: 'created_at', type: 'string', format: 'date-time'),
                    ], type: 'object')),
                    new OA\Property(property: 'meta', type: 'object'),
                ]
            )),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function activities(Request $request): JsonResponse
    {
        $activities = Activity::where('causer_id', $request->user()->id)
            ->latest()
            ->paginate($this->perPage());

        $activities->through(function ($activity) {
            $properties = $activity->properties;
            $properties = $properties instanceof \Illuminate\Support\Collection
                ? $properties->toArray()
                : (array) ($properties ?? []);

            $agent = is_array($properties['agent'] ?? null) ? $properties['agent'] : [];

            return [
                'id' => $activity->id,
                'log_name' => $activity->log_name,
                'description' => $activity->description,
                'ip' => $properties['ip'] ?? null,
                'device' => $agent['device'] ?? null,
                'os' => $agent['os'] ?? null,
                'created_at' => optional($activity->created_at)->toIso8601String(),
            ];
        });

        return $this->paginated($activities, 'Riwayat aktivitas berhasil dimuat.');
    }
}
