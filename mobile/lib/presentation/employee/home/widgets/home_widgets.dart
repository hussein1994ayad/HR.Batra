// أجزاء الشاشة الرئيسية للموظف: الرأس، كارد اليوم (حضور ← انصراف ← اكتمل)، الاختصارات،
// مدخل لوحة الإدارة، والتعاميم.

import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../shared/ui/ui.dart';
import '../../announcements/announcement_widgets.dart';


class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.name, required this.subtitle, required this.avatarUrl, required this.unread, required this.onNotifications});

  final String name;
  final String subtitle;
  final String avatarUrl;
  final int unread;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppAvatar(name: name, url: avatarUrl, size: 52),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Fmt.greeting(), style: AppText.bodySm),
              Text(name, style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(subtitle, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        AppIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: unread > 0 ? 'الإشعارات، $unread غير مقروءة' : 'الإشعارات',
          badge: unread,
          onPressed: onNotifications,
        ),
      ],
    );
  }
}

/// حالة يوم العمل الحالية.
enum HomeDayState { notStarted, working, done }

class HomeTodayCard extends StatelessWidget {
  const HomeTodayCard({super.key, required this.loading, required this.attendance, required this.schedule, required this.onAction, this.onLeave = false, this.isHoliday = false});

  final bool loading;
  final bool onLeave;
  final bool isHoliday;

  /// يوم دوام حسب جدول الموظف (0 = الأحد) وما هو عطلة رسمية
  bool _isWorkDay(DateTime now) {
    if (isHoliday) return false;
    final days = schedule?['work_days'];
    return days is! List || days.map((d) => (d as num).toInt()).contains(now.weekday % 7);
  }
  final Map<String, dynamic>? attendance;
  final Map<String, dynamic>? schedule;
  final VoidCallback onAction;

  static DateTime? _parse(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  /// عدد الدقائق المجدولة من "08:00:00" إلى "16:00:00".
  double? get _scheduledMinutes {
    final a = schedule?['check_in_time']?.toString().split(':');
    final b = schedule?['check_out_time']?.toString().split(':');
    if (a == null || b == null || a.length < 2 || b.length < 2) return null;
    final start = (int.tryParse(a[0]) ?? 0) * 60 + (int.tryParse(a[1]) ?? 0);
    final end = (int.tryParse(b[0]) ?? 0) * 60 + (int.tryParse(b[1]) ?? 0);
    return end > start ? (end - start).toDouble() : null;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const AppCard(
        padding: EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton(width: 120),
            SizedBox(height: AppSpace.lg),
            Skeleton(width: 180, height: 32),
            SizedBox(height: AppSpace.xl),
            Skeleton(height: 56, radius: AppRadius.sm),
          ],
        ),
      );
    }
    final checkIn = _parse(attendance?['check_in_time']);
    final checkOut = _parse(attendance?['check_out_time']);
    final state = checkOut != null
        ? HomeDayState.done
        : checkIn != null
            ? HomeDayState.working
            : HomeDayState.notStarted;

    final now = DateTime.now();
    final worked = checkIn == null ? Duration.zero : (checkOut ?? now).difference(checkIn);
    final planned = _scheduledMinutes;

    final lateMinutes = state == HomeDayState.notStarted && !onLeave ? _lateSoFar(now) : 0;
    final dayOff = state == HomeDayState.notStarted && !_isWorkDay(now);

    final (badge, tone, bigLabel, bigValue, actionLabel, actionIcon, variant) = switch (state) {
      // يوم عطلة ولم يبصم: ما نطلب منه يسجّل حضور
      HomeDayState.notStarted when dayOff => (
          isHoliday ? 'عطلة رسمية' : 'يوم عطلة',
          AppTone.info,
          'اليوم',
          'عطلة',
          'عرض سجل الدوام',
          Icons.history_rounded,
          AppButtonVariant.secondary,
        ),
      HomeDayState.notStarted => (
          lateMinutes > 0 ? 'متأخر ${_hm(Duration(minutes: lateMinutes))}' : 'لم تسجّل بعد',
          lateMinutes > 0 ? AppTone.danger : AppTone.warning,
          lateMinutes > 0 ? 'بدأ دوامك' : 'يبدأ دوامك',
          Fmt.timeOfDay(schedule?['check_in_time']?.toString()),
          'تسجيل الحضور',
          Icons.fingerprint_rounded,
          AppButtonVariant.primary,
        ),
      HomeDayState.working => (
          'في الدوام',
          AppTone.brand,
          'مدة العمل حتى الآن',
          _hm(worked),
          'تسجيل الانصراف',
          Icons.logout_rounded,
          AppButtonVariant.warning,
        ),
      HomeDayState.done => (
          'اكتمل الدوام',
          AppTone.success,
          'مجموع ساعات اليوم',
          _hm(worked),
          'عرض سجل اليوم',
          Icons.history_rounded,
          AppButtonVariant.secondary,
        ),
    };

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(Fmt.dateWithDay(now), style: AppText.bodySm.copyWith(fontWeight: FontWeight.w700))),
              StatusBadge(badge, tone: tone, dot: true),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text(bigLabel, style: AppText.caption),
          Text(bigValue, style: AppText.display.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          if (state == HomeDayState.working && planned != null) ...[
            const SizedBox(height: AppSpace.md),
            AppProgressBar(value: worked.isNegative ? 0 : worked.inMinutes / planned),
          ],
          const SizedBox(height: AppSpace.lg),
          Wrap(
            spacing: AppSpace.lg,
            runSpacing: AppSpace.xs,
            children: [
              HomeTimeChip(icon: Icons.login_rounded, label: 'الحضور', value: checkIn == null ? '--:--' : Fmt.time(checkIn)),
              HomeTimeChip(icon: Icons.logout_rounded, label: 'الانصراف', value: checkOut == null ? '--:--' : Fmt.time(checkOut)),
              if (schedule != null)
                HomeTimeChip(
                  icon: Icons.schedule_rounded,
                  label: 'الدوام',
                  value: '${Fmt.timeOfDay(schedule!['check_in_time']?.toString())} - ${Fmt.timeOfDay(schedule!['check_out_time']?.toString())}',
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          AppButton(label: actionLabel, icon: actionIcon, variant: variant, size: AppButtonSize.large, expand: true, onPressed: onAction),
          if (state == HomeDayState.notStarted && !dayOff && schedule?['grace_period_minutes'] != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Center(child: Text('سماحية التأخير ${schedule!['grace_period_minutes']} دقيقة', style: AppText.caption)),
            ),
        ],
      ),
    );
  }

  /// دقائق التأخير لحد الآن إذا ما بصم بعد (بعد السماحية، وبأيام الدوام فقط)
  int _lateSoFar(DateTime now) {
    final days = schedule?['work_days'];
    if (days is List && !days.map((d) => (d as num).toInt()).contains(now.weekday % 7)) return 0;
    final parts = schedule?['check_in_time']?.toString().split(':');
    if (parts == null || parts.length < 2) return 0;
    final start = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    final grace = (schedule?['grace_period_minutes'] as num?)?.toInt() ?? 0;
    final late = now.hour * 60 + now.minute - start;
    return late > grace ? late : 0;
  }

  static String _hm(Duration d) {
    if (d.isNegative) return '0 د';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m د';
    return m == 0 ? '$h س' : '$h س $m د';
  }
}

