<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\View;
use App\Models\DailySalesTarget;
use App\Models\DailyBudget;
use App\Models\Expense;
use App\Models\Order; // Pastikan menggunakan Order (bukan Sale)
use Carbon\Carbon;

use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\URL;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        // Kunci semua URL (route/url/asset/base-href) ke APP_URL di production.
        // Ini yang MENJAGA subfolder (mis. /dine-sync-pos-v2) tidak hilang.
        // PENTING: skema mengikuti APP_URL — hanya paksa https bila APP_URL memang https,
        // supaya deploy di IP http (http://10.0.22.20/dine-sync-pos-v2) tidak rusak.
        if (config('app.env') === 'production') {
            $appUrl = (string) config('app.url');
            URL::forceRootUrl($appUrl);
            if (str_starts_with($appUrl, 'https://')) {
                URL::forceScheme('https');
            }
        }

        // Implicitly grant "Superadmin" role all permissions
        Gate::before(function ($user, $ability) {
            return $user->hasRole(['Superadmin', 'superadmin']) ? true : null;
        });

        // Inject data HANYA ke view di folder 'backend' (Sidebar Widget)
        // Dan HANYA jika user sudah login (Auth::check)
        View::composer('backend.*', function ($view) {
            if (auth()->check()) {
                $today = date('Y-m-d');

                // 1. Target Penjualan Harian
                $salesTargetObj = DailySalesTarget::where('date', $today)->first();
                $salesTarget = $salesTargetObj ? $salesTargetObj->amount : 0;

                // 2. Omzet Harian (Dari tabel orders yang sudah dibayar)
                $income = Order::whereDate('created_at', $today)
                    ->where('payment_status', 'paid')
                    ->sum('grand_total');

                // 3. Budget & Pengeluaran Harian
                $budgetObj = DailyBudget::where('date', $today)->first();
                $budget = $budgetObj ? $budgetObj->amount : 0;

                $spent = Expense::whereDate('date', $today)->sum('amount');

                // Kalkulasi Persentase Pengeluaran
                $percentage = 0;
                $progressColor = 'bg-primary';
                if ($budget > 0) {
                    $percentage = round(($spent / $budget) * 100);
                    if ($percentage >= 100) {
                        $percentage = 100;
                        $progressColor = 'bg-danger';
                    } elseif ($percentage >= 75) {
                        $progressColor = 'bg-warning';
                    }
                }

                // Kalkulasi Persentase Penjualan vs Target
                $salesPercentage = 0;
                $salesBarWidth = 0;
                $salesProgressColor = 'bg-warning';
                if ($salesTarget > 0) {
                    $salesPercentage = round(($income / $salesTarget) * 100);
                    $salesBarWidth = $salesPercentage > 100 ? 100 : $salesPercentage;
                    if ($salesPercentage >= 100) {
                        $salesProgressColor = 'bg-success';
                    } elseif ($salesPercentage >= 50) {
                        $salesProgressColor = 'bg-primary';
                    }
                }

                $view->with(compact(
                    'salesTarget',
                    'income',
                    'salesPercentage',
                    'salesBarWidth',
                    'salesProgressColor',
                    'budget',
                    'spent',
                    'percentage',
                    'progressColor'
                ));
            }
        });
    }
}
