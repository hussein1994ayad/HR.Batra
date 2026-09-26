// =========================================================================
// HR Pro — الشاشة الرئيسية للموظف
// =========================================================================
// • تحية حسب الوقت + الإشعارات غير المقروءة
// • بطاقة "اليوم": زر واحد يتغير حسب الحالة (حضور ← انصراف ← اكتمل الدوام)
// • أوقات الدوام، اختصارات، والتعاميم
// منطق التحميل والاشتراك الفوري والتتبع والتذكيرات لم يتغير.
// =========================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/routes/app_router.dart';
import '../../core/services/location_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/ota_service.dart';
import '../../core/services/schedule_service.dart';
import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int) onTabChange;
  final ValueNotifier<int>? refreshNotifier;

  const HomeScreen({super.key, required this.onTabChange, this.refreshNotifier});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _employeeName = 'موظف متميز';
  String _departmentName = 'القسم العام';
  String _avatarUrl = '';
  bool _isLoading = true;
  List<Map<String, dynamic>> _announcements = [];
  Map<String, dynamic>? _todayAttendance;
  String _userRole = 'employee';
  int _unreadNotificationsCount = 0;
  dynamic _realtimeSubscription;
  dynamic _attendanceSubscription;
  Map<String, dynamic>? _workSchedule;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _subscribeToNotifications();
    _subscribeToAttendance();
    // تحديث الدوام لما يرجع المستخدم للشاشة الرئيسية من تاب آخر
    widget.refreshNotifier?.addListener(_onRefreshRequested);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final updateInfo = await OtaService.checkVersion();
        if (mounted &&
            (updateInfo['status'] == OtaStatus.mandatoryUpdate ||
                updateInfo['status'] == OtaStatus.optionalUpdate)) {
          OtaService.showUpdatePrompt(context, updateInfo);
        }
      } catch (e) {
        debugPrint('OTA check non-fatal error: $e');
      }
    });
  }

  void _subscribeToNotifications() {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    _realtimeSubscription = SupabaseService.client
        .channel('public:notifications:user:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'employee_id',
            value: user.id,
          ),
          callback: (payload) async {
            if (!mounted) return;
            setState(() => _unreadNotificationsCount++);

            try {
              unawaited(SystemSound.play(SystemSoundType.alert));
              unawaited(HapticFeedback.mediumImpact());
            } catch (e) {
              debugPrint('خطأ في تشغيل صوت الإشعار: $e');
            }

            final data = payload.newRecord;
            // Show a REAL system notification with sound — works even if
            // the user is on another tab. FCM push handles this when the
            // app is in the background; this covers the in-app case.
            await NotificationService.showLocalNotification(
              title: (data['title'] ?? 'تنبيه جديد').toString(),
              body: (data['body'] ?? '').toString(),
            );
          },
        )
        .subscribe((status, [error]) {
          debugPrint('=== notifications channel: $status ===');
          if (error != null) debugPrint('=== channel error: $error ===');
        });
  }

  /// تنفَّذ لما يعود المستخدم للشاشة الرئيسية
  void _onRefreshRequested() {
    if (!mounted) return;
    // نحدث بيانات الدوام فقط (خفيف وسريع)
    _refreshAttendanceOnly();
  }

  Future<void> _refreshAttendanceOnly() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    try {
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      final rec = await SupabaseService.client
          .from('attendance')
          .select()
          .eq('employee_id', user.id)
          .eq('work_date', todayStr)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _todayAttendance = rec;
        });
      }
    } catch (e) {
      debugPrint('تعذر تحديث سجل الدوام: \$e');
    }
  }

  /// يستمع لأي تغيير في جدول attendance لليوم الحالي ويحدث الكارد فوراً
  void _subscribeToAttendance() {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final todayStr = DateTime.now().toIso8601String().split('T')[0];

    _attendanceSubscription = SupabaseService.client
        .channel('home:attendance:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'employee_id',
            value: user.id,
          ),
          callback: (payload) {
            if (!mounted) return;
            final rec = payload.newRecord;
            // نتحقق إن السجل ليوم اليوم فقط
            if (rec['work_date'] == todayStr) {
              setState(() {
                _todayAttendance = Map<String, dynamic>.from(rec);
              });
              // تحديث التتبع بناءً على حالة الحضور الجديدة
              if (rec['check_in_time'] != null && rec['check_out_time'] == null) {
                LocationService.startTracking(employeeId: user.id);
              } else if (rec['check_out_time'] != null) {
                LocationService.stopTracking();
              }
            }
          },
        )
        .subscribe((status, [error]) {
          debugPrint('=== attendance channel: \$status ===');
        });
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onRefreshRequested);
    if (_realtimeSubscription != null) {
      SupabaseService.client.removeChannel(_realtimeSubscription as RealtimeChannel);
    }
    if (_attendanceSubscription != null) {
      SupabaseService.client.removeChannel(_attendanceSubscription as RealtimeChannel);
    }
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final empData = await SupabaseService.client
          .from('v_employee_directory')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (empData != null) {
        setState(() {
          _employeeName = (empData['full_name'] ?? _employeeName) as String;
          final String deptName = (empData['department_name'] ?? 'القسم العام') as String;
          final String branchName = (empData['branch_name'] ?? 'الفرع العام') as String;
          _departmentName = '$deptName • $branchName';
          _avatarUrl = (empData['avatar_url'] ?? '') as String;
          _userRole = (empData['role'] ?? 'employee') as String;
        });
      }

      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      final scheduleQuery = ScheduleService.fetchEffectiveSchedule();

      final results = await Future.wait<dynamic>([
        scheduleQuery,
        SupabaseService.client
            .from('announcements')
            .select()
            .order('is_pinned', ascending: false)
            .order('created_at', ascending: false)
            .limit(3),
        SupabaseService.client
            .from('attendance')
            .select()
            .eq('employee_id', user.id)
            .eq('work_date', todayStr)
            .maybeSingle(),
        SupabaseService.client
            .from('notifications')
            .select('id')
            .eq('employee_id', user.id)
            .eq('is_read', false),
      ]);

      final schedData = results[0];
      final announcementsData = results[1] as List<dynamic>;
      final attendanceData = results[2];
      final unreadRes = results[3] as List<dynamic>;

      setState(() {
        _workSchedule = schedData != null ? schedData as Map<String, dynamic> : null;
        _announcements = List<Map<String, dynamic>>.from(announcementsData);
        _todayAttendance = attendanceData != null ? attendanceData as Map<String, dynamic> : null;
        _unreadNotificationsCount = unreadRes.length;
      });


      if (_todayAttendance != null &&
          _todayAttendance!['check_in_time'] != null &&
          _todayAttendance!['check_out_time'] == null) {
        unawaited(LocationService.startTracking(employeeId: user.id));
      } else if (_todayAttendance != null && _todayAttendance!['check_out_time'] != null) {
        unawaited(LocationService.stopTracking());
      } else {
        unawaited(LocationService.stopTracking());
      }
    } catch (e) {
      debugPrint('خطأ في تحميل بيانات لوحة الموظف: $e');
      if (mounted) {
        AppSnack.error(context, 'تعذّر تحديث البيانات، تأكد من اتصال الإنترنت.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  // ==========================================================================
  // Build
  // ==========================================================================
  bool get _isManager => _userRole == 'admin' || _userRole == 'manager';

  Future<void> _openNotifications() async {
    await context.push(AppRoutes.employeeNotifications);
    unawaited(_loadDashboardData());
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.expanded;
    final today = _TodayCard(
      loading: _isLoading && _todayAttendance == null,
      attendance: _todayAttendance,
      schedule: _workSchedule,
      onAction: () => widget.onTabChange(1),
    );
    final side = <Widget>[
      if (_isManager) ...[
        const SizedBox(height: AppSpace.lg),
        _AdminEntry(onTap: () => context.push(AppRoutes.adminDashboard)),
      ],
      const SectionHeader('الخدمات'),
      _QuickActions(
        actions: [
          _QuickAction(Icons.event_available_rounded, 'طلب إجازة', AppTone.accent, () => widget.onTabChange(2)),
          _QuickAction(Icons.account_balance_wallet_rounded, 'طلب سلفة', AppTone.warning, () => widget.onTabChange(3)),
          _QuickAction(Icons.receipt_long_rounded, 'كشف الراتب', AppTone.success, () => context.push(AppRoutes.employeePayslips)),
          _QuickAction(Icons.history_rounded, 'سجل الدوام', AppTone.brand, () => widget.onTabChange(1)),
          _QuickAction(Icons.groups_rounded, 'دليل الموظفين', AppTone.info, () => context.push(AppRoutes.employeeDirectory)),
          _QuickAction(Icons.notifications_rounded, 'الإشعارات', AppTone.neutral, _openNotifications),
        ],
      ),
    ];
    final announcements = <Widget>[
      SectionHeader(
        'التعاميم',
        actionLabel: _announcements.isNotEmpty ? 'عرض الكل' : null,
        onAction: _openNotifications,
      ),
      _Announcements(loading: _isLoading && _announcements.isEmpty, items: _announcements),
    ];

    return AppPage(
      showBack: false,
      onRefresh: _loadDashboardData,
      maxWidth: wide ? 1080 : AppBreakpoints.maxContent,
      padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.lg, AppSpace.page, AppSpace.x4),
      slivers: [
        SliverToBoxAdapter(
          child: _Header(
            name: _employeeName,
            subtitle: _departmentName,
            avatarUrl: _avatarUrl,
            unread: _unreadNotificationsCount,
            onNotifications: _openNotifications,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
        if (wide)
          SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(children: [today, ...side])),
                const SizedBox(width: AppSpace.xxl),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: announcements)),
              ],
            ),
          )
        else
          SliverList.list(children: [today, ...side, ...announcements]),
      ],
    );
  }
}

