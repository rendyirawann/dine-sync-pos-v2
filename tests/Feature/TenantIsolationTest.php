<?php

namespace Tests\Feature;

use App\Events\CallQueueEvent;
use App\Events\NewQueueEvent;
use App\Http\Middleware\IdentifyTenant;
use App\Models\Category;
use App\Models\Menu;
use App\Models\Table;
use App\Models\Tenant;
use App\Models\User;
use App\Tenancy\TenantManager;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Routing\Route;
use Tests\TestCase;

/**
 * Jaring pengaman anti-bocor untuk arsitektur single-DB multi-tenant.
 *
 * Setiap kali ada fitur/tabel baru, jalankan test ini. Kalau ada kebocoran
 * (lupa pasang trait, query mentah, dll), test merah SEBELUM naik ke server.
 */
class TenantIsolationTest extends TestCase
{
    use RefreshDatabase;

    private TenantManager $manager;
    private Tenant $tenantA;
    private Tenant $tenantB;

    protected function setUp(): void
    {
        parent::setUp();

        $this->manager = app(TenantManager::class);
        $this->tenantA = Tenant::create(['name' => 'UMKM A', 'slug' => 'umkm-a']);
        $this->tenantB = Tenant::create(['name' => 'UMKM B', 'slug' => 'umkm-b']);

        // Data milik A
        $this->manager->runFor($this->tenantA->id, function () {
            $cat = Category::create(['name' => 'Makanan A', 'slug' => 'makanan']);
            Menu::create(['category_id' => $cat->id, 'name' => 'Nasi Goreng A', 'price' => 25000]);
        });

        // Data milik B
        $this->manager->runFor($this->tenantB->id, function () {
            $cat = Category::create(['name' => 'Makanan B', 'slug' => 'makanan']); // slug sama -> harus boleh
            Menu::create(['category_id' => $cat->id, 'name' => 'Nasi Goreng B', 'price' => 30000]);
        });

        $this->manager->forget();
    }

    /** Global scope: tenant hanya melihat datanya sendiri. */
    public function test_global_scope_isolates_reads(): void
    {
        $this->manager->runFor($this->tenantA->id, function () {
            $this->assertSame(1, Category::count());
            $this->assertSame(1, Menu::count());
            $this->assertSame('Nasi Goreng A', Menu::first()->name);
        });

        $this->manager->runFor($this->tenantB->id, function () {
            $this->assertSame(1, Category::count());
            $this->assertSame('Nasi Goreng B', Menu::first()->name);
        });
    }

    /** IDOR: mengakses ID milik tenant lain harus mengembalikan null. */
    public function test_cannot_read_other_tenant_record_by_id(): void
    {
        $menuB = $this->manager->runFor($this->tenantB->id, fn () => Menu::first());

        $this->manager->runFor($this->tenantA->id, function () use ($menuB) {
            $this->assertNull(Menu::find($menuB->id));
            $this->assertNull(Category::find($menuB->category_id));
        });
    }

    /** Auto-fill: data baru otomatis dapat tenant_id tenant aktif. */
    public function test_create_auto_fills_current_tenant(): void
    {
        $menu = $this->manager->runFor($this->tenantA->id, function () {
            $cat = Category::first();
            return Menu::create(['category_id' => $cat->id, 'name' => 'Menu Baru', 'price' => 1000]);
        });

        $this->assertSame($this->tenantA->id, $menu->tenant_id);
    }

    /** Anti-spoof: tenant_id dari input diabaikan, dipaksa ke tenant aktif. */
    public function test_cannot_spoof_tenant_id_on_create(): void
    {
        $menu = $this->manager->runFor($this->tenantA->id, function () {
            $cat = Category::first();
            $m = new Menu(['category_id' => $cat->id, 'name' => 'Menu Selundupan', 'price' => 1000]);
            $m->tenant_id = $this->tenantB->id; // coba titipkan ke tenant B
            $m->save();
            return $m;
        });

        // Harus tetap milik A, bukan B
        $this->assertSame($this->tenantA->id, $menu->fresh()->tenant_id);
    }

