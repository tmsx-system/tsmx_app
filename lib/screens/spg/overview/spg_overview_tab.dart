import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/responsive/responsive_layout.dart';

class SpgOverviewTab extends StatelessWidget {
  final ValueChanged<int> onMenuSelected;

  const SpgOverviewTab({super.key, required this.onMenuSelected});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 104),
      children: [
        GridView.count(
          crossAxisCount: TmsxResponsive.columnsFor(
            context,
            phone: 3,
            tablet: 4,
            desktop: 5,
          ),
          mainAxisSpacing: 14,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _SpgShortcutTile(
              icon: Icons.photo_camera_rounded,
              label: 'Foto',
              color: const Color(0xFF2563EB),
              onTap: () => onMenuSelected(1),
            ),
            _SpgShortcutTile(
              icon: Icons.bar_chart_rounded,
              label: 'Selling',
              color: const Color(0xFF0891B2),
              onTap: () => onMenuSelected(2),
            ),
          ],
        ),
      ],
    );
  }
}

class _SpgShortcutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SpgShortcutTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(icon, color: AppColors.white, size: 28),
              ),
              const SizedBox(height: 9),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 12,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
