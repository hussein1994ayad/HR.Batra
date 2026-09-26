// =========================================================================
// نظام HR Pro v6.0 - إدارة أوقات العمل للأفرع (Branch Work Schedules)
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes/app_router.dart';
import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

class BranchScheduleScreen extends StatefulWidget {
  const BranchScheduleScreen({super.key});

  @override
  State<BranchScheduleScreen> createState() => _BranchScheduleScreenState();
}

class _BranchScheduleScreenState extends State<BranchScheduleScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _branches = [];

  // أسماء أيام الأسبوع بالعربية
  static const List<String> _dayNames = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      final employeeRes = await SupabaseService.client
          .from('employees')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (employeeRes == null || (employeeRes['role'] != 'admin' && employeeRes['role'] != 'manager')) {
        if (mounted) Navigator.pop(context);
        return;
      }

      // جلب بيانات الأفرع وجداول العمل بالتوازي
      final results = await Future.wait([
        SupabaseService.client
            .from('branches')
            .select('id, name')
            .order('name'),
        SupabaseService.client
            .from('work_schedules')
            .select()
            .isFilter('employee_id', null)
            .isFilter('department_id', null)
            .not('branch_id', 'is', null)
      ]);

      final zones = results[0] as List<dynamic>;
      final schedules = results[1] as List<dynamic>;

      // دمج البيانات
      final List<Map<String, dynamic>> merged = [];
      for (final zone in zones) {
        final schedule = schedules.firstWhere(
          (s) => s['branch_id'] == zone['id'],
          orElse: () => <String, dynamic>{},
        );
        merged.add({
          'zone_id': zone['id'],
          'zone_name': zone['name'],
          'has_schedule': schedule.isNotEmpty,
          'schedule': schedule,
        });
      }

      setState(() {
        _branches = merged;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل الأفرع: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // إضافة أو تعديل جدول عمل فرع
  Future<void> _editSchedule(Map<String, dynamic> branch) async {
    final schedule = branch['schedule'] as Map<String, dynamic>;
    final bool hasSchedule = branch['has_schedule'] as bool;

    // القيم الأولية
    List<int> workDays = hasSchedule
        ? List<int>.from((schedule['work_days'] ?? [0, 1, 2, 3, 4, 6]) as Iterable<dynamic>)
        : [0, 1, 2, 3, 4, 6]; // كل الأيام ما عدا الجمعة (5)
    TimeOfDay shiftStart = hasSchedule
        ? _parseTime((schedule['check_in_time'] ?? '08:00:00') as String)
        : const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay shiftEnd = hasSchedule
        ? _parseTime((schedule['check_out_time'] ?? '16:00:00') as String)
        : const TimeOfDay(hour: 16, minute: 0);
    int reminderMinutes = 5; // القيمة الافتراضية
    int graceMinutes = (hasSchedule
        ? (schedule['grace_period_minutes'] ?? 15)
        : 15) as int;

    await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  // المقبض العلوي
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // العنوان
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.schedule_rounded, color: AppColors.brand, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'أوقات عمل: ${branch['zone_name']}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                hasSchedule ? 'تعديل الجدول الحالي' : 'إعداد جدول جديد',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: AppColors.textPrimary.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: AppColors.border, height: 1),
                  // المحتوى
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // أيام العمل
                        const Text('أيام العمل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(7, (dayIndex) {
                            final isSelected = workDays.contains(dayIndex);
                            final isFriday = dayIndex == 5;
                            return GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  if (isSelected) {
                                    workDays.remove(dayIndex);
                                  } else {
                                    workDays.add(dayIndex);
                                    workDays.sort();
                                  }
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isFriday ? AppColors.warning.withValues(alpha: 0.2) : AppColors.brand.withValues(alpha: 0.2))
                                      : AppColors.textPrimary.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? (isFriday ? AppColors.warning : AppColors.brand)
                                        : AppColors.border,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Text(
                                  _dayNames[dayIndex],
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 11,
                                    color: isSelected
                                        ? (isFriday ? AppColors.warning : AppColors.brand)
                                        : AppColors.textDisabled,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 24),

                        // أوقات الدوام
                        const Text('أوقات الدوام', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTimePicker(
                                label: 'بداية الدوام',
                                time: shiftStart,
                                icon: Icons.login_rounded,
                                color: AppColors.success,
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: shiftStart,
                                    builder: (ctx, child) {
                                      return Theme(
                                        data: ThemeData.dark().copyWith(
                                          colorScheme: const ColorScheme.dark(
                                            primary: AppColors.brand,
                                            surface: AppColors.surface2,
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked != null) {
                                    setModalState(() => shiftStart = picked);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTimePicker(
                                label: 'نهاية الدوام',
                                time: shiftEnd,
                                icon: Icons.logout_rounded,
                                color: AppColors.danger,
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: shiftEnd,
                                    builder: (ctx, child) {
                                      return Theme(
                                        data: ThemeData.dark().copyWith(
                                          colorScheme: const ColorScheme.dark(
                                            primary: AppColors.brand,
                                            surface: AppColors.surface2,
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked != null) {
                                    setModalState(() => shiftEnd = picked);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // التذكير وفترة السماح
                        const Text('إعدادات التذكير', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                        const SizedBox(height: 12),
                        GlassContainer(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.notifications_active_rounded, color: AppColors.warning, size: 18),
                                  const SizedBox(width: 8),
                                  const Text('إرسال التذكير بعد بداية الدوام بـ', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textSecondary)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.warning.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: DropdownButton<int>(
                                      value: reminderMinutes,
                                      dropdownColor: AppColors.surface2,
                                      underline: const SizedBox(),
                                      isDense: true,
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.bold),
                                      items: [5, 10, 15, 30].map((m) => DropdownMenuItem(value: m, child: Text('$m د'))).toList(),
                                      onChanged: (v) => setModalState(() => reminderMinutes = v!),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Icon(Icons.timer_rounded, color: AppColors.brand, size: 18),
                                  const SizedBox(width: 8),
                                  const Text('فترة السماح بالتأخير', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textSecondary)),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.brand.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: DropdownButton<int>(
                                      value: graceMinutes,
                                      dropdownColor: AppColors.surface2,
                                      underline: const SizedBox(),
                                      isDense: true,
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.brand, fontWeight: FontWeight.bold),
                                      items: [5, 10, 15, 20, 30].map((m) => DropdownMenuItem(value: m, child: Text('$m د'))).toList(),
                                      onChanged: (v) => setModalState(() => graceMinutes = v!),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // زر الحفظ
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            if (shiftStart.hour > shiftEnd.hour || (shiftStart.hour == shiftEnd.hour && shiftStart.minute >= shiftEnd.minute)) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('يجب أن يكون وقت البداية قبل وقت النهاية!', style: TextStyle(fontFamily: 'Cairo')),
                                    backgroundColor: AppColors.danger,
                                  ),
                                );
                              }
                              return;
                            }

                            final data = {
                              'branch_id': branch['zone_id'],
                              'name': 'دوام فرع ${branch['zone_name']}',
                              'work_days': workDays,
                              'check_in_time': '${shiftStart.hour.toString().padLeft(2, '0')}:${shiftStart.minute.toString().padLeft(2, '0')}:00',
                              'check_out_time': '${shiftEnd.hour.toString().padLeft(2, '0')}:${shiftEnd.minute.toString().padLeft(2, '0')}:00',
                              'grace_period_minutes': graceMinutes,
                            };

                            if (hasSchedule) {
                              await SupabaseService.client
                                  .from('work_schedules')
                                  .update(data)
                                  .eq('id', schedule['id'] as Object);
                            } else {
                              await SupabaseService.client
                                  .from('work_schedules')
                                  .insert(data);
                            }

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم حفظ جدول العمل بنجاح', style: TextStyle(fontFamily: 'Cairo')),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                              unawaited(_loadBranches());
                            }
                          } catch (e) {
                            debugPrint('خطأ في حفظ الجدول: $e');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')),
                                  backgroundColor: AppColors.danger,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand,
                          foregroundColor: AppColors.onStatus,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'حفظ جدول العمل',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTimePicker({
    required String label,
    required TimeOfDay time,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    int hour = time.hour;
    final String period = hour >= 12 ? 'م' : 'ص';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    final String minuteStr = time.minute.toString().padLeft(2, '0');
    final String formattedTime = '$hour:$minuteStr $period';

    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        padding: const EdgeInsets.all(14),
        borderRadius: 14,
        borderColor: color.withValues(alpha: 0.3),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppColors.textPrimary.withValues(alpha: 0.5))),
            const SizedBox(height: 4),
            Text(
              formattedTime,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'أوقات عمل الأفرع ⏰',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.map_rounded, color: AppColors.success),
              tooltip: 'إدارة مواقع الأفرع',
              onPressed: () {
                context.push(AppRoutes.adminBranchManagement);
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList())
            : _branches.isEmpty
                ? const Center(
                    child: GlassContainer(
                      padding: EdgeInsets.all(32),
                      margin: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_off_rounded, color: AppColors.warning, size: 54),
                          SizedBox(height: 16),
                          Text(
                            'لا توجد أفرع مسجلة حالياً',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'يرجى إضافة أفرع (مناطق جيوفينس) أولاً من قاعدة البيانات',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: AppColors.textDisabled, fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadBranches,
                    color: AppColors.brand,
                    backgroundColor: AppColors.surface1,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _branches.length,
                      itemBuilder: (context, index) {
                        final branch = _branches[index];
                        final hasSchedule = branch['has_schedule'];
                        final schedule = branch['schedule'] as Map<String, dynamic>;

                        return GlassContainer(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          borderRadius: 20,
                          borderColor: (hasSchedule as bool)
                              ? AppColors.success.withValues(alpha: 0.25)
                              : AppColors.warning.withValues(alpha: 0.25),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: (hasSchedule ? AppColors.success : AppColors.warning).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      hasSchedule ? Icons.business_rounded : Icons.warning_amber_rounded,
                                      color: hasSchedule ? AppColors.success : AppColors.warning,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (branch['zone_name'] ?? 'فرع غير مسمى') as String,
                                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                                        ),
                                        Text(
                                          hasSchedule ? 'الجدول مُعَد' : 'بدون جدول عمل',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 10,
                                            color: hasSchedule ? AppColors.success : AppColors.warning,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      hasSchedule ? Icons.edit_rounded : Icons.add_circle_outline_rounded,
                                      color: AppColors.brand,
                                    ),
                                    onPressed: () => _editSchedule(branch),
                                  ),
                                ],
                              ),
                              if (hasSchedule) ...[
                                const SizedBox(height: 12),
                                const Divider(color: AppColors.border, height: 1),
                                const SizedBox(height: 12),
                                // عرض أوقات الدوام
                                Row(
                                  children: [
                                    _buildTimeChip(
                                      'الدخول',
                                      _formatTimeStr((schedule['check_in_time'] ?? '08:00:00') as String),
                                      AppColors.success,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildTimeChip(
                                      'الخروج',
                                      _formatTimeStr((schedule['check_out_time'] ?? '16:00:00') as String),
                                      AppColors.danger,
                                    ),
                                    const SizedBox(width: 8),
                                    _buildTimeChip(
                                      'التذكير بعد',
                                      '${schedule['reminder_minutes_after'] ?? 5} د',
                                      AppColors.warning,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // عرض أيام العمل
                                Wrap(
                                  spacing: 4,
                                  children: List.generate(7, (d) {
                                    final List<dynamic> days = (schedule['work_days'] ?? <dynamic>[]) as List<dynamic>;
                                    final isWork = days.contains(d);
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isWork
                                            ? AppColors.brand.withValues(alpha: 0.15)
                                            : AppColors.danger.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isWork ? AppColors.brand.withValues(alpha: 0.3) : AppColors.border,
                                        ),
                                      ),
                                      child: Text(
                                        _dayNames[d].substring(0, _dayNames[d].length > 4 ? 4 : _dayNames[d].length),
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: isWork ? AppColors.brand : AppColors.borderStrong,
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _buildTimeChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 8, color: color.withValues(alpha: 0.7))),
            Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  String _formatTimeStr(String timeStr) {
    try {
      final parts = timeStr.split(':');
      int hour = int.parse(parts[0]);
      final int minute = int.parse(parts[1]);
      final String period = hour >= 12 ? 'م' : 'ص';
      
      hour = hour % 12;
      if (hour == 0) hour = 12;
      
      final String minuteStr = minute.toString().padLeft(2, '0');
      return '$hour:$minuteStr $period';
    } catch (e) {
      return timeStr;
    }
  }
}