// =========================================================================
// أجزاء الشاشة
// =========================================================================

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.subtitle, required this.avatarUrl, required this.unread, required this.onNotifications});

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
enum _DayState { notStarted, working, done }

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.loading, required this.attendance, required this.schedule, required this.onAction});

  final bool loading;
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
        ? _DayState.done
        : checkIn != null
            ? _DayState.working
            : _DayState.notStarted;

    final now = DateTime.now();
    final worked = checkIn == null ? Duration.zero : (checkOut ?? now).difference(checkIn);
    final planned = _scheduledMinutes;

    final (badge, tone, bigLabel, bigValue, actionLabel, actionIcon, variant) = switch (state) {
      _DayState.notStarted => (
          'لم تسجّل بعد',
          AppTone.warning,
          'يبدأ دوامك',
          Fmt.timeOfDay(schedule?['check_in_time']?.toString()),
          'تسجيل الحضور',
          Icons.fingerprint_rounded,
          AppButtonVariant.primary,
        ),
      _DayState.working => (
          'في الدوام',
          AppTone.brand,
          'مدة العمل حتى الآن',
          _hm(worked),
          'تسجيل الانصراف',
          Icons.logout_rounded,
          AppButtonVariant.warning,
        ),
      _DayState.done => (
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
          if (state == _DayState.working && planned != null) ...[
            const SizedBox(height: AppSpace.md),
            AppProgressBar(value: worked.isNegative ? 0 : worked.inMinutes / planned),
          ],
          const SizedBox(height: AppSpace.lg),
          Wrap(
            spacing: AppSpace.lg,
            runSpacing: AppSpace.xs,
            children: [
              _TimeChip(icon: Icons.login_rounded, label: 'الحضور', value: checkIn == null ? '--:--' : Fmt.time(checkIn)),
              _TimeChip(icon: Icons.logout_rounded, label: 'الانصراف', value: checkOut == null ? '--:--' : Fmt.time(checkOut)),
              if (schedule != null)
                _TimeChip(
                  icon: Icons.schedule_rounded,
                  label: 'الدوام',
                  value: '${Fmt.timeOfDay(schedule!['check_in_time']?.toString())} - ${Fmt.timeOfDay(schedule!['check_out_time']?.toString())}',
                ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          AppButton(label: actionLabel, icon: actionIcon, variant: variant, size: AppButtonSize.large, expand: true, onPressed: onAction),
          if (state == _DayState.notStarted && schedule?['grace_period_minutes'] != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Center(child: Text('سماحية التأخير ${schedule!['grace_period_minutes']} دقيقة', style: AppText.caption)),
            ),
        ],
      ),
    );
  }

  static String _hm(Duration d) {
    if (d.isNegative) return '0 د';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '$m د';
    return m == 0 ? '$h س' : '$h س $m د';
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.icon, required this.label, required this.value});
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

