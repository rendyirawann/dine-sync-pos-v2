<?php

namespace App\Http\Controllers\Backend;

use App\Http\Controllers\Controller;
use App\Models\Setting;
use App\Models\Tenant;
use App\Models\User;
use App\Tenancy\TenantManager;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * Kelola UMKM (tenant). HANYA superadmin yang bisa akses
 * (route di-gate 'can:view_resources' yang hanya dimiliki superadmin).
 *
 * Catatan: model Tenant TIDAK ter-scope (dia registry), jadi superadmin
 * (tenant_id NULL) melihat semua tenant. Saat membuat data milik tenant
 * (Setting, user owner) kita bungkus dengan TenantManager::runFor agar
 * tenant_id terisi otomatis dan benar.
 */
class TenantController extends Controller
{
    public function index()
    {
        $tenants = Tenant::withCount('users')->orderBy('created_at', 'desc')->get();

        return view('backend.tenant_management.index', compact('tenants'));
    }

    public function store(Request $request)
    {
        $request->validate([
            'name'           => 'required|string|max:255',
            'trial_ends_at'  => 'nullable|date',
            'owner_name'     => 'required|string|max:255',
            'owner_email'    => 'required|email|max:255|unique:users,email',
            'owner_password' => 'required|string|min:6',
        ], [], [
            'owner_name'     => 'nama owner',
            'owner_email'    => 'email owner',
            'owner_password' => 'password owner',
        ]);

        DB::transaction(function () use ($request) {
            $tenant = Tenant::create([
                'name'          => $request->name,
                'slug'          => $this->uniqueSlug($request->name),
                'is_active'     => true,
                'trial_ends_at' => $request->trial_ends_at,
            ]);

            // Buat data awal milik tenant baru (setting + user owner) di dalam konteks tenant.
            app(TenantManager::class)->runFor($tenant->id, function () use ($request) {
                Setting::create([
                    'store_name' => $request->name,
                    'tax_rate'   => 10,
                ]);

                $owner = User::create([
                    'name'              => $request->owner_name,
                    'username'          => $this->uniqueUsername($request->owner_name),
                    'email'             => $request->owner_email,
                    'password'          => Hash::make($request->owner_password),
                    'is_active'         => true,
                    'email_verified_at' => now(),
                ]);
                $owner->assignRole('admin');
            });
        });

        return redirect()->route('tenants.index')->with('success', 'UMKM baru beserta akun owner-nya berhasil dibuat.');
    }

    public function update(Request $request, $id)
    {
        $tenant = Tenant::findOrFail($id);

        $request->validate([
            'name'          => 'required|string|max:255',
            'slug'          => 'required|string|max:255|alpha_dash|unique:tenants,slug,' . $tenant->id,
            'trial_ends_at' => 'nullable|date',
        ]);

        $tenant->update([
            'name'          => $request->name,
            'slug'          => Str::slug($request->slug),
            'trial_ends_at' => $request->trial_ends_at,
            'is_active'     => $request->boolean('is_active'),
        ]);

        return redirect()->route('tenants.index')->with('success', 'Data UMKM berhasil diperbarui.');
    }

    public function toggleActive($id)
    {
        $tenant = Tenant::findOrFail($id);
        $tenant->update(['is_active' => ! $tenant->is_active]);

        $status = $tenant->is_active ? 'diaktifkan' : 'dinonaktifkan';

        return redirect()->route('tenants.index')->with('success', "UMKM {$tenant->name} berhasil {$status}.");
    }

    public function destroy($id)
    {
        $tenant = Tenant::findOrFail($id);

        DB::transaction(function () use ($tenant) {
            // Bersihkan relasi role/permission milik user tenant ini (di-key oleh uuid user).
            $userIds = DB::table('users')->where('tenant_id', $tenant->id)->pluck('id');
            if ($userIds->isNotEmpty()) {
                DB::table('model_has_roles')->whereIn('model_id', $userIds)->delete();
                DB::table('model_has_permissions')->whereIn('model_id', $userIds)->delete();
            }

            // Hapus semua data milik tenant (urutan anak -> induk agar aman terhadap FK).
            $tables = [
                'stock_opname_details', 'stock_movements', 'stock_opnames',
                'order_details', 'orders', 'menu_ingredients', 'ingredient_batches',
                'ingredients', 'suppliers', 'menus', 'categories', 'tables',
                'promos', 'queues', 'shifts', 'expenses', 'daily_budgets',
                'daily_sales_targets', 'settings', 'users',
            ];
            foreach ($tables as $table) {
                DB::table($table)->where('tenant_id', $tenant->id)->delete();
            }

            $tenant->delete();
        });

        return redirect()->route('tenants.index')->with('success', 'UMKM beserta seluruh datanya telah dihapus.');
    }

    private function uniqueSlug(string $name): string
    {
        $base = Str::slug($name) ?: 'umkm';
        $slug = $base;
        $i = 1;
        while (Tenant::where('slug', $slug)->exists()) {
            $slug = $base . '-' . $i;
            $i++;
        }

        return $slug;
    }

    private function uniqueUsername(string $name): string
    {
        $base = Str::slug($name, '_') ?: 'owner';
        $username = $base;
        $i = 1;
        while (DB::table('users')->where('username', $username)->exists()) {
            $username = $base . '_' . $i;
            $i++;
        }

        return $username;
    }
}
