@extends('backend.layout.app')
@section('title', 'Tenant Management')
@section('content')

    <div class="app-content flex-column-fluid mt-5">
        <div class="app-container container-xxl">

            <div class="d-flex justify-content-between align-items-center mb-6">
                <div>
                    <h1 class="text-gray-900 fw-bold fs-2"><i class="ki-outline ki-shop fs-1 me-2"></i> Tenant (UMKM)</h1>
                    <span class="text-muted fs-7">Kelola UMKM yang ikut trial. Tiap UMKM punya data terpisah.</span>
                </div>
                <button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#addTenantModal">
                    <i class="ki-outline ki-plus fs-3"></i> Tambah UMKM
                </button>
            </div>

            {{-- Flash & Validation --}}
            @if (session('success'))
                <div class="alert alert-success d-flex align-items-center">
                    <i class="ki-outline ki-check-circle fs-2 text-success me-3"></i>{{ session('success') }}
                </div>
            @endif
            @if ($errors->any())
                <div class="alert alert-danger">
                    <ul class="mb-0">
                        @foreach ($errors->all() as $error)
                            <li>{{ $error }}</li>
                        @endforeach
                    </ul>
                </div>
            @endif

            <div class="card shadow-sm">
                <div class="card-body">
                    <div class="table-responsive">
                        <table class="table align-middle table-row-dashed fs-6 gy-5">
                            <thead>
                                <tr class="text-start text-gray-500 fw-bold fs-7 text-uppercase gs-0">
                                    <th>Nama UMKM</th>
                                    <th>Slug</th>
                                    <th>User</th>
                                    <th>Trial s/d</th>
                                    <th>Link Kiosk / Display</th>
                                    <th>Status</th>
                                    <th class="text-end">Aksi</th>
                                </tr>
                            </thead>
                            <tbody>
                                @forelse ($tenants as $t)
                                    <tr>
                                        <td class="fw-bold text-gray-800">{{ $t->name }}</td>
                                        <td><span class="badge badge-light-info">{{ $t->slug }}</span></td>
                                        <td>{{ $t->users_count }} user</td>
                                        <td>{{ $t->trial_ends_at ? $t->trial_ends_at->format('d M Y') : '-' }}</td>
                                        <td>
                                            @if (config('features.queue', true))
                                                <a href="{{ url('/kiosk/' . $t->slug) }}" target="_blank"
                                                    class="badge badge-light-primary me-1">Kiosk</a>
                                                <a href="{{ url('/display/' . $t->slug) }}" target="_blank"
                                                    class="badge badge-light-primary">Display</a>
                                            @else
                                                <span class="text-muted">-</span>
                                            @endif
                                        </td>
                                        <td>
                                            @if ($t->is_active)
                                                <span class="badge badge-success">Aktif</span>
                                            @else
                                                <span class="badge badge-light-danger">Nonaktif</span>
                                            @endif
                                        </td>
                                        <td class="text-end">
                                            <button class="btn btn-sm btn-icon btn-light-primary me-1 btn-edit"
                                                title="Edit"
                                                data-action="{{ route('tenants.update', $t->id) }}"
                                                data-name="{{ $t->name }}"
                                                data-slug="{{ $t->slug }}"
                                                data-trial="{{ $t->trial_ends_at ? $t->trial_ends_at->format('Y-m-d') : '' }}"
                                                data-active="{{ $t->is_active ? 1 : 0 }}">
                                                <i class="ki-outline ki-pencil fs-4"></i>
                                            </button>

                                            <form action="{{ route('tenants.toggle', $t->id) }}" method="POST"
                                                class="d-inline">
                                                @csrf
                                                <button type="submit"
                                                    class="btn btn-sm btn-icon {{ $t->is_active ? 'btn-light-warning' : 'btn-light-success' }} me-1"
                                                    title="{{ $t->is_active ? 'Nonaktifkan' : 'Aktifkan' }}">
                                                    <i class="ki-outline {{ $t->is_active ? 'ki-lock-2' : 'ki-check' }} fs-4"></i>
                                                </button>
                                            </form>

                                            <form action="{{ route('tenants.destroy', $t->id) }}" method="POST"
                                                class="d-inline"
                                                onsubmit="return confirm('HAPUS UMKM &quot;{{ $t->name }}&quot;? Semua datanya (menu, order, user, dll) ikut terhapus permanen.')">
                                                @csrf
                                                @method('DELETE')
                                                <button type="submit" class="btn btn-sm btn-icon btn-light-danger"
                                                    title="Hapus">
                                                    <i class="ki-outline ki-trash fs-4"></i>
                                                </button>
                                            </form>
                                        </td>
                                    </tr>
                                @empty
                                    <tr>
                                        <td colspan="7" class="text-center text-muted py-10">Belum ada UMKM. Klik
                                            "Tambah UMKM".</td>
                                    </tr>
                                @endforelse
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>
        </div>
    </div>

    {{-- ============ MODAL TAMBAH ============ --}}
    <div class="modal fade" id="addTenantModal" tabindex="-1" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered">
            <div class="modal-content">
                <form action="{{ route('tenants.store') }}" method="POST">
                    @csrf
                    <div class="modal-header">
                        <h2 class="fw-bold">Tambah UMKM Baru</h2>
                        <div class="btn btn-icon btn-sm btn-active-icon-primary" data-bs-dismiss="modal">
                            <i class="ki-outline ki-cross fs-1"></i>
                        </div>
                    </div>
                    <div class="modal-body">
                        <div class="mb-5">
                            <label class="required fw-semibold fs-6 mb-2">Nama UMKM</label>
                            <input type="text" name="name" class="form-control form-control-solid"
                                placeholder="cth: Warung Makan Bu Sri" required>
                        </div>
                        <div class="mb-5">
                            <label class="fw-semibold fs-6 mb-2">Masa Trial s/d (opsional)</label>
                            <input type="date" name="trial_ends_at" class="form-control form-control-solid">
                        </div>
                        <div class="separator separator-dashed my-5"></div>
                        <div class="text-muted fs-7 mb-3">Akun Owner (untuk login UMKM ini)</div>
                        <div class="mb-5">
                            <label class="required fw-semibold fs-6 mb-2">Nama Owner</label>
                            <input type="text" name="owner_name" class="form-control form-control-solid" required>
                        </div>
                        <div class="mb-5">
                            <label class="required fw-semibold fs-6 mb-2">Email Owner</label>
                            <input type="email" name="owner_email" class="form-control form-control-solid" required>
                        </div>
                        <div class="mb-5">
                            <label class="required fw-semibold fs-6 mb-2">Password Owner</label>
                            <input type="text" name="owner_password" class="form-control form-control-solid"
                                placeholder="min. 6 karakter" required>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-light" data-bs-dismiss="modal">Batal</button>
                        <button type="submit" class="btn btn-primary">Simpan</button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    {{-- ============ MODAL EDIT ============ --}}
    <div class="modal fade" id="editTenantModal" tabindex="-1" aria-hidden="true">
        <div class="modal-dialog modal-dialog-centered">
            <div class="modal-content">
                <form id="editTenantForm" method="POST">
                    @csrf
                    @method('PUT')
                    <div class="modal-header">
                        <h2 class="fw-bold">Edit UMKM</h2>
                        <div class="btn btn-icon btn-sm btn-active-icon-primary" data-bs-dismiss="modal">
                            <i class="ki-outline ki-cross fs-1"></i>
                        </div>
                    </div>
                    <div class="modal-body">
                        <div class="mb-5">
                            <label class="required fw-semibold fs-6 mb-2">Nama UMKM</label>
                            <input type="text" name="name" id="edit_name" class="form-control form-control-solid" required>
                        </div>
                        <div class="mb-5">
                            <label class="required fw-semibold fs-6 mb-2">Slug (untuk URL kiosk/display)</label>
                            <input type="text" name="slug" id="edit_slug" class="form-control form-control-solid" required>
                        </div>
                        <div class="mb-5">
                            <label class="fw-semibold fs-6 mb-2">Masa Trial s/d</label>
                            <input type="date" name="trial_ends_at" id="edit_trial" class="form-control form-control-solid">
                        </div>
                        <div class="form-check form-switch">
                            <input class="form-check-input" type="checkbox" name="is_active" value="1" id="edit_active">
                            <label class="form-check-label fw-semibold" for="edit_active">UMKM Aktif</label>
                        </div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-light" data-bs-dismiss="modal">Batal</button>
                        <button type="submit" class="btn btn-primary">Perbarui</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
@endsection

@push('scripts')
    <script>
        document.querySelectorAll('.btn-edit').forEach(function (btn) {
            btn.addEventListener('click', function () {
                const d = this.dataset;
                const form = document.getElementById('editTenantForm');
                form.setAttribute('action', d.action);
                document.getElementById('edit_name').value = d.name;
                document.getElementById('edit_slug').value = d.slug;
                document.getElementById('edit_trial').value = d.trial;
                document.getElementById('edit_active').checked = (d.active === '1');

                const modal = new bootstrap.Modal(document.getElementById('editTenantModal'));
                modal.show();
            });
        });
    </script>
@endpush