class _AdminEntry extends StatelessWidget {
  const _AdminEntry({required this.onTap});
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

class _QuickAction {
  const _QuickAction(this.icon, this.title, this.tone, this.onTap);
  final IconData icon;
  final String title;
  final AppTone tone;
  final VoidCallback onTap;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.actions});
  final List<_QuickAction> actions;

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

class _Announcements extends StatelessWidget {
  const _Announcements({required this.loading, required this.items});
  final bool loading;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    if (loading) return const SkeletonList(count: 2, itemHeight: 88);
    if (items.isEmpty) {
      return const AppCard(
        child: EmptyView(title: 'لا توجد تعاميم جديدة', message: 'ستظهر هنا إعلانات الإدارة.', icon: Icons.campaign_rounded, compact: true),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: FadeSlideIn(index: i, child: _AnnouncementCard(items[i])),
          ),
      ],
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard(this.a);
  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final pinned = a['is_pinned'] == true;
    final body = (a['content'] ?? a['body'] ?? '').toString();
    return AppCard(
      tone: pinned ? AppTone.warning : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (pinned) ...[const Icon(Icons.push_pin_rounded, size: 16, color: AppColors.warning), const SizedBox(width: AppSpace.xs)],
              Expanded(child: Text((a['title'] ?? 'إعلان إداري').toString(), style: AppText.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: AppSpace.sm),
              Text(Fmt.relative(DateTime.tryParse(a['created_at']?.toString() ?? '')), style: AppText.caption),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(body, style: AppText.bodySm, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
