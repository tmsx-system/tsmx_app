import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth/auth_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/responsive/responsive_layout.dart';
import '../auth/login_screen.dart';
import '../profile/profile_screen.dart';

typedef RoleScreensBuilder =
    List<Widget> Function(ValueChanged<int> onMenuSelected);
typedef RoleFloatingActionButtonBuilder =
    Widget? Function(BuildContext context, int currentIndex);
typedef RoleTabChangedCallback =
    FutureOr<void> Function(BuildContext context, int currentIndex);

class RoleMainScreen extends StatefulWidget {
  final String title;
  final String fallbackUsername;
  final List<NavigationDestination> destinations;
  final RoleScreensBuilder screensBuilder;
  final FutureOr<void> Function(BuildContext context)? onInitialize;
  final RoleTabChangedCallback? onTabChanged;
  final RoleFloatingActionButtonBuilder? floatingActionButtonBuilder;
  final int initialTabIndex;

  const RoleMainScreen({
    super.key,
    required this.title,
    required this.fallbackUsername,
    required this.destinations,
    required this.screensBuilder,
    this.onInitialize,
    this.onTabChanged,
    this.floatingActionButtonBuilder,
    this.initialTabIndex = 0,
  });

  @override
  State<RoleMainScreen> createState() => _RoleMainScreenState();
}

class _RoleMainScreenState extends State<RoleMainScreen> {
  late int _currentIndex;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = widget.screensBuilder(_changeTab);
    _currentIndex = widget.initialTabIndex.clamp(0, _screens.length - 1);
    assert(
      _screens.length >= widget.destinations.length,
      'Jumlah screen harus sama atau lebih banyak dari navigation destination.',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runInitialLoad());
    });
  }

  Future<void> _runInitialLoad() async {
    await widget.onInitialize?.call(context);
    if (!mounted) return;
    await _notifyTabChanged(_currentIndex);
  }

  Future<void> _notifyTabChanged(int index) async {
    await widget.onTabChanged?.call(context, index);
  }

  void _changeTab(int index) {
    if (index < 0 || index >= _screens.length || index == _currentIndex) return;
    setState(() => _currentIndex = index);
    unawaited(_notifyTabChanged(index));
  }

  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = context.select<AuthState, bool>(
      (state) => state.isAuthenticated,
    );
    if (!isAuthenticated) {
      _redirectToLogin();
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final subtitle = context.select<AuthState, String>((state) {
      final siteName = state.selectedSiteName.trim();
      return siteName.isNotEmpty
          ? siteName
          : state.selectedSiteCode.trim().isNotEmpty
          ? state.selectedSiteCode
          : widget.fallbackUsername;
    });
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: widget.floatingActionButtonBuilder?.call(
        context,
        _currentIndex,
      ),
      appBar: AppBar(
        toolbarHeight: 64,
        backgroundColor: AppColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        automaticallyImplyLeading: Navigator.canPop(context),
        titleSpacing: 16,
        title: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(
              Icons.person_rounded,
              color: AppColors.primary,
              size: 22,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          for (var index = 0; index < _screens.length; index++)
            Positioned.fill(
              child: _LazyRolePane(
                active: index == _currentIndex,
                child: TmsxResponsiveBody(child: _screens[index]),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _RoleBottomNav(
        destinations: widget.destinations,
        selectedIndex: _currentIndex,
        onSelected: _changeTab,
      ),
    );
  }
}

class _LazyRolePane extends StatefulWidget {
  final bool active;
  final Widget child;

  const _LazyRolePane({required this.active, required this.child});

  @override
  State<_LazyRolePane> createState() => _LazyRolePaneState();
}

class _LazyRolePaneState extends State<_LazyRolePane> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loaded = widget.active;
  }

  @override
  void didUpdateWidget(covariant _LazyRolePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_loaded) {
      _loaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Offstage(
      offstage: !widget.active,
      child: TickerMode(enabled: widget.active, child: widget.child),
    );
  }
}

class _RoleBottomNav extends StatelessWidget {
  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _RoleBottomNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withValues(alpha: 0),
            AppColors.background,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(14, 3, 14, bottomPadding > 0 ? 6 : 10),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SizedBox(
              width: double.infinity,
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDark.withValues(alpha: 0.07),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < destinations.length; index++)
                      Expanded(
                        child: _RoleBottomNavItem(
                          destination: destinations[index],
                          selected: index == selectedIndex,
                          compact: destinations.length >= 5,
                          onTap: () => onSelected(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleBottomNavItem extends StatelessWidget {
  final NavigationDestination destination;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _RoleBottomNavItem({
    required this.destination,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.slate;
    return Tooltip(
      message: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: double.infinity,
          margin: EdgeInsets.symmetric(horizontal: compact ? 1 : 2),
          padding: EdgeInsets.symmetric(horizontal: compact ? 3 : 7),
          decoration: const BoxDecoration(color: Colors.transparent),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 34 : 30,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? AppColors.softGreen : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: IconTheme(
                  data: IconThemeData(color: color, size: compact ? 20 : 21),
                  child: selected
                      ? destination.selectedIcon ?? destination.icon
                      : destination.icon,
                ),
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontSize: compact ? 9.5 : 10.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: selected ? 18 : 4,
                height: 3,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