    /** Composite unique: nilai unik yang sama boleh ada di tenant berbeda. */
    public function test_same_unique_value_allowed_across_tenants(): void
    {
        // Sudah terbukti di setUp: kedua tenant punya category slug 'makanan'.
        $this->assertDatabaseCount('categories', 2);

        // Tambah tenant ketiga dengan slug yang sama -> tetap tidak error.
        $tenantC = Tenant::create(['name' => 'UMKM C', 'slug' => 'umkm-c']);
        $this->manager->runFor($tenantC->id, function () {
            Category::create(['name' => 'Makanan C', 'slug' => 'makanan']);
        });

        $this->assertDatabaseCount('categories', 3);
    }

    /** Tanpa konteks tenant, scope mati -> melihat semua (inilah kenapa reset wajib). */
    public function test_without_tenant_context_sees_all(): void
    {
        $this->manager->forget();
        $this->assertSame(2, Category::count());
        $this->assertSame(2, Menu::count());
    }

    /** Relasi/eager-load ikut ter-scope. */
    public function test_relationships_respect_scope(): void
    {
        $this->manager->runFor($this->tenantA->id, function () {
            // Eager-load relasi: menu beserta kategorinya, semua tetap ter-scope ke A.
            $menus = Menu::with('category')->get();
            $this->assertCount(1, $menus);
            $this->assertSame('Nasi Goreng A', $menus->first()->name);
            $this->assertSame('Makanan A', $menus->first()->category->name);
        });
    }

    /** Middleware: tenant aktif diambil dari user yang login. */
    public function test_middleware_sets_tenant_from_authenticated_user(): void
    {
        $user = $this->manager->runFor($this->tenantA->id, fn () => User::create([
            'name'     => 'Admin A',
            'username' => 'admin_a',
            'email'    => 'admin_a@test.com',
            'password' => bcrypt('password'),
        ]));
        $this->manager->forget();

        $request = Request::create('/admin/dashboard', 'GET');
        $request->setUserResolver(fn () => $user);

        (new IdentifyTenant($this->manager))->handle($request, function () {
            return response('ok');
        });

        $this->assertSame($this->tenantA->id, $this->manager->id());
    }

    /** Middleware: halaman QR publik resolve tenant dari UUID meja (tanpa login). */
    public function test_middleware_resolves_tenant_from_public_table_uuid(): void
    {
        $table = $this->manager->runFor($this->tenantB->id, fn () => Table::create([
            'table_number' => 'Meja 01',
            'capacity'     => 4,
        ]));
        $this->manager->forget();

        $request = Request::create('/menu/' . $table->uuid, 'GET');
        $route = new Route('GET', '/menu/{uuid}', []);
        $route->bind($request);
        $request->setRouteResolver(fn () => $route);

        (new IdentifyTenant($this->manager))->handle($request, function () {
            return response('ok');
        });

        $this->assertSame($this->tenantB->id, $this->manager->id());
    }

    /** Middleware: halaman kiosk/display publik resolve tenant dari slug di URL. */
    public function test_middleware_resolves_tenant_from_slug_param(): void
    {
        $request = Request::create('/display/' . $this->tenantA->slug, 'GET');
        $route = new Route('GET', '/display/{tenant}', []);
        $route->bind($request);
        $request->setRouteResolver(fn () => $route);

        (new IdentifyTenant($this->manager))->handle($request, fn () => response('ok'));

        $this->assertSame($this->tenantA->id, $this->manager->id());
    }

    /** Channel antrian/display memakai nama per-tenant. */
    public function test_queue_events_use_per_tenant_channel(): void
    {
        $new = new NewQueueEvent($this->tenantA->id);
        $this->assertSame('public-queue.' . $this->tenantA->id, $new->broadcastOn()->name);

        $call = new CallQueueEvent('halo', [], 'queue', $this->tenantB->id);
        $this->assertSame('public-display.' . $this->tenantB->id, $call->broadcastOn()->name);
    }

    /** Superadmin (tenant_id NULL) tidak men-set tenant -> bisa lihat semua. */
    public function test_superadmin_without_tenant_sees_all_via_middleware(): void
    {
        $super = User::create([
            'name'      => 'Super',
            'username'  => 'super',
            'email'     => 'super@test.com',
            'password'  => bcrypt('password'),
            'tenant_id' => null,
        ]);

        $request = Request::create('/admin/dashboard', 'GET');
        $request->setUserResolver(fn () => $super);

        (new IdentifyTenant($this->manager))->handle($request, function () {
            return response('ok');
        });

        $this->assertFalse($this->manager->has());
        $this->assertSame(2, Menu::count());
    }
}
