// =========================================================================
// نظام HR Pro v6.0 - الشاشة الرئيسية للموظف (Employee Home)
// إعادة تصميم عصرية: ألوان الثيم بالكامل (دعم Light/Dark سليم)،
// hierarchy واضحة، skeleton loading، انيميشن أنعم، ودعم كل الأحجام.
// كل منطق تحميل البيانات والاشتراك الفوري والتتبع محفوظ كما هو.
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/routes/app_router.dart';
import '../../core/services/location_service.dart';
import '../../core/services/ota_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  final Function(int) onTabChange;
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
              SystemSound.play(SystemSoundType.alert);
              HapticFeedback.mediumImpact();
            } catch (e) {
              debugPrint('خطأ في تشغيل صوت الإشعار: $e');
            }

            final data = payload.newRecord;
            // Show a REAL system notification with sound — works even if
            // the user is on another tab. FCM push handles this when the
            // app is in the background; this covers the in-app case.
            await NotificationService.showLocalNotification(
              title: (data['title'] ?? 'تنبيه جديد 🔔').toString(),
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
          _todayAttendance = rec != null ? rec as Map<String, dynamic> : null;
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
            if (rec != null && rec['work_date'] == todayStr) {
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
      SupabaseService.client.removeChannel(_realtimeSubscription);
    }
    if (_attendanceSubscription != null) {
      SupabaseService.client.removeChannel(_attendanceSubscription);
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
          _employeeName = empData['full_name'] ?? _employeeName;
          final String deptName = empData['department_name'] ?? 'القسم العام';
          final String branchName = empData['branch_name'] ?? 'الفرع العام';
          _departmentName = '$deptName • $branchName';
          _avatarUrl = empData['avatar_url'] ?? '';
          _userRole = empData['role'] ?? 'employee';
        });
      }

      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      final List<String> orFilters = ['employee_id.eq.${user.id}'];
      if (empData != null) {
        if (empData['department_id'] != null) {
          orFilters.add('department_id.eq.${empData['department_id']}');
        }
        if (empData['branch_id'] != null) {
          orFilters.add('branch_id.eq.${empData['branch_id']}');
        }
      }
      final scheduleQuery = SupabaseService.client
          .from('work_schedules')
          .select()
          .or(orFilters.join(','))
          .limit(1)
          .maybeSingle();

      final results = await Future.wait([
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

      // جدولة تذكيرات الحضور والانصراف تلقائياً بناءً على جدول العمل
      NotificationService.scheduleAttendanceReminders(schedule: _workSchedule);

      if (_todayAttendance != null &&
          _todayAttendance!['check_in_time'] != null &&
          _todayAttendance!['check_out_time'] == null) {
        LocationService.startTracking(employeeId: user.id);
        NotificationService.cancelTodayCheckInReminder();
      } else if (_todayAttendance != null && _todayAttendance!['check_out_time'] != null) {
        LocationService.stopTracking();
        NotificationService.cancelTodayCheckInReminder();
        NotificationService.cancelTodayCheckOutReminder();
      } else {
        LocationService.stopTracking();
      }
    } catch (e) {
      debugPrint('خطأ في تحميل بيانات لوحة الموظف: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر تحديث البيانات، يرجى التحقق من اتصال الإنترنت.',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppTheme.dangerRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================================================================
  // Build
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final t = theme.textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: cs.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(isDark, cs, t),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space4,
                AppTheme.space2,
                AppTheme.space4,
                AppTheme.space10,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_workSchedule != null) ...[
                    _buildScheduleCard(isDark, cs, t),
                    const SizedBox(height: AppTheme.space4),
                  ],
                  _buildAttendanceCard(isDark, cs, t),
                  const SizedBox(height: AppTheme.space6),
                  if (_userRole == 'admin' || _userRole == 'manager') ...[
                    _buildAdminCard(isDark, cs, t),
                    const SizedBox(height: AppTheme.space6),
                  ],
                  _buildSectionHeader('الخدمات السريعة', Icons.grid_view_rounded, cs, t),
                  const SizedBox(height: AppTheme.space3),
                  _buildQuickActionsGrid(context),
                  const SizedBox(height: AppTheme.space6),
                  _buildAnnouncementsHeader(context, cs, t),
                  const SizedBox(height: AppTheme.space3),
                  _buildAnnouncementsSection(isDark, cs, t),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // App Bar
  // ==========================================================================
  Widget _buildAppBar(bool isDark, ColorScheme cs, TextTheme t) {
    return SliverAppBar(
      expandedHeight: 140,
      floating: false,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      actions: [
        _NotificationButton(
          count: _unreadNotificationsCount,
          onTap: () async {
            await context.push(AppRoutes.employeeNotifications);
            _loadDashboardData();
          },
        ),
        const SizedBox(width: AppTheme.space2),
      ],
      title: Text(
        'HR Pro',
        style: t.titleLarge?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
      ),
      centerTitle: false,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.space4, 60, AppTheme.space4, AppTheme.space3,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.primaryGradient,
                  ),
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: cs.surface,
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: cs.primaryContainer,
                      backgroundImage: _avatarUrl.isNotEmpty
                          ? ResizeImage.resizeIfNeeded(120, 120, NetworkImage(_avatarUrl))
                          : null,
                      child: _avatarUrl.isEmpty
                          ? Icon(Icons.person, color: cs.onPrimaryContainer, size: 24)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _greeting(),
                        style: t.bodySmall?.copyWith(
                          color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
                        ),
                      ),
                      Text(
                        _employeeName,
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _departmentName,
                        style: t.bodySmall?.copyWith(
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // Cards
  // ==========================================================================
  Widget _buildScheduleCard(bool isDark, ColorScheme cs, TextTheme t) {
    final checkIn = _formatTimeStr(_workSchedule!['check_in_time']?.toString());
    final checkOut = _formatTimeStr(_workSchedule!['check_out_time']?.toString());
    final grace = _workSchedule!['grace_period_minutes'] ?? 15;

    return _SectionCard(
      accent: AppTheme.accentIndigo,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.space3),
            decoration: BoxDecoration(
              color: AppTheme.accentIndigo.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: const Icon(Icons.access_time_filled_rounded, color: AppTheme.accentIndigo, size: 26),
          ),
          const SizedBox(width: AppTheme.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('أوقات الدوام المعتمدة', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  'من $checkIn إلى $checkOut  •  سماحية $grace د',
                  style: t.bodySmall?.copyWith(
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(bool isDark, ColorScheme cs, TextTheme t) {
    final hasCheckIn = _todayAttendance != null && _todayAttendance!['check_in_time'] != null;
    final hasCheckOut = _todayAttendance != null && _todayAttendance!['check_out_time'] != null;

    final (statusText, statusColor, statusIcon) = hasCheckOut
        ? ('مكتمل الدوام اليومي', AppTheme.successGreen, Icons.check_circle_rounded)
        : hasCheckIn
            ? ('أنت في فترة الدوام', AppTheme.warningOrange, Icons.watch_later_rounded)
            : ('لم تسجل الحضور بعد', AppTheme.dangerRed, Icons.error_rounded);

    return _SectionCard(
      accent: statusColor,
      padding: const EdgeInsets.all(AppTheme.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('بصمة الدوام اليومية', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.space3, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  _getFormattedTodayDate(),
                  style: t.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.space3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Icon(statusIcon, color: statusColor, size: 28),
              ),
              const SizedBox(width: AppTheme.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(statusText, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      hasCheckIn
                          ? 'تسجيل الحضور: ${_formatTime(_todayAttendance!['check_in_time'])}'
                          : 'يرجى تسجيل حضورك عند الوصول للفرع.',
                      style: t.bodySmall?.copyWith(
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space5),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => widget.onTabChange(1),
              icon: Icon(hasCheckIn ? Icons.logout_rounded : Icons.login_rounded, size: 20),
              label: Text(
                hasCheckIn ? (hasCheckOut ? 'عرض السجل اليومي' : 'تسجيل الانصراف') : 'ابدأ الدوام',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800, fontSize: 15),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: statusColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 52),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminCard(bool isDark, ColorScheme cs, TextTheme t) {
    return _SectionCard(
      accent: AppTheme.cyberPurple,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          onTap: () => context.push(AppRoutes.adminDashboard),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space5),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppTheme.space3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.cyberPurple.withValues(alpha: 0.20), AppTheme.cyberPurple.withValues(alpha: 0.08)],
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.cyberPurple, size: 32),
                ),
                const SizedBox(width: AppTheme.space4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'بوابة الإدارة والمدراء',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.cyberPurple,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'الإجازات، السلف، الأجهزة المقفلة، والتتبع الحي',
                        style: t.bodySmall?.copyWith(
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.cyberPurple, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // Quick actions
  // ==========================================================================
  Widget _buildQuickActionsGrid(BuildContext context) {
    final actions = <_QuickAction>[
      _QuickAction(Icons.calendar_today_rounded, 'تقديم إجازة', AppTheme.accentIndigo, () => widget.onTabChange(2)),
      _QuickAction(Icons.monetization_on_rounded, 'طلب سلفة', AppTheme.warningOrange, () => widget.onTabChange(3)),
      _QuickAction(Icons.receipt_long_rounded, 'كشف الراتب', AppTheme.successGreen, () => context.push(AppRoutes.employeePayslips)),
      _QuickAction(Icons.fingerprint_rounded, 'بصمة الدوام', AppTheme.primaryTeal, () => widget.onTabChange(1)),
      _QuickAction(Icons.people_alt_rounded, 'دليل الموظفين', AppTheme.cyberPurple, () => context.push(AppRoutes.employeeDirectory)),
      _QuickAction(Icons.settings_rounded, 'الإعدادات', AppTheme.neonCyan, () => widget.onTabChange(4)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 600 ? 4 : 3;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppTheme.space3,
          mainAxisSpacing: AppTheme.space3,
          childAspectRatio: 1.0,
          children: actions.map((a) => _QuickActionTile(action: a)).toList(),
        );
      },
    );
  }

  // ==========================================================================
  // Announcements
  // ==========================================================================
  Widget _buildAnnouncementsHeader(BuildContext context, ColorScheme cs, TextTheme t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSectionHeader('التعاميم والإعلانات', Icons.campaign_rounded, cs, t),
        if (_announcements.isNotEmpty)
          TextButton(
            onPressed: () => context.push(AppRoutes.employeeNotifications),
            child: Text('عرض الكل', style: t.bodyMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }

  Widget _buildAnnouncementsSection(bool isDark, ColorScheme cs, TextTheme t) {
    if (_isLoading) {
      return Column(
        children: List.generate(2, (_) => Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.space3),
          child: _SkeletonBox(height: 84, isDark: isDark),
        )),
      );
    }

    if (_announcements.isEmpty) {
      return _SectionCard(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.space6),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.notifications_off_outlined, color: cs.outline, size: 40),
              const SizedBox(height: AppTheme.space2),
              Text(
                'لا توجد تعاميم جديدة حالياً',
                style: t.bodyMedium?.copyWith(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _announcements.asMap().entries.map((entry) {
        final a = entry.value;
        final isPinned = a['is_pinned'] ?? false;
        final accent = isPinned ? AppTheme.warningOrange : cs.primary;

        return Padding(
          padding: EdgeInsets.only(bottom: entry.key < _announcements.length - 1 ? AppTheme.space3 : 0),
          child: _SectionCard(
            accent: accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (isPinned) ...[
                            Icon(Icons.push_pin_rounded, color: accent, size: 16),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              a['title'] ?? 'إعلان إداري',
                              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formatAnnounceDate(a['created_at']),
                      style: t.bodySmall?.copyWith(color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  a['content'] ?? '',
                  style: t.bodyMedium?.copyWith(
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================
  Widget _buildSectionHeader(String title, IconData icon, ColorScheme cs, TextTheme t) {
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'صباح الخير،';
    if (h < 17) return 'أهلاً،';
    return 'مساء الخير،';
  }

  String _getFormattedTodayDate() {
    final now = DateTime.now();
    const months = [
      'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
      'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
    ];
    return '${now.day} ${months[now.month - 1]}';
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '--:--';
    try {
      final dt = DateTime.parse(timeStr).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $amPm';
    } catch (_) {
      return '--:--';
    }
  }

  String _formatAnnounceDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.year}/${date.month}/${date.day}';
    } catch (_) {
      return '';
    }
  }

  String _formatTimeStr(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '--:--';
    try {
      final parts = timeStr.split(':');
      if (parts.length < 2) return timeStr;
      int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);
      final String period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      final String minuteStr = minute.toString().padLeft(2, '0');
      return '$hour:$minuteStr $period';
    } catch (_) {
      return timeStr;
    }
  }
}

// =========================================================================
// Reusable widgets — private to this file
// =========================================================================

class _SectionCard extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final EdgeInsetsGeometry padding;

  const _SectionCard({
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.all(AppTheme.space4),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: accent?.withValues(alpha: 0.18) ??
              (isDark ? AppTheme.darkBorder.withValues(alpha: 0.5) : AppTheme.lightBorder),
          width: 1,
        ),
        boxShadow: AppTheme.shadowSm(isDark),
      ),
      child: child,
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.title, this.color, this.onTap);
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction action;
  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final t = theme.textTheme;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          action.onTap();
        },
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.space3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder.withValues(alpha: 0.5) : AppTheme.lightBorder,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.space3),
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Icon(action.icon, color: action.color, size: 22),
              ),
              const SizedBox(height: AppTheme.space2),
              Text(
                action.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _NotificationButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(Icons.notifications_none_rounded, color: cs.onSurface),
          tooltip: 'الإشعارات',
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.dangerRed,
                shape: BoxShape.circle,
                border: Border.all(color: cs.surface, width: 2),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double height;
  final bool isDark;
  const _SkeletonBox({required this.height, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceVariant : AppTheme.lightSurfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
    );
  }
}
