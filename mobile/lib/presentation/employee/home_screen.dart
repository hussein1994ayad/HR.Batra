// =========================================================================
// نظام HR Pro v6.0 - الشاشة الرئيسية للموظف (Employee Home Screen)
// =========================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/routes/app_router.dart';
import '../../core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/services/location_service.dart';
import '../../core/services/ota_service.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/glass_container.dart';

class HomeScreen extends StatefulWidget {
  final Function(int) onTabChange;

  const HomeScreen({super.key, required this.onTabChange});

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
  final AudioPlayer _audioPlayer = AudioPlayer();
  Map<String, dynamic>? _workSchedule;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _subscribeToNotifications();
    
    // تشغيل تتبع الموقع التلقائي للموظف
    LocationService.startTracking();
    
    // فحص التحديثات الهوائية (OTA) فور فتح التطبيق
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final updateInfo = await OtaService.checkVersion();
      if (mounted && (updateInfo['status'] == OtaStatus.mandatoryUpdate || 
          updateInfo['status'] == OtaStatus.optionalUpdate)) {
        OtaService.showUpdatePrompt(context, updateInfo);
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
            
            // Increment unread count
            setState(() {
              _unreadNotificationsCount++;
            });

            // Play alert sound!
            try {
              SystemSound.play(SystemSoundType.alert);
            } catch (e) {
              debugPrint('خطأ في تشغيل صوت الإشعار: $e');
            }

            // Show beautiful overlay banner notification and trigger system tray alert!
            final data = payload.newRecord;
            // Show standard snackbar for foreground notifications
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded, color: AppTheme.brandLight),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${data['title'] ?? 'تنبيه جديد'}\n${data['body'] ?? ''}',
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          },
        )
        .subscribe((status, [error]) {
          debugPrint('=== اشتراك الإشعارات الفورية للعميل: $status ===');
          if (error != null) {
            debugPrint('=== خطأ في اشتراك الإشعارات الفورية: $error ===');
          }
        });
  }

  @override
  void dispose() {
    if (_realtimeSubscription != null) {
      SupabaseService.client.removeChannel(_realtimeSubscription);
    }
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    final user = SupabaseService.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. جلب بيانات الموظف والقسم
      final empData = await SupabaseService.client
          .from('v_employee_directory')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;

      if (empData != null) {
        setState(() {
          _employeeName = empData['full_name'] ?? _employeeName;
          final String deptName = empData['department_name'] ?? 'القسم العام';
          final String branchName = empData['branch_name'] ?? 'الفرع العام';
          _departmentName = '$deptName - $branchName';
          _avatarUrl = empData['avatar_url'] ?? '';
          _userRole = empData['role'] ?? 'employee';
        });
      }

      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      // إعداد استعلام جدول العمل بناءً على توفر بيانات الموظف
      final scheduleQuery = empData != null
          ? SupabaseService.client
              .from('work_schedules')
              .select()
              .or('employee_id.eq.${user.id},department_id.eq.${empData['department_id']},branch_id.eq.${empData['branch_id']}')
              .limit(1)
              .maybeSingle()
          : SupabaseService.client
              .from('work_schedules')
              .select()
              .eq('employee_id', user.id)
              .limit(1)
              .maybeSingle();

      // جلب بقية البيانات بالتوازي لتسريع العملية بشكل كبير
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
      if (!mounted) return;

      setState(() {
        if (schedData != null) {
          _workSchedule = schedData as Map<String, dynamic>;
        }
        _announcements = List<Map<String, dynamic>>.from(announcementsData);
        if (attendanceData != null) {
          _todayAttendance = attendanceData as Map<String, dynamic>;
        }
        _unreadNotificationsCount = unreadRes.length;
      });

    } catch (e) {
      debugPrint('خطأ في تحميل بيانات لوحة الموظف: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        edgeOffset: 8,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: _buildHeader()),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              sliver: SliverList.list(
                children: [
                  _buildAttendanceHeroCard(),
                  if (_userRole == 'admin' || _userRole == 'manager') ...[
                    const SizedBox(height: 14),
                    _buildAdminDashboardCard(),
                  ],
                  const SizedBox(height: 26),
                  const SectionHeader(
                    title: 'الخدمات السريعة',
                    icon: Icons.bolt_rounded,
                  ),
                  _buildQuickActionsGrid(context),
                  const SizedBox(height: 26),
                  SectionHeader(
                    title: 'الإعلانات والتعاميم',
                    icon: Icons.campaign_rounded,
                    actionLabel: _announcements.isNotEmpty ? 'عرض الكل' : null,
                    onAction: () => context.push(AppRoutes.employeeNotifications),
                  ),
                  _buildAnnouncementsSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير';
    if (hour < 18) return 'مساء الخير';
    return 'مساء النور';
  }

  // الترويسة: صورة الموظف، التحية، والإشعارات
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppTheme.primaryGradient,
          ),
          child: CircleAvatar(
            radius: 24,
            backgroundColor: AppTheme.darkSurfaceHigh,
            foregroundImage: _avatarUrl.isNotEmpty ? NetworkImage(_avatarUrl) : null,
            child: Text(
              _employeeName.trim().isNotEmpty ? _employeeName.trim()[0] : '؟',
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: AppTheme.brandLight,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greeting()} 👋',
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  color: AppTheme.darkTextSecondary,
                ),
              ),
              _isLoading && _employeeName == 'موظف متميز'
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: SkeletonBox(width: 140, height: 18),
                    )
                  : Text(
                      _employeeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.darkTextPrimary,
                        height: 1.3,
                      ),
                    ),
              Text(
                _departmentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 12,
                  color: AppTheme.darkTextMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'الإشعارات',
          onPressed: () async {
            await context.push(AppRoutes.employeeNotifications);
            _loadDashboardData();
          },
          icon: Badge(
            isLabelVisible: _unreadNotificationsCount > 0,
            label: Text(
              _unreadNotificationsCount > 99 ? '99+' : '$_unreadNotificationsCount',
            ),
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
      ],
    );
  }

  // بطاقة الدوام الرئيسية: الحالة، الوقت، وأوقات الفرع
  Widget _buildAttendanceHeroCard() {
    final hasCheckIn = _todayAttendance != null && _todayAttendance!['check_in_time'] != null;
    final hasCheckOut = _todayAttendance != null && _todayAttendance!['check_out_time'] != null;

    final String status;
    final IconData statusIcon;
    if (hasCheckOut) {
      status = 'اكتمل دوامك لليوم';
      statusIcon = Icons.task_alt_rounded;
    } else if (hasCheckIn) {
      status = 'أنت في الدوام الآن';
      statusIcon = Icons.timelapse_rounded;
    } else {
      status = 'لم تسجّل حضورك بعد';
      statusIcon = Icons.schedule_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brand.withValues(alpha: 0.3),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // زخرفة خفيفة
          PositionedDirectional(
            top: -40,
            end: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 13, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            _getFormattedTodayDate(),
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(statusIcon, color: Colors.white, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        status,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hasCheckIn
                      ? 'الحضور: ${_formatTime(_todayAttendance!['check_in_time'])}'
                          '${hasCheckOut ? '   •   الانصراف: ${_formatTime(_todayAttendance!['check_out_time'])}' : ''}'
                      : 'سجّل حضورك فور وصولك إلى الفرع.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
                if (_workSchedule != null) ...[
                  const SizedBox(height: 16),
                  _buildScheduleStrip(),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () => widget.onTabChange(1),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.brandDeep,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                    ),
                    icon: Icon(
                      hasCheckOut
                          ? Icons.history_rounded
                          : (hasCheckIn ? Icons.logout_rounded : Icons.fingerprint_rounded),
                    ),
                    label: Text(
                      hasCheckOut
                          ? 'عرض سجل الدوام'
                          : (hasCheckIn ? 'تسجيل الانصراف' : 'تسجيل الحضور'),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // شريط أوقات الدوام المعتمدة للفرع
  Widget _buildScheduleStrip() {
    final checkIn = _formatTimeStr(_workSchedule!['check_in_time']?.toString());
    final checkOut = _formatTimeStr(_workSchedule!['check_out_time']?.toString());
    final grace = _workSchedule!['grace_period_minutes'] ?? 15;

    Widget cell(String label, String value) => Expanded(
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );

    Widget divider() => Container(
          width: 1,
          height: 28,
          color: Colors.white.withValues(alpha: 0.2),
        );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Row(
        children: [
          cell('بداية الدوام', checkIn),
          divider(),
          cell('نهاية الدوام', checkOut),
          divider(),
          cell('فترة السماح', '$grace د'),
        ],
      ),
    );
  }

  // شبكة الخدمات السريعة (3 أعمدة على الهاتف و6 على الشاشات العريضة)
  Widget _buildQuickActionsGrid(BuildContext context) {
    final actions = [
      (icon: Icons.event_note_rounded, title: 'طلب إجازة', color: AppTheme.sky, onTap: () => widget.onTabChange(2)),
      (icon: Icons.account_balance_wallet_rounded, title: 'طلب سلفة', color: AppTheme.pink, onTap: () => widget.onTabChange(3)),
      (icon: Icons.receipt_long_rounded, title: 'كشف الراتب', color: AppTheme.violetLight, onTap: () => context.push(AppRoutes.employeePayslips)),
      (icon: Icons.fingerprint_rounded, title: 'بصمة الدوام', color: AppTheme.warningLight, onTap: () => widget.onTabChange(1)),
      (icon: Icons.groups_rounded, title: 'دليل الموظفين', color: AppTheme.successLight, onTap: () => context.push(AppRoutes.employeeDirectory)),
      (icon: Icons.tune_rounded, title: 'الإعدادات', color: AppTheme.brandLight, onTap: () => widget.onTabChange(4)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 6 : 3;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        return GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 96 + 18 * textScale,
          ),
          itemBuilder: (context, index) {
            final a = actions[index];
            return _buildActionCard(
              icon: a.icon,
              title: a.title,
              color: a.color,
              onTap: a.onTap,
            );
          },
        );
      },
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      borderRadius: AppTheme.radiusLg,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppTheme.fontFamily,
                    color: AppTheme.darkTextPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // قسم الإعلانات والتعاميم
  Widget _buildAnnouncementsSection() {
    if (_isLoading && _announcements.isEmpty) {
      return Column(
        children: List.generate(
          2,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: SkeletonBox(height: 84, radius: AppTheme.radiusLg),
          ),
        ),
      );
    }

    if (_announcements.isEmpty) {
      return const GlassContainer(
        width: double.infinity,
        child: EmptyState(
          icon: Icons.campaign_outlined,
          title: 'لا توجد إعلانات جديدة',
          message: 'ستظهر هنا تعاميم الإدارة فور نشرها.',
        ),
      );
    }

    return Column(
      children: [
        for (final announcement in _announcements)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildAnnouncementCard(announcement),
          ),
      ],
    );
  }

  Widget _buildAnnouncementCard(Map<String, dynamic> announcement) {
    final isPinned = announcement['is_pinned'] == true;
    final accent = isPinned ? AppTheme.warningLight : AppTheme.brandLight;

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      opacity: isPinned ? 0.12 : 0.05,
      borderColor: isPinned ? AppTheme.warningOrange.withValues(alpha: 0.35) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            ),
            child: Icon(
              isPinned ? Icons.push_pin_rounded : Icons.campaign_rounded,
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        announcement['title'] ?? 'إعلان إداري',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          fontFamily: AppTheme.fontFamily,
                          color: AppTheme.darkTextPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatAnnounceDate(announcement['created_at']),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.darkTextMuted,
                        fontFamily: AppTheme.fontFamily,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  announcement['content'] ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.darkTextSecondary,
                    fontFamily: AppTheme.fontFamily,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // دوال وتنسيقات برمجية مساعدة
  String _getFormattedTodayDate() {
    final now = DateTime.now();
    final months = [
      'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
      'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'
    ];
    return '${now.day} ${months[now.month - 1]}، ${now.year}';
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null) return '--:--';
    try {
      final dateTime = DateTime.parse(timeStr).toLocal();
      final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
      final amPm = dateTime.hour >= 12 ? 'PM' : 'AM';
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute $amPm';
    } catch (e) {
      return '--:--';
    }
  }

  String _formatAnnounceDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return '${date.year}/${date.month}/${date.day}';
    } catch (e) {
      return '';
    }
  }

  Widget _buildAdminDashboardCard() {
    return GlassContainer(
      padding: EdgeInsets.zero,
      opacity: 0.12,
      borderColor: AppTheme.violetLight.withValues(alpha: 0.3),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => context.push(AppRoutes.adminDashboard),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppTheme.accentGradient,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'بوابة الإدارة',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          fontFamily: AppTheme.fontFamily,
                          color: AppTheme.darkTextPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'الإجازات، السلف، الأجهزة، ومراقبة الحضور والـ GPS',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.darkTextSecondary,
                          fontFamily: AppTheme.fontFamily,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_left_rounded,
                  color: AppTheme.darkTextSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    } catch (e) {
      return timeStr;
    }
  }
}
