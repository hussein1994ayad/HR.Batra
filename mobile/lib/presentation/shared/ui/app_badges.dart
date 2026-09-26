import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

/// شارة حالة صغيرة: "معلق"، "مقبول"، "مرفوض"...
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = AppTone.neutral, this.icon, this.dot = false});

  final String label;
  final AppTone tone;
  final IconData? icon;
  final bool dot;

  /// شارة جاهزة لحالات الطلبات في القاعدة (pending/approved/rejected...).
  factory StatusBadge.request(String? status, {Key? key}) {
    return switch (status) {
      'approved' || 'paid' || 'completed' || 'issued' => StatusBadge('مقبول', key: key, tone: AppTone.success, icon: Icons.check_circle_rounded),
      'rejected' || 'cancelled' => StatusBadge('مرفوض', key: key, tone: AppTone.danger, icon: Icons.cancel_rounded),
      'pending' => StatusBadge('قيد المراجعة', key: key, tone: AppTone.warning, icon: Icons.schedule_rounded),
      _ => StatusBadge(status ?? '—', key: key),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2, vertical: 3),
      decoration: BoxDecoration(color: tone.container, borderRadius: AppRadius.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: tone.color, shape: BoxShape.circle)),
            const SizedBox(width: AppSpace.xs + 2),
          ] else if (icon != null) ...[
            Icon(icon, size: 14, color: tone.color),
            const SizedBox(width: AppSpace.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: tone.color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// أيقونة داخل مربع ملوّن خفيف (تُستعمل في القوائم والبطاقات).
class ToneIcon extends StatelessWidget {
  const ToneIcon(this.icon, {super.key, this.tone = AppTone.brand, this.size = 40});

  final IconData icon;
  final AppTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tone.container, borderRadius: BorderRadius.circular(size * 0.3)),
      alignment: Alignment.center,
      child: Icon(icon, color: tone.color, size: size * 0.5),
    );
  }
}

/// صورة شخصية مع الحروف الأولى كبديل.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, this.url, this.size = 44, this.tone = AppTone.brand});

  final String name;
  final String? url;
  final double size;
  final AppTone tone;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.characters.first;
    return '${parts.first.characters.first} ${parts[1].characters.first}';
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initials(name),
        style: AppText.label.copyWith(color: tone.color, fontSize: size * 0.34, height: 1),
      ),
    );
    final hasUrl = url != null && url!.isNotEmpty;
    return Semantics(
      label: 'صورة $name',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: tone.container, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: hasUrl
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, __, ___) => fallback,
                loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
              )
            : fallback,
      ),
    );
  }
}
