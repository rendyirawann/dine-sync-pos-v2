<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class UserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'username' => $this->username,
            'email' => $this->email,
            'no_wa' => $this->no_wa,
            'phone' => $this->phone,
            'avatar' => $this->avatar,
            'avatar_url' => $this->avatar ? $this->avatar_url : null,
            'is_active' => (bool) $this->is_active,
            'banned_at' => optional($this->banned_at)->toIso8601String(),
            'last_login' => optional($this->last_login)->toIso8601String(),
            'last_ip' => $this->last_ip,
            'tenant_id' => $this->tenant_id,
            'tenant_name' => $this->relationLoaded('tenant') ? ($this->tenant->name ?? null) : null,
            'roles' => $this->whenLoaded('roles', fn () => $this->roles->pluck('name')->values()),
            'created_at' => optional($this->created_at)->toIso8601String(),
        ];
    }

    /**
     * Bentuk lengkap untuk endpoint login / me: sertakan role + permission
     * supaya Flutter bisa menyembunyikan menu sesuai hak akses (seperti @can di web).
     */
    public static function withAccess($user): array
    {
        $isSuper = $user->hasRole(['Superadmin', 'superadmin']);

        return array_merge(
            (new self($user->loadMissing('roles', 'tenant')))->resolve(),
            [
                'is_superadmin' => $isSuper,
                // Superadmin mendapat semua ability (mengikuti Gate::before di web).
                'permissions' => $isSuper
                    ? \Spatie\Permission\Models\Permission::pluck('name')->values()
                    : $user->getAllPermissions()->pluck('name')->values(),
            ]
        );
    }
}
