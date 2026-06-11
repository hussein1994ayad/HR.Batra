// =========================================================================
// نظام HR Pro v6.0 - تقارير الحضور المتقدمة
// =========================================================================

import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';
import 'package:url_launcher/url_launcher.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  bool _isLoading = true;
  DateTimeRange _selectedDateRange = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now(),
  );
  
  String? _selectedBranchId = 'all';
  String? _selectedEmployeeId = 'all';

  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employeesList = [];
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    try {
      final List<Future<dynamic>> initFutures = [
        SupabaseService.client.from('branches').select('id, name').order('name'),
        SupabaseService.client.from('employees').select('id, full_name, employee_code, branch_id, is_active').order('full_name')
      ];
      final results = await Future.wait(initFutures);
      _branches = List<Map<String, dynamic>>.from(results[0]);
      _employeesList = List<Map<String, dynamic>>.from(results[1]);
    } catch (e) {
      debugPrint('Error loading branches/employees: $e');
    }
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      final startStr = _selectedDateRange.start.toIso8601String().split('T')[0];
      final endStr = _selectedDateRange.end.toIso8601String().split('T')[0];

      var query = SupabaseService.client
          .from('attendance')
          .select('id, check_in_time, check_out_time, check_in_lat, check_in_lng, check_out_lat, check_out_lng, status, work_date, employees!inner(id, full_name, employee_code, branch_id)')
          .gte('work_date', startStr)
          .lte('work_date', endStr);

      if (_selectedEmployeeId != null && _selectedEmployeeId != 'all') {
        query = query.eq('employee_id', _selectedEmployeeId!);
      }
      if (_selectedBranchId != null && _selectedBranchId != 'all') {
        query = query.eq('employees.branch_id', _selectedBranchId!);
      }

      final data = await query
          .order('work_date', ascending: false)
          .order('check_in_time', ascending: false)
          .limit(300);
      final List<Map<String, dynamic>> processed = [];

      for (var record in data) {
        if (record['employees'] != null) {
          String status = record['status'] ?? 'حاضر';
          if (status == 'present') status = 'حاضر';
          if (status == 'late') status = 'تأخير';
          if (status == 'absent') status = 'غائب';
          if (status == 'half_day') status = 'نصف يوم';

          processed.add({
            'id': record['id'],
            'employee_name': record['employees']['full_name'],
            'employee_code': record['employees']['employee_code'],
            'check_in': record['check_in_time'],
            'check_out': record['check_out_time'],
            'check_in_lat': record['check_in_lat'],
            'check_in_lng': record['check_in_lng'],
            'check_out_lat': record['check_out_lat'],
            'check_out_lng': record['check_out_lng'],
            'work_date': record['work_date'],
            'status': status,
          });
        }
      }

      // Add missing employees as absent
      final Set<String> employeesWithRecords = data.map<String>((r) {
        if (r['employees'] != null) return r['employees']['id'].toString();
        return '';
      }).toSet();

      for (var emp in _employeesList) {
        if (_selectedEmployeeId != null && _selectedEmployeeId != 'all' && emp['id'] != _selectedEmployeeId) continue;
        if (_selectedBranchId != null && _selectedBranchId != 'all' && emp['branch_id'] != _selectedBranchId) continue;
        
        if (!employeesWithRecords.contains(emp['id'].toString())) {
          processed.add({
            'id': 'virtual_${emp['id']}',
            'employee_name': emp['full_name'],
            'employee_code': emp['employee_code'] ?? '',
            'check_in': null,
            'check_out': null,
            'check_in_lat': null,
            'check_in_lng': null,
            'check_out_lat': null,
            'check_out_lng': null,
            'work_date': endStr,
            'status': 'غائب',
          });
        }
      }

      // ترتيب إضافي حسب الغياب والاسم
      processed.sort((a, b) {
        if (a['status'] == 'غائب' && b['status'] != 'غائب') return 1;
        if (a['status'] != 'غائب' && b['status'] == 'غائب') return -1;
        return (a['employee_name'] ?? '').compareTo(b['employee_name'] ?? '');
      });

      setState(() {
        _records = processed;
      });
    } catch (e) {
      debugPrint('Error loading attendance: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDateRange,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.neonCyan,
              surface: Color(0xFF1A1F3A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
      _loadRecords();
    }
  }

  Future<void> _openMap(double? lat, double? lng) async {
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('إحداثيات الموقع غير متوفرة لهذا السجل', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الخرائط', style: TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  Future<void> _editTimeDialog(Map<String, dynamic> record) async {
    TimeOfDay? newCheckIn;
    TimeOfDay? newCheckOut;

    // تهيئة الأوقات الحالية إذا وجدت
    if (record['check_in'] != null) {
      try {
        final dt = DateTime.parse(record['check_in']).toLocal();
        newCheckIn = TimeOfDay(hour: dt.hour, minute: dt.minute);
      } catch (e) {
        try {
          final parts = record['check_in'].toString().split(':');
          newCheckIn = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        } catch (_) {}
      }
    }
    
    if (record['check_out'] != null) {
      try {
        final dt = DateTime.parse(record['check_out']).toLocal();
        newCheckOut = TimeOfDay(hour: dt.hour, minute: dt.minute);
      } catch (e) {
        try {
          final parts = record['check_out'].toString().split(':');
          newCheckOut = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        } catch (_) {}
      }
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('تعديل وقت الحضور: ${record['employee_name']}', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('وقت الدخول', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
                    subtitle: Text(newCheckIn != null ? newCheckIn!.format(context) : 'لم يُحدد', style: const TextStyle(color: AppTheme.successGreen, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.access_time_filled_rounded, color: AppTheme.successGreen),
                    onTap: () async {
                      final time = await showTimePicker(context: context, initialTime: newCheckIn ?? TimeOfDay.now());
                      if (time != null) setStateDialog(() => newCheckIn = time);
                    },
                  ),
                  const Divider(color: Colors.white12),
                  ListTile(
                    title: const Text('وقت الخروج', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
                    subtitle: Text(newCheckOut != null ? newCheckOut!.format(context) : 'لم يُحدد', style: const TextStyle(color: AppTheme.dangerRed, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.access_time_filled_rounded, color: AppTheme.dangerRed),
                    onTap: () async {
                      final time = await showTimePicker(context: context, initialTime: newCheckOut ?? TimeOfDay.now());
                      if (time != null) setStateDialog(() => newCheckOut = time);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white54, fontFamily: 'Cairo')),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.neonCyan),
                  onPressed: () async {
                    Navigator.pop(context);
                    _saveEditedTime(record['id'], record['work_date'], newCheckIn, newCheckOut);
                  },
                  child: const Text('حفظ التعديلات', style: TextStyle(color: Colors.black, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Future<void> _saveEditedTime(String recordId, String workDateStr, TimeOfDay? checkIn, TimeOfDay? checkOut) async {
    setState(() => _isLoading = true);
    try {
      final Map<String, dynamic> updates = {};
      
      // دمج التاريخ والوقت لتكوين ISO String صحيحة لحفظها في Supabase
      if (checkIn != null) {
        final dt = DateTime.parse(workDateStr);
        final combined = DateTime(dt.year, dt.month, dt.day, checkIn.hour, checkIn.minute).toUtc().toIso8601String();
        updates['check_in_time'] = combined;
      }
      
      if (checkOut != null) {
        final dt = DateTime.parse(workDateStr);
        final combined = DateTime(dt.year, dt.month, dt.day, checkOut.hour, checkOut.minute).toUtc().toIso8601String();
        updates['check_out_time'] = combined;
      }

      if (updates.isNotEmpty) {
        await SupabaseService.client.from('attendance').update(updates).eq('id', recordId);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث الأوقات بنجاح ✅', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.successGreen));
        _loadRecords();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error updating time: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدث خطأ أثناء التحديث ❌', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.dangerRed));
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentCount = _records.where((r) => r['status'] != 'غائب').length;
    final absentCount = _records.length - presentCount;

    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('تقارير الحضور المتقدمة 📊', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        ),
        body: Column(
          children: [
            // قسم الفلاتر العلوية
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  // Branch Dropdown
                  Expanded(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.neonCyan.withOpacity(0.2)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedBranchId,
                          hint: const Text('جميع الفروع', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11)),
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1A1F3A),
                          icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.neonCyan),
                          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11),
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('جميع الفروع')),
                            ..._branches.map((b) => DropdownMenuItem<String>(value: b['id'], child: Text(b['name']))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedBranchId = val;
                              if (_selectedEmployeeId != null && _selectedEmployeeId != 'all') {
                                final emp = _employeesList.firstWhere((e) => e['id'] == _selectedEmployeeId, orElse: () => <String, dynamic>{});
                                if (emp.isNotEmpty && val != 'all' && emp['branch_id'] != val) {
                                  _selectedEmployeeId = 'all';
                                }
                              }
                            });
                            _loadRecords();
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Employee Dropdown
                  Expanded(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.successGreen.withOpacity(0.2)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedEmployeeId,
                          hint: const Text('جميع الموظفين', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11)),
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1A1F3A),
                          icon: const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.successGreen),
                          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 11),
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('جميع الموظفين')),
                            ..._employeesList.where((emp) {
                              if (_selectedBranchId == null || _selectedBranchId == 'all') return true;
                              return emp['branch_id'] == _selectedBranchId;
                            }).map((e) => DropdownMenuItem<String>(value: e['id'], child: Text(e['full_name']))),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedEmployeeId = val;
                            });
                            _loadRecords();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // نطاق التاريخ والإحصائيات
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: _selectDateRange,
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.warningOrange.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_selectedDateRange.start.month}/${_selectedDateRange.start.day} - ${_selectedDateRange.end.month}/${_selectedDateRange.end.day}',
                              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.date_range_rounded, color: AppTheme.warningOrange, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildStatChip('حاضر', presentCount, AppTheme.successGreen),
                        const SizedBox(width: 6),
                        _buildStatChip('غائب', absentCount, AppTheme.dangerRed),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan))
                  : _records.isEmpty
                      ? const Center(child: Text('لا توجد بيانات لهذه الفترة أو الفلاتر', style: TextStyle(color: Colors.white54, fontFamily: 'Cairo')))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          itemCount: _records.length,
                          itemBuilder: (context, index) {
                            final r = _records[index];
                            final isAbsent = r['status'] == 'غائب';
                            final checkIn = r['check_in'] != null ? _formatTime(r['check_in']) : '--:--';
                            final checkOut = r['check_out'] != null ? _formatTime(r['check_out']) : '--:--';

                            return GlassContainer(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              borderRadius: 14,
                              opacity: 0.05,
                              borderColor: isAbsent ? AppTheme.dangerRed.withOpacity(0.2) : AppTheme.successGreen.withOpacity(0.2),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: (isAbsent ? AppTheme.dangerRed : AppTheme.successGreen).withOpacity(0.15),
                                    child: Icon(
                                      isAbsent ? Icons.person_off_rounded : Icons.how_to_reg_rounded,
                                      color: isAbsent ? AppTheme.dangerRed : AppTheme.successGreen,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(r['employee_name'] ?? 'مجهول', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                                        Text('${r['employee_code']} | ${r['work_date']}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                  if (!isAbsent)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Row(
                                          children: [
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                const Text('دخول', style: TextStyle(color: AppTheme.successGreen, fontFamily: 'Cairo', fontSize: 9)),
                                                Row(
                                                  children: [
                                                    if (r['check_in_lat'] != null)
                                                      GestureDetector(
                                                        onTap: () => _openMap(r['check_in_lat'], r['check_in_lng']),
                                                        child: const Icon(Icons.location_on_rounded, color: AppTheme.successGreen, size: 14),
                                                      ),
                                                    const SizedBox(width: 2),
                                                    Text(checkIn, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 12),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                const Text('خروج', style: TextStyle(color: AppTheme.dangerRed, fontFamily: 'Cairo', fontSize: 9)),
                                                Row(
                                                  children: [
                                                    if (r['check_out_lat'] != null)
                                                      GestureDetector(
                                                        onTap: () => _openMap(r['check_out_lat'], r['check_out_lng']),
                                                        child: const Icon(Icons.location_on_rounded, color: AppTheme.dangerRed, size: 14),
                                                      ),
                                                    const SizedBox(width: 2),
                                                    Text(checkOut, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 8),
                                            // Edit Button
                                            IconButton(
                                              icon: const Icon(Icons.edit_calendar_rounded, color: AppTheme.neonCyan, size: 18),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              onPressed: () => _editTimeDialog(r),
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: AppTheme.dangerRed.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                      child: const Text('غائب', style: TextStyle(color: AppTheme.dangerRed, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 10)),
          const SizedBox(width: 4),
          Text(count.toString(), style: TextStyle(color: color, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  String _formatTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime).toLocal();
      int hour = dt.hour;
      final int minute = dt.minute;
      final String period = hour >= 12 ? 'م' : 'ص';
      
      hour = hour % 12;
      if (hour == 0) hour = 12;
      
      final String minuteStr = minute.toString().padLeft(2, '0');
      return '$hour:$minuteStr $period';
    } catch (e) {
      // Fallback for "21:53" or "21:53:00"
      try {
        final parts = isoTime.split(':');
        if (parts.length >= 2) {
          int hour = int.parse(parts[0]);
          final minute = parts[1];
          final String period = hour >= 12 ? 'م' : 'ص';
          hour = hour % 12;
          if (hour == 0) hour = 12;
          return '$hour:$minute $period';
        }
      } catch (_) {}
      return '--:--';
    }
  }
}
