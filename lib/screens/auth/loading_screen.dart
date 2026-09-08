import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../state/auth/auth_state.dart';
import '../../theme/app_colors.dart';
import '../app_main_screen.dart';
import 'login_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _startApp();
  }

  Future<void> _startApp() async {
    final authState = context.read<AuthState>();

    await Future.wait([
      Future.delayed(const Duration(milliseconds: 1200)),
      authState.initApp(),
    ]);

    if (!mounted) return;

    final destination = authState.isAuthenticated
        ? const AppMainScreen()
        : const LoginScreen();

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: 104,
                height: 104,
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                  cacheWidth: 512,
                ),
              ),

              const SizedBox(height: 22),

              Text(
                AppConfig.defaultAppName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Mobile ERP untuk operasional multi-company',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.slate,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 190,
                child: LinearProgressIndicator(
                  minHeight: 5,
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  backgroundColor: AppColors.softGreen,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Menyiapkan data ERP...',
                style: TextStyle(
                  color: AppColors.slate,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withValues(alpha: 0.05),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: AppColors.primary,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Akses aman ke dokumen operasional perusahaan',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
