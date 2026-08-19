@echo off
setlocal
rem ── DineSync POS Mobile (dine-fe) — debug di browser Brave ──────────────
rem   Aplikasi : http://127.0.0.1:8085
rem   API       : http://127.0.0.1:8001  (dine-be, harus sudah jalan)
rem
rem   Berkas ini berjalan di JENDELA SAAT INI (tidak membuka jendela baru),
rem   supaya bisa dipakai sebagai salah satu tab oleh ..\..\start-dev.bat.
rem   Bisa juga dijalankan sendiri (klik dua kali).
rem
rem   Pakai port/API lain:  debug-web.bat 9000 http://192.168.1.10:8001

rem Folder proyek TANPA backslash di akhir.
rem (backslash di akhir akan meng-escape tanda kutip penutup argumen)
set "PROJ=%~dp0"
set "PROJ=%PROJ:~0,-1%"

set "PORT=%~1"
if not defined PORT set "PORT=8085"

set "API=%~2"
if not defined API set "API=http://127.0.0.1:8001"

rem ── Cari SDK Flutter ─────────────────────────────────────────────────
rem Ada di PATH belum tentu bisa dipakai: SDK di sini berada di drive D:,
rem jadi kalau drive-nya terputus perintahnya gagal dengan pesan
rem membingungkan "The system cannot find the drive specified."
set "SDK="
for /f "delims=" %%F in ('where flutter 2^>nul') do if not defined SDK set "SDK=%%~dpF"
if not defined SDK if exist "D:\src\flutter\bin\flutter.bat" set "SDK=D:\src\flutter\bin\"
if not defined SDK if exist "C:\src\flutter\bin\flutter.bat" set "SDK=C:\src\flutter\bin\"

if not defined SDK goto :nosdk
if not exist "%SDK%flutter.bat" goto :nosdk
set "FLUTTER=%SDK%flutter.bat"

rem ── Cari Brave ───────────────────────────────────────────────────────
rem Brave berbasis Chromium, jadi Flutter bisa memakainya sebagai device
rem "chrome" lewat variabel CHROME_EXECUTABLE (hot restart & DevTools aktif).
set "BRAVE="
if exist "%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe" set "BRAVE=%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe"
if not defined BRAVE if exist "%ProgramFiles(x86)%\BraveSoftware\Brave-Browser\Application\brave.exe" set "BRAVE=%ProgramFiles(x86)%\BraveSoftware\Brave-Browser\Application\brave.exe"
if not defined BRAVE if exist "%LocalAppData%\BraveSoftware\Brave-Browser\Application\brave.exe" set "BRAVE=%LocalAppData%\BraveSoftware\Brave-Browser\Application\brave.exe"

cd /d "%PROJ%" || goto :nodir

echo.
echo   ==========================================================
echo    DineSync POS Mobile - Debug Web
echo   ==========================================================
echo    SDK Flutter : %SDK%
echo    Aplikasi    : http://127.0.0.1:%PORT%
echo    API dituju  : %API%
if defined BRAVE echo    Browser     : Brave (otomatis terbuka)
if not defined BRAVE echo    Browser     : Brave tidak ditemukan - mode web-server
echo   ----------------------------------------------------------
echo    Tombol berguna di tab ini:  r = hot reload   R = restart
echo                                q = keluar
echo   ==========================================================
echo.

if not defined BRAVE goto :webserver

rem Brave dipakai sebagai "chrome device" -> aplikasi terbuka sendiri.
set "CHROME_EXECUTABLE=%BRAVE%"
call "%FLUTTER%" run -d chrome --web-hostname 127.0.0.1 --web-port %PORT% --dart-define=API_BASE_URL=%API%
goto :eof

:webserver
rem Tanpa Brave: sajikan saja, buka manual di browser apa pun.
echo   [i] Buka sendiri di browser: http://127.0.0.1:%PORT%
echo.
call "%FLUTTER%" run -d web-server --web-hostname 127.0.0.1 --web-port %PORT% --dart-define=API_BASE_URL=%API%
goto :eof

:nodir
echo   [X] Folder proyek tidak dapat dibuka: %PROJ%
pause
exit /b 1

:nosdk
echo.
echo   [X] SDK Flutter tidak dapat dijangkau.
echo.
echo   Penyebab paling sering: SDK berada di drive lepasan (di komputer ini
echo   SDK ada di D:\src\flutter) yang sedang terputus.
echo   Cek di File Explorer apakah drive-nya muncul.
echo.
echo   Solusi cepat    : sambungkan kembali drive-nya, jalankan ulang berkas ini.
echo   Solusi permanen : pindahkan folder flutter ke C:\src\flutter
echo                     lalu perbarui PATH ke C:\src\flutter\bin
echo.
pause
exit /b 1
