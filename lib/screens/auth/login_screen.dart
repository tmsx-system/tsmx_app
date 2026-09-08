import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../state/auth/auth_state.dart';
import '../../theme/app_colors.dart';
import '../app_main_screen.dart';
import 'register_site_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _siteController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  List<Map<String, String>> _siteHistory = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authState = context.read<AuthState>();
      if (authState.selectedSiteCode.trim().isNotEmpty) {
        _siteController.text = authState.selectedSiteCode;
      }
      final history = (await authState.loadFrappeSiteHistory())
          .where((site) => (site['siteCode'] ?? '').trim().isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() => _siteHistory = history);
    });
  }

  @override
  void dispose() {
    _siteController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final authState = context.read<AuthState>();
    final siteInput = _siteController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final configured = await authState.configureFrappeSite(
      codeOrUrl: siteInput,
    );

    if (!mounted) return;

    if (!configured) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authState.lastAuthError ?? 'Site tidak valid.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final success = await authState.login(
      username,
      password,
      baseUrl: authState.selectedSiteBaseUrl,
    );

    if (success) {
      await authState.saveFrappeConfig(
        username: username,
        password: password,
        baseUrl: authState.selectedSiteBaseUrl,
        siteCode: authState.selectedSiteCode,
        siteName: authState.selectedSiteName,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AppMainScreen()),
      );
    } else {
      if (!mounted) return;
      final err = authState.lastAuthError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err == null
                ? 'Invalid login. Please check your credentials.'
                : 'Login failed: $err',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _useHistorySite(Map<String, String> site) {
    final code = (site['siteCode'] ?? '').trim();
    if (code.isNotEmpty) _siteController.text = code.toUpperCase();
  }

  String _historySiteLabel(Map<String, String> site) {
    final code = (site['siteCode'] ?? '').trim();
    return code.isEmpty ? 'SITE' : code.toUpperCase();
  }

  Future<void> _continueSample() async {
    setState(() => _isLoading = true);

    final authState = context.read<AuthState>();
    authState.loginSample();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const AppMainScreen()));
  }

  Future<void> _openRegisterSitePage() async {
    final registered = await Navigator.of(context).push<RegisteredSiteResult>(
      MaterialPageRoute(builder: (_) => const RegisterSiteScreen()),
    );
    if (registered == null || !mounted) return;
    setState(() {
      _siteController.text = registered.siteCode;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${registered.siteName} berhasil diregister.'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primary),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.surfaceMuted,
      labelStyle: const TextStyle(color: AppColors.slate, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shadowColor: AppColors.primary.withValues(alpha: 0.18),
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ).copyWith(
      overlayColor: WidgetStateProperty.all(
        AppColors.accentYellow.withValues(alpha: 0.25),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _LoginBrand(),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDark.withValues(alpha: 0.08),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Form(key: _formKey, child: _loginForm(authState)),
                ),
                const SizedBox(height: 26),
                Text(
                  'Powered by ${AppConfig.defaultAppName}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginForm(AuthState authState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_siteHistory.isNotEmpty) ...[
          const Text(
            'Terakhir digunakan',
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final site in _siteHistory)
                ActionChip(
                  avatar: const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  label: Text(_historySiteLabel(site)),
                  onPressed: _isLoading ? null : () => _useHistorySite(site),
                  backgroundColor: AppColors.softGreen,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.12),
                  ),
                  labelStyle: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        TextFormField(
          controller: _siteController,
          decoration: _inputDecoration(
            label: 'Kode Perusahaan',
            icon: Icons.dns_outlined,
          ),
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) {
            FocusScope.of(context).nextFocus();
          },
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Masukkan kode perusahaan';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _usernameController,
          decoration: _inputDecoration(
            label: 'Email / Username',
            icon: Icons.person_outline,
          ),
          textInputAction: TextInputAction.next,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter your email';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: _inputDecoration(
            label: 'Password',
            icon: Icons.lock_outline,
            suffixIcon: IconButton(
              splashRadius: 22,
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: AppColors.primary,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
          ),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) {
            if (!_isLoading) _submit();
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter your password';
            }
            if (value.length < 4) return 'Password too short';
            return null;
          },
        ),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            authState.setRememberDevice(!authState.rememberDevice);
          },
          child: Row(
            children: [
              Transform.scale(
                scale: 0.78,
                child: Switch(
                  value: authState.rememberDevice,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.primary,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: AppColors.softGreen,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: authState.setRememberDevice,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'Ingat perangkat ini',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          style: _primaryButtonStyle(),
          child: _isLoading
              ? const _ButtonSpinner()
              : const Text(
                  'Log in',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1.1,
                  ),
                ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _continueSample,
          icon: const Icon(Icons.dataset_outlined),
          label: const Text('Sample'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
            backgroundColor: AppColors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Register Your ERP',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.slate,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _openRegisterSitePage,
          icon: const Icon(Icons.app_registration_rounded),
          label: const Text('Register'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.25)),
            backgroundColor: AppColors.softGreen.withValues(alpha: 0.18),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 108,
          height: 108,
          child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
        ),
        const SizedBox(height: 6),
        const Text(
          'Mobile ERP untuk operasional multi-company',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.slate,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }
}
