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
                  content: Text(
                    '${data['title'] ?? 'تنبيه جديد 🔔'}\n${data['body'] ?? ''}',
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                  backgroundColor: AppTheme.successGreen,
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
    if (user == null) return;

    try {
      // 1. جلب بيانات الموظف والقسم
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        color: AppTheme.neonCyan,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. شريط التطبيق العلوي الإبداعي (Premium Custom SliverAppBar)
            SliverAppBar(
              expandedHeight: 120.0,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_active_outlined, color: AppTheme.neonCyan),
                      onPressed: () async {
                        await context.push(AppRoutes.employeeNotifications);
                        _loadDashboardData();
                      },
                    ),
                    if (_unreadNotificationsCount > 0)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppTheme.dangerRed,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '$_unreadNotificationsCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              title: const Text(
                'HR Pro v6.0',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: AppTheme.neonCyan,
                  shadows: [
                    Shadow(
                      color: AppTheme.neonCyan,
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
              centerTitle: false,
              flexibleSpace: FlexibleSpaceBar(
                background: Padding(
                  padding: const EdgeInsets.only(top: 80.0, right: 16.0, left: 16.0),
                  child: Row(
                    children: [
                      // الصورة الشخصية للموظف مع تذهيب
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.neonCyan, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonCyan.withOpacity(0.3),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: AppTheme.neonCyan.withAlpha(30),
                          backgroundImage: _avatarUrl.isNotEmpty ? NetworkImage(_avatarUrl) : null,
                          child: _avatarUrl.isEmpty
                              ? const Icon(Icons.person, color: AppTheme.neonCyan)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'أهلاً بك، $_employeeName',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          Text(
                            _departmentName,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2. محتوى الصفحة الرئيسي
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_workSchedule != null) _buildWorkScheduleCard(isDark),
                    if (_workSchedule != null) const SizedBox(height: 16),
                    // بطاقة حالة الحضور والانصراف اليومية
                    _buildAttendanceStatusCard(isDark),
                    const SizedBox(height: 24),

                    if (_userRole == 'admin' || _userRole == 'manager') ...[
                      _buildAdminDashboardCard(isDark),
                      const SizedBox(height: 24),
                    ],

                    // عنوان شبكة الخدمات السريعة
                    const Text(
                      'الخدمات السريعة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // شبكة الخدمات 2x2
                    _buildQuickActionsGrid(context),
                    const SizedBox(height: 28),

                    // إعلانات وتعاميم الإدارة
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'تعاميم لوحة الإعلانات 📢',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            color: Colors.white,
                          ),
                        ),
                        if (_announcements.isNotEmpty)
                          TextButton(
                            onPressed: () => context.push(AppRoutes.employeeNotifications),
                            child: const Text('عرض الكل', style: TextStyle(color: AppTheme.neonCyan, fontSize: 12, fontFamily: 'Cairo')),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildAnnouncementsSection(isDark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // بطاقة أوقات العمل للفرع
  Widget _buildWorkScheduleCard(bool isDark) {
    if (_workSchedule == null) return const SizedBox.shrink();
    
    final checkIn = _formatTimeStr(_workSchedule!['check_in_time']?.toString());
    final checkOut = _formatTimeStr(_workSchedule!['check_out_time']?.toString());
    final grace = _workSchedule!['grace_period_minutes'] ?? 15;

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      opacity: 0.1,
      borderColor: AppTheme.neonPink.withOpacity(0.3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.neonPink.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.access_time_filled_rounded, color: AppTheme.neonPink, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'أوقات الدوام المعتمدة لفرعك',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'الدخول: $checkIn  |  الخروج: $checkOut\nفترة السماح (تأخير): $grace دقيقة',
                  style: const TextStyle(
                    color: AppTheme.lightTextSecondary,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // بطاقة الحضور والانصراف اليومية
  Widget _buildAttendanceStatusCard(bool isDark) {
    final hasCheckIn = _todayAttendance != null && _todayAttendance!['check_in_time'] != null;
    final hasCheckOut = _todayAttendance != null && _todayAttendance!['check_out_time'] != null;

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: 20,
      opacity: 0.12,
      borderColor: AppTheme.neonCyan.withOpacity(0.3),
      boxShadow: [
        BoxShadow(
          color: AppTheme.neonCyan.withOpacity(0.08),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'بصمة الدوام اليومية',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  fontFamily: 'Cairo',
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.neonCyan.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.neonCyan.withOpacity(0.3)),
                ),
                child: Text(
                  _getFormattedTodayDate(),
                  style: const TextStyle(color: AppTheme.neonCyan, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasCheckOut 
                          ? 'مكتمل الدوام اليومي 🟢' 
                          : (hasCheckIn ? 'أنت في فترة الدوام حالياً 🟡' : 'لم تسجل الحضور اليوم 🔴'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasCheckIn 
                          ? 'تسجيل الحضور: ${_formatTime(_todayAttendance!['check_in_time'])}'
                          : 'يرجى تسجيل حضورك فور الوصول للفرع.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.neonCyan.withOpacity(0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => widget.onTabChange(1), // الانتقال لتبويب الحضور
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Ink(
                    decoration: const BoxDecoration(
                      gradient: AppTheme.cyberGradient,
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      alignment: Alignment.center,
                      child: Text(
                        hasCheckIn ? 'تسجيل الانصراف' : 'ابدأ الدوام',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo', color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // شبكة الخدمات السريعة 3x2
  Widget _buildQuickActionsGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        _buildActionCard(
          icon: Icons.calendar_today_rounded,
          title: 'تقديم إجازة',
          color: AppTheme.neonCyan,
          onTap: () => widget.onTabChange(2),
        ),
        _buildActionCard(
          icon: Icons.monetization_on_rounded,
          title: 'طلب سلفة',
          color: AppTheme.neonPink,
          onTap: () => widget.onTabChange(3),
        ),
        _buildActionCard(
          icon: Icons.receipt_long_rounded,
          title: 'كشف الراتب',
          color: AppTheme.cyberPurple,
          onTap: () => context.push(AppRoutes.employeePayslips),
        ),
        _buildActionCard(
          icon: Icons.fingerprint_rounded,
          title: 'بصمة الدوام',
          color: AppTheme.warningOrange,
          onTap: () => widget.onTabChange(1),
        ),
        _buildActionCard(
          icon: Icons.people_alt_rounded,
          title: 'دليل الموظفين',
          color: AppTheme.successGreen,
          onTap: () => context.push(AppRoutes.employeeDirectory),
        ),
        _buildActionCard(
          icon: Icons.settings_rounded,
          title: 'الإعدادات',
          color: Colors.blueAccent,
          onTap: () => widget.onTabChange(4),
        ),
      ],
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
      borderRadius: 16,
      opacity: 0.08,
      borderColor: color.withOpacity(0.25),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // قسم الإعلانات والتعاميم
  Widget _buildAnnouncementsSection(bool isDark) {
    if (_isLoading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(20.0),
        child: CircularProgressIndicator(color: AppTheme.neonCyan),
      ));
    }

    if (_announcements.isEmpty) {
      return const GlassContainer(
        width: double.infinity,
        padding: EdgeInsets.all(24),
        borderRadius: 16,
        child: Center(
          child: Text(
            'لا توجد تعاميم أو إعلانات جديدة حالياً ✨',
            style: TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Cairo'),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _announcements.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final announcement = _announcements[index];
        final isPinned = announcement['is_pinned'] ?? false;
        final cardColor = isPinned ? AppTheme.warningOrange : AppTheme.neonCyan;

        return GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 16,
          opacity: isPinned ? 0.12 : 0.08,
          borderColor: cardColor.withOpacity(0.3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (isPinned) ...[
                        const Icon(Icons.push_pin_rounded, color: AppTheme.warningOrange, size: 16),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        announcement['title'] ?? 'إعلان إداري',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'Cairo',
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _formatAnnounceDate(announcement['created_at']),
                    style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'Cairo'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                announcement['content'] ?? '',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontFamily: 'Cairo',
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
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

  Widget _buildAdminDashboardCard(bool isDark) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      borderRadius: 20,
      opacity: 0.15,
      borderColor: AppTheme.cyberPurple.withOpacity(0.3),
      boxShadow: [
        BoxShadow(
          color: AppTheme.cyberPurple.withOpacity(0.08),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(AppRoutes.adminDashboard),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.cyberPurple.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.cyberPurple.withOpacity(0.4)),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_rounded,
                    color: AppTheme.cyberPurple,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'بوابة الإدارة والمدراء 👑',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          color: AppTheme.cyberPurple,
                          shadows: [
                            Shadow(
                              color: AppTheme.cyberPurple,
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'إدارة الإجازات، السلف، الأجهزة المقفلة، ومراقبة خروقات الأمان والـ GPS.',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontFamily: 'Cairo',
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppTheme.cyberPurple,
                  size: 16,
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
