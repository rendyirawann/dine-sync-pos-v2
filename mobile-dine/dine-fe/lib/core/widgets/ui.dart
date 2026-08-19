import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// Kartu dasar — padanan `.card` di web (radius besar, border halus, shadow tipis).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.borderColor,
    this.onTap,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final radius = BorderRadius.circular(AppRadius.card);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? p.border),
        boxShadow: AppShadow.card(Theme.of(context).brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: padding ?? EdgeInsets.all(sp(4)),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Kartu statistik — padanan `bg-light-{color}` + label + nilai besar di dashboard web.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.tone = 'primary',
    this.caption,
    this.icon,
    this.onTap,
    this.compact = false,
  });

  final String label;
  final String value;

  /// primary | success | warning | danger | info
  final String tone;
  final String? caption;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = p.solidOf(tone);

    return AppCard(
      onTap: onTap,
      color: p.softOf(tone),
      borderColor: Colors.transparent,
      padding: EdgeInsets.all(sp(compact ? 3.5 : 4.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: accent),
                SizedBox(width: sp(1.5)),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: accent,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: sp(1.5)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: compact ? 18 : 21,
                fontWeight: FontWeight.w700,
                color: p.gray900,
                height: 1.1,
              ),
            ),
          ),
          if (caption != null) ...[
            SizedBox(height: sp(1)),
            Text(
              caption!,
              style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }
}

/// Badge status — padanan `badge-light-{color}` di web.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.text,
    this.tone = 'primary',
    this.solid = false,
    this.icon,
    this.dense = false,
  });

  final String text;
  final String tone;
  final bool solid;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = p.solidOf(tone);
    final bg = solid ? accent : p.softOf(tone);
    final fg = solid ? Colors.white : accent;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: sp(dense ? 1.5 : 2),
        vertical: sp(dense ? 0.5 : 1),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: fg),
            SizedBox(width: sp(1)),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Judul bagian + aksi opsional di kanan.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: p.gray600),
          SizedBox(width: sp(2)),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: p.gray900),
              ),
              if (subtitle != null)
                Padding(
                  padding: EdgeInsets.only(top: sp(0.5)),
                  child: Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: p.textMuted),
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Uang dengan gaya seragam (hijau untuk pemasukan, merah untuk pengeluaran).
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.tone,
    this.size = 15,
    this.weight = FontWeight.w700,
    this.short = false,
  });

  final num? value;
  final String? tone;
  final double size;
  final FontWeight weight;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Text(
      short ? Fmt.rupiahShort(value) : Fmt.rupiah(value),
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: tone == null ? p.gray900 : p.solidOf(tone!),
      ),
    );
  }
}

/// Tampilan kosong yang informatif (bukan layar putih).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: sp(8), vertical: sp(compact ? 6 : 12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(sp(4)),
              decoration: BoxDecoration(color: p.gray100, shape: BoxShape.circle),
              child: Icon(icon, size: compact ? 26 : 34, color: p.gray500),
            ),
            SizedBox(height: sp(3)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: p.textMuted, height: 1.5),
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: sp(4)),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tampilan error + tombol coba lagi.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(sp(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(sp(4)),
              decoration: BoxDecoration(color: p.dangerLight, shape: BoxShape.circle),
              child: Icon(Icons.error_outline_rounded, size: 32, color: p.danger),
            ),
            SizedBox(height: sp(3)),
            Text(
              'Gagal memuat data',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.gray900),
            ),
            SizedBox(height: sp(1.5)),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.textMuted, height: 1.5),
            ),
            if (onRetry != null) ...[
              SizedBox(height: sp(4)),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Coba Lagi'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pembungkus AsyncValue agar layar tidak perlu menulis when() berulang.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loading ?? const Center(child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(strokeWidth: 2.5),
      )),
      error: (e, _) => ErrorView(message: e.toString(), onRetry: onRetry),
      data: builder,
    );
  }
}

/// Progress bar tebal seperti widget target/budget di sidebar web (tinggi 24px).
class ThickProgressBar extends StatelessWidget {
  const ThickProgressBar({
    super.key,
    required this.percent,
    this.tone = 'primary',
    this.height = 20,
  });

  /// 0..100
  final int percent;
  final String tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final clamped = percent.clamp(0, 100) / 100;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Stack(
        children: [
          Container(height: height, color: p.softOf(tone)),
          FractionallySizedBox(
            widthFactor: clamped,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              height: height,
              decoration: BoxDecoration(color: p.solidOf(tone)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kolom pencarian ringkas.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        isDense: true,
      ),
    );
  }
}

/// Baris label–nilai untuk ringkasan (subtotal, pajak, dll).
class SummaryRow extends StatelessWidget {
  const SummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.tone,
    this.bold = false,
    this.big = false,
  });

  final String label;
  final String value;
  final String? tone;
  final bool bold;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = tone == null ? p.gray800 : p.solidOf(tone!);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: sp(1)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: big ? 14.5 : 13.5,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
              color: tone == null ? p.gray700 : color,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: big ? 18 : 14.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper snackbar seragam.
void showSnack(BuildContext context, String message, {bool error = false}) {
  final p = AppPalette.light$;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? p.danger : p.gray900,
        duration: Duration(seconds: error ? 4 : 2),
      ),
    );
}
