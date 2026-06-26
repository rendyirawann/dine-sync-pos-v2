{{-- Developer Credit Modal — trigger: CTRL + SHIFT + ALT + R. Self-contained, auto-adapt tema host. --}}
@verbatim
<script>
(function () {
    if (window.__rdevCreditInit) return;
    window.__rdevCreditInit = true;

    /* ---------- color helpers ---------- */
    var _cvs, _ctx;
    function toRGBA(str) {
        if (str == null) return null;
        str = ('' + str).trim();
        if (!str) return null;
        try {
            if (!_ctx) { _cvs = document.createElement('canvas'); _cvs.width = _cvs.height = 1; _ctx = _cvs.getContext('2d'); }
            _ctx.clearRect(0, 0, 1, 1);
            _ctx.fillStyle = 'rgba(0,0,0,0)';
            _ctx.fillStyle = str;            // invalid color -> fillStyle stays transparent
            _ctx.fillRect(0, 0, 1, 1);
            var d = _ctx.getImageData(0, 0, 1, 1).data;
            return [d[0], d[1], d[2], d[3] / 255];
        } catch (e) { return null; }
    }
    function lum(c) {
        var a = [c[0], c[1], c[2]].map(function (v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
        return 0.2126 * a[0] + 0.7152 * a[1] + 0.0722 * a[2];
    }
    function contrast(c1, c2) {
        var l1 = lum(c1), l2 = lum(c2), hi = Math.max(l1, l2), lo = Math.min(l1, l2);
        return (hi + 0.05) / (lo + 0.05);
    }
    function detectAccent() {
        var de = document.documentElement, bd = document.body;
        var names = ['--bs-primary', '--primary', '--color-primary', '--accent', '--theme-color'];
        for (var i = 0; i < names.length; i++) {
            var v = getComputedStyle(de).getPropertyValue(names[i]);
            if (!v && bd) v = getComputedStyle(bd).getPropertyValue(names[i]);
            var c = toRGBA(v);
            if (c && c[3] > 0) return c;
        }
        var sels = ['.btn-primary', '.bg-primary', 'button[type=submit]', '[class*="primary"]'];
        for (var j = 0; j < sels.length; j++) {
            var el = null; try { el = document.querySelector(sels[j]); } catch (e) {}
            if (el) {
                var bg = toRGBA(getComputedStyle(el).backgroundColor);
                if (bg && bg[3] > 0) return bg;
                var col = toRGBA(getComputedStyle(el).color);
                if (col && col[3] > 0) return col;
            }
        }
        var a = document.querySelector('a');
        if (a) { var lc = toRGBA(getComputedStyle(a).color); if (lc && lc[3] > 0) return lc; }
        return null;
    }

    /* ---------- INTI: baca tema host -> set CSS vars di root modal ---------- */
    function applyHostTheme(r) {
        try {
            // 1. FONT
            var f = (document.body && getComputedStyle(document.body).fontFamily) || '';
            if (!f) f = getComputedStyle(document.documentElement).fontFamily || '';
            if (f) r.style.setProperty('--rdev-font', f);

            // 2. TERANG/GELAP dari background efektif halaman
            var bg = toRGBA(document.body && getComputedStyle(document.body).backgroundColor);
            if (!bg || bg[3] === 0) bg = toRGBA(getComputedStyle(document.documentElement).backgroundColor);
            if (!bg || bg[3] === 0) bg = [255, 255, 255, 1];
            var isDark = lum(bg) < 0.5;
            if (isDark) {
                r.style.setProperty('--rdev-surface', '#1c1e26');
                r.style.setProperty('--rdev-text', '#f4f5f7');
                r.style.setProperty('--rdev-muted', '#aab2c0');
                r.style.setProperty('--rdev-border', 'rgba(255,255,255,.14)');
            } else {
                r.style.setProperty('--rdev-surface', '#ffffff');
                r.style.setProperty('--rdev-text', '#111827');
                r.style.setProperty('--rdev-muted', '#6b7280');
                r.style.setProperty('--rdev-border', 'rgba(17,24,39,.12)');
            }

            // 3. AKSEN
            var ac = detectAccent() || [99, 102, 241, 1];
            r.style.setProperty('--rdev-accent', 'rgb(' + (ac[0] | 0) + ',' + (ac[1] | 0) + ',' + (ac[2] | 0) + ')');

            // 4. KONTRAS teks-di-atas-aksen via rasio kontras WCAG (bukan ambang luminance)
            var cWhite = contrast(ac, [255, 255, 255]);
            var cBlack = contrast(ac, [17, 17, 17]);
            r.style.setProperty('--rdev-accent-contrast', cWhite >= cBlack ? '#ffffff' : '#111111');
        } catch (e) {
            // 6. fallback netral-gelap
            r.style.setProperty('--rdev-accent', '#6366f1');
            r.style.setProperty('--rdev-accent-contrast', '#ffffff');
            r.style.setProperty('--rdev-surface', '#1c1e26');
            r.style.setProperty('--rdev-text', '#f4f5f7');
            r.style.setProperty('--rdev-muted', '#aab2c0');
            r.style.setProperty('--rdev-border', 'rgba(255,255,255,.14)');
            r.style.setProperty('--rdev-font', "system-ui,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif");
        }
    }

    /* ---------- CSS (statik pakai var + default wajar + prefers-color-scheme) ---------- */
    var CSS = [
        '#rdev-root,#rdev-root *{box-sizing:border-box}',
        "#rdev-root{--rdev-accent:#6366f1;--rdev-accent-contrast:#fff;--rdev-surface:#1c1e26;--rdev-text:#f4f5f7;--rdev-muted:#aab2c0;--rdev-border:rgba(255,255,255,.14);--rdev-font:system-ui,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-family:var(--rdev-font)}",
        '@media (prefers-color-scheme:light){#rdev-root{--rdev-surface:#fff;--rdev-text:#111827;--rdev-muted:#6b7280;--rdev-border:rgba(17,24,39,.12)}}',
        '.rdev-backdrop{position:fixed;inset:0;z-index:2147483600;display:none;align-items:center;justify-content:center;background:rgba(0,0,0,.5);-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);padding:16px;opacity:0;transition:opacity .25s ease}',
        '#rdev-root.rdev-open .rdev-backdrop{display:flex;opacity:1}',
        '.rdev-modal{position:relative;width:100%;max-width:420px;background:var(--rdev-surface);color:var(--rdev-text);border:1px solid var(--rdev-border);border-radius:18px;padding:30px 24px 20px;box-shadow:0 24px 60px rgba(0,0,0,.4);font-family:var(--rdev-font);text-align:center;transform:translateY(14px) scale(.97);opacity:0;transition:transform .3s cubic-bezier(.2,.8,.2,1),opacity .3s ease}',
        '#rdev-root.rdev-open .rdev-modal{transform:none;opacity:1}',
        '.rdev-close{position:absolute;top:12px;right:12px;width:34px;height:34px;border-radius:9px;border:1px solid var(--rdev-border);background:transparent;color:var(--rdev-muted);cursor:pointer;display:flex;align-items:center;justify-content:center;font-size:20px;line-height:1;font-family:var(--rdev-font);transition:color .15s,border-color .15s}',
        '.rdev-close:hover{color:var(--rdev-text);border-color:var(--rdev-accent)}',
        '.rdev-avatar{width:84px;height:84px;border-radius:50%;margin:2px auto 14px;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:30px;letter-spacing:1px;background:var(--rdev-accent);color:var(--rdev-accent-contrast);box-shadow:0 8px 22px rgba(0,0,0,.2)}',
        '.rdev-name{font-size:20px;font-weight:700;margin:0 0 3px;color:var(--rdev-text)}',
        '.rdev-role{display:inline-block;font-size:11.5px;font-weight:600;letter-spacing:.3px;color:var(--rdev-accent-contrast);background:var(--rdev-accent);padding:3px 11px;border-radius:999px;margin-bottom:14px}',
        '.rdev-bio{font-size:13px;line-height:1.65;color:var(--rdev-muted);margin:0 0 18px}',
        '.rdev-socials{display:flex;gap:9px;justify-content:center;flex-wrap:wrap;margin-bottom:16px}',
        '.rdev-social{display:inline-flex;align-items:center;gap:7px;text-decoration:none;font-size:12px;font-weight:600;color:var(--rdev-text);border:1px solid var(--rdev-border);border-radius:10px;padding:8px 11px;transition:border-color .15s,transform .15s}',
        '.rdev-social:hover{border-color:var(--rdev-accent);transform:translateY(-1px)}',
        '.rdev-social svg{width:16px;height:16px;fill:currentColor;flex:none;display:block}',
        '.rdev-hint{font-size:10.5px;color:var(--rdev-muted);margin-top:2px}',
        '.rdev-kbd{border:1px solid var(--rdev-border);border-radius:6px;padding:1px 6px;font-size:10px;color:var(--rdev-muted)}',
        '.rdev-close:focus-visible,.rdev-social:focus-visible{outline:2px solid var(--rdev-accent);outline-offset:2px}',
        '@media (prefers-reduced-motion:reduce){.rdev-backdrop,.rdev-modal{transition:none}.rdev-modal{transform:none}}',
        '@media (max-width:480px){.rdev-modal{padding:26px 16px 16px}.rdev-social{font-size:11.5px;padding:7px 9px}}'
    ].join('');

    /* ---------- inline brand SVG ---------- */
    var IG = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zM12 0C8.741 0 8.333.014 7.053.072 2.695.272.273 2.69.073 7.052.014 8.333 0 8.741 0 12c0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98C8.333 23.986 8.741 24 12 24c3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98C15.668.014 15.259 0 12 0zm0 5.838a6.162 6.162 0 100 12.324 6.162 6.162 0 000-12.324zM12 16a4 4 0 110-8 4 4 0 010 8zm6.406-11.845a1.44 1.44 0 100 2.881 1.44 1.44 0 000-2.881z"/></svg>';
    var TT = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.08-.14 1.62.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/></svg>';
    var LI = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 01-2.063-2.065 2.064 2.064 0 112.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.225 0z"/></svg>';
    var GH = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/></svg>';

    function soc(svg, href, label) {
        return '<a class="rdev-social" href="' + href + '" target="_blank" rel="noopener noreferrer">' + svg + '<span>' + label + '</span></a>';
    }

    var HTML =
        '<div class="rdev-backdrop" id="rdev-backdrop">' +
            '<div class="rdev-modal" role="dialog" aria-modal="true" aria-labelledby="rdev-name" id="rdev-modal">' +
                '<button class="rdev-close" id="rdev-close" type="button" aria-label="Tutup">×</button>' +
                '<div class="rdev-avatar" aria-hidden="true">RI</div>' +
                '<h2 class="rdev-name" id="rdev-name">Rendy Irawan, S.Kom</h2>' +
                '<div class="rdev-role">Full Stack Developer</div>' +
                '<p class="rdev-bio">Membangun aplikasi web &amp; mobile dari ide sampai siap pakai. Founder HustleSync, ngembangin produk digital dan solusi bisnis seperti sistem POS dan tools berbasis AI.</p>' +
                '<div class="rdev-socials">' +
                    soc(IG, 'https://instagram.com/reillvx_', '@reillvx_') +
                    soc(TT, 'https://www.tiktok.com/@beoulveee', '@beoulveee') +
                    soc(LI, 'https://linkedin.com/in/rendyirawann', 'rendyirawann') +
                    soc(GH, 'https://github.com/rendyirawann', 'rendyirawann') +
                '</div>' +
                '<div class="rdev-hint">Tekan <span class="rdev-kbd">CTRL + SHIFT + ALT + R</span></div>' +
            '</div>' +
        '</div>';

    function init() {
        var st = document.createElement('style');
        st.id = 'rdev-style';
        st.textContent = CSS;
        document.head.appendChild(st);

        var root = document.createElement('div');
        root.id = 'rdev-root';
        root.setAttribute('aria-hidden', 'true');
        root.innerHTML = HTML;
        document.body.appendChild(root);

        var backdrop = root.querySelector('#rdev-backdrop');
        var modal = root.querySelector('#rdev-modal');
        var closeBtn = root.querySelector('#rdev-close');
        var isOpen = false, lastFocused = null, prevOverflow = '';

        function focusables() {
            return Array.prototype.slice.call(root.querySelectorAll('a[href],button:not([disabled])'));
        }
        function open() {
            if (isOpen) return;
            isOpen = true;
            lastFocused = document.activeElement;
            applyHostTheme(root);                 // re-apply tema host tiap dibuka
            root.classList.add('rdev-open');
            root.setAttribute('aria-hidden', 'false');
            prevOverflow = document.body.style.overflow;
            document.body.style.overflow = 'hidden';
            setTimeout(function () { try { closeBtn.focus(); } catch (e) {} }, 10);
        }
        function close() {
            if (!isOpen) return;
            isOpen = false;
            root.classList.remove('rdev-open');
            root.setAttribute('aria-hidden', 'true');
            document.body.style.overflow = prevOverflow || '';
            if (lastFocused && lastFocused.focus) { try { lastFocused.focus(); } catch (e) {} }
        }
        function toggle() { isOpen ? close() : open(); }

        closeBtn.addEventListener('click', close);
        backdrop.addEventListener('click', function (e) { if (e.target === backdrop) close(); });
        modal.addEventListener('click', function (e) { e.stopPropagation(); });

        document.addEventListener('keydown', function (e) {
            if (e.ctrlKey && e.shiftKey && e.altKey && (e.key === 'r' || e.key === 'R' || e.code === 'KeyR')) {
                e.preventDefault();
                toggle();
                return;
            }
            if (!isOpen) return;
            if (e.key === 'Escape') { e.preventDefault(); close(); return; }
            if (e.key === 'Tab') {                // focus-trap
                var f = focusables();
                if (!f.length) return;
                var first = f[0], last = f[f.length - 1];
                if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
                else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
            }
        }, true);

        applyHostTheme(root);                     // init
    }

    if (document.body) init();
    else document.addEventListener('DOMContentLoaded', init);
})();
</script>
@endverbatim
