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

import '../../../core/models/models.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/ota_service.dart';
import '../../../core/services/schedule_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_log.dart';
import '../../../data/repositories/home_repository.dart';
import '../../shared/ui/ui.dart';
import '../announcements/announcement_widgets.dart';
import 'widgets/home_widgets.dart';

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
  List<AnnouncementModel> _announcements = [];
  List<OnLeavePerson> _onLeave = [];
  List<LatePerson> _lateToday = [];

  /// اليوم عطلة رسمية (من الإعدادات) — الكارد يگول "اليوم عطلة" بدل "لم تسجّل بعد"
  bool _isHolidayToday = false;
  Map<String, dynamic>? _todayAttendance;
  String _userRole = 'employee';
  int _unreadNotificationsCount = 0;
  dynamic _realtimeSubscription;
  dynamic _attendanceSubscription;
  Map<String, dynamic>? _workSchedule;
  final HomeRepository _repo = HomeRepository();

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
        appLog('OTA check non-fatal error: $e');
      }
    });
  }

  void _subscribeToNotifications() {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    _realtimeSubscription = _repo.subscribeToNewNotifications(user.id, (payload) async {
      if (!mounted) return;
      setState(() => _unreadNotificationsCount++);

      try {
        unawaited(SystemSound.play(SystemSoundType.alert));
        unawaited(HapticFeedback.mediumImpact());
      } catch (e) {
        appLog('خطأ في تشغيل صوت الإشعار: $e');
      }

      final data = payload.newRecord;
      // Show a REAL system notification with sound — works even if
      // the user is on another tab. FCM push handles this when the
      // app is in the background; this covers the in-app case.
      await NotificationService.showLocalNotification(
        title: (data['title'] ?? 'تنبيه جديد').toString(),
        body: (data['body'] ?? '').toString(),
      );
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
      final rec = await _repo.fetchTodayAttendance(user.id, todayStr);
      if (mounted) {
        setState(() {
          _todayAttendance = rec;
        });
      }
    } catch (e) {
      appLog('تعذر تحديث سجل الدوام: $e');
    }
  }

  /// يستمع لأي تغيير في جدول attendance لليوم الحالي ويحدث الكارد فوراً
  void _subscribeToAttendance() {
    final user = SupabaseService.currentUser;
    if (user == null) return;
    final todayStr = DateTime.now().toIso8601String().split('T')[0];

    _attendanceSubscription = _repo.subscribeToAttendance(user.id, (payload) {
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
    });
  }

  @override
  void dispose() {
    widget.refreshNotifier?.removeListener(_onRefreshRequested);
    if (_realtimeSubscription != null) {
      _repo.removeChannel(_realtimeSubscription as RealtimeChannel);
    }
    if (_attendanceSubscription != null) {
      _repo.removeChannel(_attendanceSubscription as RealtimeChannel);
    }
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final empData = await _repo.fetchProfile(user.id);

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
        // التعاميم السارية الآن لهذا الموظف فقط (مدة + جمهور مستهدف)
        _repo.fetchActiveAnnouncements(),
        _repo.fetchTodayAttendance(user.id, todayStr),
        _repo.fetchUnreadNotificationIds(user.id),
      ]);

      final schedData = results[0];
      final announcementsData = results[1] as List<dynamic>;
      final attendanceData = results[2];
      final unreadRes = results[3] as List<dynamic>;

      unawaited(_loadOnLeave());
      unawaited(_loadHolidayToday(todayStr));
      // تذكيرات البصمة المحلية (للآيفون) حسب الجدول والإجازات وبصمة اليوم
      unawaited(NotificationService.refreshLocalAttendanceReminders());

      setState(() {
        _workSchedule = schedData != null ? schedData as Map<String, dynamic> : null;
        _announcements = rowsStrict(announcementsData, AnnouncementModel.fromMap);
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
      appLog('خطأ في تحميل بيانات لوحة الموظف: $e');
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

  Future<void> _loadHolidayToday(String todayStr) async {
    try {
      final isHoliday = await _repo.isOfficialHoliday(todayStr);
      if (mounted) setState(() => _isHolidayToday = isHoliday);
    } catch (e) {
      appLog('تعذّر فحص العطلة الرسمية: $e');
    }
  }

  // المجازون الآن (منفصل: فشله لا يوقف باقي الرئيسية)
  Future<void> _loadOnLeave() async {
    try {
      final r = await _repo.fetchOnLeaveAndLateToday();
      if (mounted) {
        setState(() {
          if (r[0] is List) _onLeave = rowsStrict(r[0], OnLeavePerson.fromMap);
          if (r[1] is List) _lateToday = rowsStrict(r[1], LatePerson.fromMap);
        });
      }
    } catch (e) {
      appLog('Error loading on-leave list: $e');
    }
  }

  Future<void> _openAnnouncements() async {
    await context.push(AppRoutes.employeeAnnouncements);
    unawaited(_loadDashboardData());
  }

  Future<void> _openNotifications() async {
    await context.push(AppRoutes.employeeNotifications);
    unawaited(_loadDashboardData());
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.expanded;
    final today = HomeTodayCard(
      loading: _isLoading && _todayAttendance == null,
      attendance: _todayAttendance,
      schedule: _workSchedule,
      // مجاز الآن = ما نعرض "متأخر"
      onLeave: _onLeave.any((p) => p.employeeId == SupabaseService.currentUser?.id),
      isHoliday: _isHolidayToday,
      onAction: () => widget.onTabChange(1),
    );
    final side = <Widget>[
      if (_isManager) ...[
        const SizedBox(height: AppSpace.lg),
        HomeAdminEntry(onTap: () => context.push(AppRoutes.adminDashboard)),
      ],
      const SectionHeader('الخدمات'),
      HomeQuickActions(
        actions: [
          HomeQuickAction(Icons.event_available_rounded, 'طلب إجازة', AppTone.accent, () => widget.onTabChange(2)),
          HomeQuickAction(Icons.account_balance_wallet_rounded, 'طلب سلفة', AppTone.warning, () => widget.onTabChange(3)),
          HomeQuickAction(Icons.receipt_long_rounded, 'كشف الراتب', AppTone.success, () => context.push(AppRoutes.employeePayslips)),
          HomeQuickAction(Icons.history_rounded, 'سجل الدوام', AppTone.brand, () => widget.onTabChange(1)),
          HomeQuickAction(Icons.groups_rounded, 'دليل الموظفين', AppTone.info, () => context.push(AppRoutes.employeeDirectory)),
          HomeQuickAction(Icons.notifications_rounded, 'الإشعارات', AppTone.neutral, _openNotifications),
        ],
      ),
    ];
    final announcements = <Widget>[
      SectionHeader(
        'التعاميم',
        actionLabel: 'عرض الكل',
        onAction: _openAnnouncements,
      ),
      HomeAnnouncements(loading: _isLoading && _announcements.isEmpty, items: _announcements, onOpen: _openAnnouncements),
      if (_onLeave.isNotEmpty) ...[
        SectionHeader(
          'المجازون اليوم',
          trailing: StatusBadge('${_onLeave.length}', tone: AppTone.accent),
          actionLabel: 'عرض الكل',
          onAction: _openAnnouncements,
        ),
        OnLeaveStrip(people: _onLeave),
      ],
      if (_lateToday.isNotEmpty) ...[
        SectionHeader(
          'المتأخرون اليوم',
          trailing: StatusBadge('${_lateToday.length}', tone: AppTone.warning),
          actionLabel: 'عرض الكل',
          onAction: _openAnnouncements,
        ),
        LateStrip(people: _lateToday),
      ],
    ];

    return AppPage(
      showBack: false,
      onRefresh: _loadDashboardData,
      maxWidth: wide ? 1080 : AppBreakpoints.maxContent,
      padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.lg, AppSpace.page, AppSpace.x4),
      slivers: [
        SliverToBoxAdapter(
          child: HomeHeader(
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
