<div class="app-navbar flex-shrink-0 align-items-center">

    {{-- Identitas Tenant (UMKM) dari user yang sedang login --}}
    @auth
        @php($__tenant = auth()->user()->tenant)
        @php($__role = auth()->user()->getRoleNames()->first())
        <div class="app-navbar-item align-items-center me-2 me-lg-4">
            <span class="badge badge-light-primary fs-7 fw-bold px-3 py-2 d-flex align-items-center">
                <i class="ki-outline ki-shop fs-4 me-2"></i>
                <span class="text-gray-800">{{ $__tenant?->name ?? 'Semua UMKM (Superadmin)' }}</span>
                @if ($__role)
                    <span class="text-muted fw-semibold ms-2">· {{ ucfirst($__role) }}</span>
                @endif
            </span>
        </div>
    @endauth

    <!--begin::Header menu mobile toggle-->
    <div class="app-navbar-item d-lg-none ms-2 me-n4" title="Show header menu">
        <div class="btn btn-icon btn-color-gray-600 btn-active-color-primary" id="kt_app_header_menu_toggle">
            <i class="ki-outline ki-text-align-left fs-2 fw-bold"></i>
        </div>
    </div>
    <!--end::Header menu mobile toggle-->
</div>
