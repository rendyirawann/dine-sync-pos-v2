@echo off
setlocal
rem ══════════════════════════════════════════════════════════════════════
rem  DineSync POS — jalankan SEMUA service dalam SATU jendela Windows
rem  Terminal (4 tab). Konsepnya sama seperti start-api.bat di rsud-hat.
rem
rem   Tab 1  Web-8000     : aplikasi web  http://127.0.0.1:8000
rem   Tab 2  Reverb-8080  : WebSocket (antrian / dapur / TV display)
rem   Tab 3  API-8001     : REST API mobile  http://127.0.0.1:8001
rem                         Swagger: http://127.0.0.1:8001/api/documentation
rem   Tab 4  Mobile-8085  : aplikasi Flutter (debug web di Brave)
rem                         http://127.0.0.1:8085
rem
rem  Brave dibuka otomatis: aplikasi mobile (oleh Flutter) + web & Swagger.
rem
rem  Login uji : owner1@trial.test / password   (atau superadmin@gmail.com)
rem  Matikan   : tekan Ctrl+C di tab yang ingin dihentikan, atau tutup jendela.
rem ══════════════════════════════════════════════════════════════════════

rem Folder proyek TANPA backslash di akhir
rem (backslash di akhir akan meng-escape tanda kutip penutup argumen -d).
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"

set "BE=%ROOT%\mobile-dine\dine-be"
set "FE=%ROOT%\mobile-dine\dine-fe"

rem ── Pemeriksaan singkat sebelum jalan ────────────────────────────────
if not exist "%ROOT%\artisan" goto :nolaravel
if not exist "%BE%\artisan" goto :nobe
if not exist "%FE%\pubspec.yaml" goto :nofe
if not exist "%BE%\vendor\autoload.php" goto :novendor

rem ── Cari Brave (untuk membuka web & Swagger) ──────────────────────────
set "BRAVE="
if exist "%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe" set "BRAVE=%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe"
if not defined BRAVE if exist "%ProgramFiles(x86)%\BraveSoftware\Brave-Browser\Application\brave.exe" set "BRAVE=%ProgramFiles(x86)%\BraveSoftware\Brave-Browser\Application\brave.exe"
if not defined BRAVE if exist "%LocalAppData%\BraveSoftware\Brave-Browser\Application\brave.exe" set "BRAVE=%LocalAppData%\BraveSoftware\Brave-Browser\Application\brave.exe"

where wt >nul 2>nul
if errorlevel 1 goto :fallback

rem ── SATU jendela Windows Terminal, 4 tab ─────────────────────────────
rem Judul tab tanpa spasi — parser wt lebih aman.
wt -w new new-tab --title Web-8000 -d "%ROOT%" cmd /k php artisan serve --host=127.0.0.1 --port=8000 ; new-tab --title Reverb-8080 -d "%ROOT%" cmd /k php artisan reverb:start ; new-tab --title API-8001 -d "%BE%" cmd /k php artisan serve --host=127.0.0.1 --port=8001 ; new-tab --title Mobile-8085 -d "%FE%" cmd /k "%FE%\debug-web.bat"
goto :browser

:fallback
rem Windows Terminal tidak ada — buka jendela terpisah seperti biasa.
echo   [i] Windows Terminal (wt) tidak ditemukan - memakai jendela terpisah.
start "DineSync - Web :8000" cmd /k "cd /d "%ROOT%" && php artisan serve --host=127.0.0.1 --port=8000"
start "DineSync - Reverb :8080" cmd /k "cd /d "%ROOT%" && php artisan reverb:start"
start "DineSync - API :8001" cmd /k "cd /d "%BE%" && php artisan serve --host=127.0.0.1 --port=8001"
start "DineSync - Mobile :8085" cmd /k ""%FE%\debug-web.bat""

:browser
rem Beri jeda agar server siap, lalu buka web & Swagger di Brave.
rem (Aplikasi mobile dibuka sendiri oleh Flutter di tab Mobile-8085.)
timeout /t 6 /nobreak >nul
if defined BRAVE start "" "%BRAVE%" "http://127.0.0.1:8000/admin/login" "http://127.0.0.1:8001/api/documentation"
if not defined BRAVE start "" "http://127.0.0.1:8000/admin/login"

echo.
echo   ==========================================================
echo    DineSync POS - semua service dijalankan
echo   ==========================================================
echo    Web admin    : http://127.0.0.1:8000/admin/login
echo    Reverb (WS)  : ws://127.0.0.1:8080
echo    API mobile   : http://127.0.0.1:8001/api/v1
echo    Swagger UI   : http://127.0.0.1:8001/api/documentation
echo    App mobile   : http://127.0.0.1:8085   ^(Brave, hot reload^)
echo   ----------------------------------------------------------
echo    Login uji    : owner1@trial.test / password
echo                   superadmin@gmail.com / 12qwaszx123!!@@##
echo   ----------------------------------------------------------
echo    Tab Mobile butuh ~30-60 detik saat compile pertama.
echo    Di tab itu: r = hot reload, R = restart, q = keluar.
echo   ==========================================================
echo.
exit /b 0

:nolaravel
echo   [X] artisan tidak ditemukan di: %ROOT%
echo       Jalankan berkas ini dari folder root project dine-sync-pos-v2.
pause
exit /b 1

:nobe
echo   [X] Backend API tidak ditemukan di: %BE%
pause
exit /b 1

:nofe
echo   [X] Aplikasi Flutter tidak ditemukan di: %FE%
pause
exit /b 1

:novendor
echo.
echo   [X] Dependensi dine-be belum terpasang.
echo.
echo       cd mobile-dine\dine-be
echo       composer install
echo.
pause
exit /b 1
