<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Api\BaseApiController;
use App\Http\Resources\UserResource;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;
use Jenssegers\Agent\Agent;
use OpenApi\Attributes as OA;

class AuthController extends BaseApiController
{
    #[OA\Post(
        path: '/api/v1/auth/login',
        operationId: 'authLogin',
        summary: 'Login & dapatkan token',
        description: 'Login memakai email, username, no WhatsApp, atau nama (sama seperti web). Balasan berisi token Sanctum + data user, role, dan daftar permission untuk mengatur menu di aplikasi.',
        tags: ['Auth'],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['login', 'password'],
                properties: [
                    new OA\Property(property: 'login', type: 'string', example: 'owner1@trial.test', description: 'Email / username / no WA / nama'),
                    new OA\Property(property: 'password', type: 'string', format: 'password', example: 'password'),
                    new OA\Property(property: 'device_name', type: 'string', example: 'Android - Redmi Note 12', description: 'Nama device untuk penamaan token'),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Login berhasil', content: new OA\JsonContent(
                properties: [
                    new OA\Property(property: 'success', type: 'boolean', example: true),
                    new OA\Property(property: 'message', type: 'string', example: 'Login berhasil.'),
                    new OA\Property(property: 'data', properties: [
                        new OA\Property(property: 'token', type: 'string', example: '3|abcdef123456...'),
                        new OA\Property(property: 'user', type: 'object'),
                    ], type: 'object'),
                ]
            )),
            new OA\Response(response: 422, description: 'Kredensial salah / tidak valid'),
            new OA\Response(response: 403, description: 'Akun dibekukan atau tidak aktif'),
        ]
    )]
    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'login' => ['required', 'string'],
            'password' => ['required', 'string'],
            'device_name' => ['nullable', 'string', 'max:120'],
        ], [
            'login.required' => 'Email / username wajib diisi.',
            'password.required' => 'Password wajib diisi.',
        ]);

        $value = trim($data['login']);

        // Deteksi tipe input mengikuti perilaku login web: email / no_wa / username / nama.
        $user = User::query()
            ->where(function ($q) use ($value) {
                $q->where('email', $value)
                    ->orWhere('username', $value)
                    ->orWhere('no_wa', $value)
                    ->orWhere('name', $value);
            })
            ->first();

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages([
                'login' => ['Akun atau password salah.'],
            ]);
        }

        if ($user->banned_at) {
            return $this->fail('Akun Anda telah dibekukan. Silakan hubungi admin.', 403);
        }

        if (! $user->is_active) {
            return $this->fail('Akun Anda tidak aktif. Silakan hubungi admin.', 403);
        }

        // Catat jejak login (sama seperti web).
        $user->update([
            'last_ip' => $request->ip(),
            'last_login' => now(),
        ]);

        $deviceName = $data['device_name'] ?? $this->guessDeviceName($request);
        $token = $user->createToken($deviceName)->plainTextToken;

        $this->logActivity($request, $user, 'login', 'Login mobile berhasil');

        return $this->ok([
            'token' => $token,
            'token_type' => 'Bearer',
            'user' => UserResource::withAccess($user),
        ], 'Login berhasil.');
    }

    #[OA\Get(
        path: '/api/v1/auth/me',
        operationId: 'authMe',
        summary: 'Data user yang sedang login',
        description: 'Mengembalikan profil, role, permission, dan tenant (UMKM) user aktif.',
        tags: ['Auth'],
        security: [['sanctum' => []]],
        responses: [
            new OA\Response(response: 200, description: 'Data user'),
            new OA\Response(response: 401, description: 'Belum terautentikasi'),
        ]
    )]
    public function me(Request $request): JsonResponse
    {
        return $this->ok(UserResource::withAccess($request->user()));
    }

    #[OA\Post(
        path: '/api/v1/auth/logout',
        operationId: 'authLogout',
        summary: 'Logout device ini',
        description: 'Menghapus token yang sedang dipakai (device ini saja).',
        tags: ['Auth'],
        security: [['sanctum' => []]],
        responses: [new OA\Response(response: 200, description: 'Logout berhasil')]
    )]
    public function logout(Request $request): JsonResponse
    {
        $this->logActivity($request, $request->user(), 'logout', 'Logout mobile');

        $request->user()->currentAccessToken()->delete();

        return $this->ok(null, 'Logout berhasil.');
    }

    #[OA\Post(
        path: '/api/v1/auth/logout-all',
        operationId: 'authLogoutAll',
        summary: 'Logout semua device',
        description: 'Menghapus SEMUA token milik user (keluar dari semua perangkat).',
        tags: ['Auth'],
        security: [['sanctum' => []]],
        responses: [new OA\Response(response: 200, description: 'Semua sesi diakhiri')]
    )]
    public function logoutAll(Request $request): JsonResponse
    {
        $request->user()->tokens()->delete();

        return $this->ok(null, 'Semua sesi perangkat telah diakhiri.');
    }

    #[OA\Post(
        path: '/api/v1/auth/change-password',
        operationId: 'authChangePassword',
        summary: 'Ganti password',
        tags: ['Auth'],
        security: [['sanctum' => []]],
        requestBody: new OA\RequestBody(
            required: true,
            content: new OA\JsonContent(
                required: ['current_password', 'password', 'password_confirmation'],
                properties: [
                    new OA\Property(property: 'current_password', type: 'string', format: 'password'),
                    new OA\Property(property: 'password', type: 'string', format: 'password', minLength: 8),
                    new OA\Property(property: 'password_confirmation', type: 'string', format: 'password'),
                    new OA\Property(property: 'logout_other_devices', type: 'boolean', example: true),
                ]
            )
        ),
        responses: [
            new OA\Response(response: 200, description: 'Password diperbarui'),
            new OA\Response(response: 422, description: 'Password lama salah / konfirmasi tidak cocok'),
        ]
    )]
    public function changePassword(Request $request): JsonResponse
    {
        $data = $request->validate([
            'current_password' => ['required', 'string'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
            'logout_other_devices' => ['nullable', 'boolean'],
        ], [
            'password.confirmed' => 'Konfirmasi password tidak sama.',
            'password.min' => 'Password baru minimal 8 karakter.',
        ]);

        $user = $request->user();

        if (! Hash::check($data['current_password'], $user->password)) {
            throw ValidationException::withMessages([
                'current_password' => ['Password saat ini salah.'],
            ]);
        }

        $user->update(['password' => $data['password']]); // auto-hash lewat cast 'hashed'

        if ($request->boolean('logout_other_devices')) {
            $currentId = $request->user()->currentAccessToken()->id;
            $user->tokens()->where('id', '!=', $currentId)->delete();
        }

        $this->logActivity($request, $user, 'profile', 'Mengganti password via mobile');

        return $this->ok(null, 'Password berhasil diperbarui.');
    }

    /** Nama device fallback dari User-Agent. */
    private function guessDeviceName(Request $request): string
    {
        $agent = new Agent;
        $agent->setUserAgent((string) $request->header('User-Agent'));

        $platform = $agent->platform() ?: 'Unknown OS';
        $device = $agent->device() ?: 'Mobile';

        return trim($device . ' - ' . $platform);
    }

    /** Catat activity log bila paket tersedia (sama seperti web). */
    private function logActivity(Request $request, ?User $user, string $log, string $description): void
    {
        if (! function_exists('activity') || ! $user) {
            return;
        }

        $agent = new Agent;
        $agent->setUserAgent((string) $request->header('User-Agent'));

        activity()
            ->useLog($log)
            ->causedBy($user)
            ->withProperties([
                'ip' => $request->ip(),
                'channel' => 'mobile-api',
                'agent' => [
                    'browser' => $agent->browser(),
                    'os' => $agent->platform(),
                    'device' => $agent->device(),
                    'raw' => $request->header('User-Agent'),
                ],
            ])
            ->log($description);
    }
}