class HomeTimeChip extends StatelessWidget {
  const HomeTimeChip({super.key, required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: AppSpace.xs),
        Text('$label ', style: AppText.caption),
        Text(value, style: AppText.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class HomeAdminEntry extends StatelessWidget {
  const HomeAdminEntry({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tone: AppTone.accent,
      onTap: onTap,
      child: const Row(
        children: [
          ToneIcon(Icons.admin_panel_settings_rounded, tone: AppTone.accent, size: 44),
          SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('لوحة الإدارة', style: AppText.subtitle),
                Text('الطلبات، الحضور، السلف، والتتبع', style: AppText.caption),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.accent),
        ],
      ),
    );
  }
}

class HomeQuickAction {
  const HomeQuickAction(this.icon, this.title, this.tone, this.onTap);
  final IconData icon;
  final String title;
  final AppTone tone;
  final VoidCallback onTap;
}

class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({super.key, required this.actions});
  final List<HomeQuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return ResponsiveGrid(
      minItemWidth: 96,
      maxColumns: 6,
      children: [
        for (final a in actions)
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.md),
            onTap: () {
              AppHaptics.select();
              a.onTap();
            },
            semanticLabel: a.title,
            child: ExcludeSemantics(
              child: Column(
                children: [
                  ToneIcon(a.icon, tone: a.tone, size: 44),
                  const SizedBox(height: AppSpace.sm),
                  Text(a.title, textAlign: TextAlign.center, maxLines: 2, style: AppText.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class HomeAnnouncements extends StatelessWidget {
  const HomeAnnouncements({super.key, required this.loading, required this.items, this.onOpen});
  final bool loading;
  final List<AnnouncementModel> items;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList(count: 1, itemHeight: 196);
    if (items.isEmpty) {
      return const AppCard(
        child: EmptyView(title: 'لا توجد تعاميم جديدة', message: 'ستظهر هنا إعلانات الإدارة.', icon: Icons.campaign_rounded, compact: true),
      );
    }
    return FadeSlideIn(child: AnnouncementCarousel(items: items, onOpen: onOpen));
  }
}

