import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ui.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final ok = await ref.read(authControllerProvider.notifier).login(
          login: _loginCtrl.text,
          password: _passCtrl.text,
        );

    if (!mounted) return;
    if (!ok) {
      final err = ref.read(authControllerProvider).error;
      if (err != null) showSnack(context, err, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final auth = ref.watch(authControllerProvider);
    final busy = auth.isSubmitting;

    return Scaffold(
      backgroundColor: p.appBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: sp(5), vertical: sp(8)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ===== Brand =====
                  Container(
                    height: sp(16),
                    width: sp(16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.primary,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      boxShadow: [
                        BoxShadow(
                          color: p.primary.withValues(alpha: .3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 34),
                  ),
                  SizedBox(height: sp(5)),
                  Text(
                    'DineSync POS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: p.gray900,
                      letterSpacing: -.5,
                    ),
                  ),
                  SizedBox(height: sp(1.5)),
                  Text(
                    'Masuk untuk mulai melayani pelanggan',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: p.textMuted),
                  ),
                  SizedBox(height: sp(7)),

                  // ===== Form =====
                  AppCard(
                    padding: EdgeInsets.all(sp(5)),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Email / Username / No. WA',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: p.gray700,
                            ),
                          ),
                          SizedBox(height: sp(2)),
                          TextFormField(
                            controller: _loginCtrl,
                            autocorrect: false,
                            enabled: !busy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              hintText: 'owner1@trial.test',
                              prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Wajib diisi.' : null,
                          ),
                          SizedBox(height: sp(4)),
                          Text(
                            'Password',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: p.gray700,
                            ),
                          ),
                          SizedBox(height: sp(2)),
                          TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscure,
                            enabled: !busy,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => busy ? null : _submit(),
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) =>
                                (v == null || v.isEmpty) ? 'Password wajib diisi.' : null,
                          ),
                          SizedBox(height: sp(6)),
                          SizedBox(
                            height: sp(13),
                            child: ElevatedButton(
                              onPressed: busy ? null : _submit,
                              child: busy
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Masuk'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: sp(4)),

                  // ===== Info server (bisa diganti tanpa rebuild) =====
                  Center(
                    child: TextButton.icon(
                      onPressed: busy ? null : _showServerSheet,
                      icon: const Icon(Icons.dns_outlined, size: 16),
                      label: Text(
                        'Server: ${ref.read(apiClientProvider).baseUrl}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ganti alamat server saat runtime — berguna saat pindah dari localhost ke IP kantor.
  void _showServerSheet() {
    final ctrl = TextEditingController(text: AppConfig.serverBaseUrl);
    final p = context.palette;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: sp(5),
          right: sp(5),
          top: sp(5),
          bottom: MediaQuery.of(ctx).viewInsets.bottom + sp(5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Alamat Server',
              subtitle: 'Tanpa /api/v1 — contoh: http://10.0.22.20/dine-be/public',
              icon: Icons.dns_outlined,
            ),
            SizedBox(height: sp(4)),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'http://10.0.22.20:8001'),
            ),
            SizedBox(height: sp(2)),
            Text(
              'Emulator Android tidak bisa memakai localhost — gunakan 10.0.2.2 '
              'atau IP komputer Anda.',
              style: TextStyle(fontSize: 11.5, color: p.textMuted, height: 1.4),
            ),
            SizedBox(height: sp(4)),
            ElevatedButton(
              onPressed: () async {
                final url = ctrl.text.trim();
                if (url.isEmpty) return;
                await ref.read(authControllerProvider.notifier).setServer(url);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  setState(() {});
                  showSnack(context, 'Alamat server disimpan.');
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
