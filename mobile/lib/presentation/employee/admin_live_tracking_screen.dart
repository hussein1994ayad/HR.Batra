// =========================================================================
// نظام HR Pro v6.0 - شاشة خريطة التتبع الحي المتقدم وخط مسار الموظفين للمدراء
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/routes/app_router.dart';
import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';
import '../shared/widgets/glass_background.dart';

class AdminLiveTrackingScreen extends StatefulWidget {
  const AdminLiveTrackingScreen({super.key});

  @override
  State<AdminLiveTrackingScreen> createState() => _AdminLiveTrackingScreenState();
}

class _AdminLiveTrackingScreenState extends State<AdminLiveTrackingScreen> {
  final MapController _mapController = MapController();
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _autoRefreshEnabled = true;
  Timer? _autoRefreshTimer;

  // التاريخ المختار (افتراضياً اليوم)
  DateTime _selectedDate = DateTime.now();

  // الفلاتر
  String _selectedBranchId = 'all';
  String _selectedStatusFilter = 'all'; // 'all', 'inside', 'outside', 'checked_out', 'absent'
  String _searchQuery = '';

  // البيانات
  List<Map<String, dynamic>> _branchesList = [];
  List<Map<String, dynamic>> _employeesList = [];
  List<Map<String, dynamic>> _attendanceList = [];
  List<Map<String, dynamic>> _locationTrackingList = [];
  List<Map<String, dynamic>> _processedData = [];

  // الموظف المركز عليه حالياً وخط مساره
  Map<String, dynamic>? _selectedEmployeeForFocus;
  bool _showTrail = true;

  // الإحصائيات (KPIs)
  int _totalCount = 0;
  int _insideCount = 0;
  int _outsideCount = 0;
  int _checkedOutCount = 0;
  int _absentCount = 0;

  // مركز الخريطة الافتراضي
  LatLng _mapCenter = const LatLng(33.3152, 44.3661);
  dynamic _trackingChannel;

  @override
  void initState() {
    super.initState();
    _loadAllTrackingData();

    // تشغيل مؤقت التحديث التلقائي كل 15 ثانية كنسخة احتياطية
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_autoRefreshEnabled && mounted && !_isRefreshing) {
        _refreshLocationsSilently();
      }
    });

    // الاشتراك المباشر في قنوات Realtime للتحديث اللحظي الفوري عند تحرك أي موظف
    try {
      _trackingChannel = SupabaseService.client.channel('live-admin-tracking')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'location_tracking',
          callback: (payload) {
            if (mounted && !_isRefreshing) _refreshLocationsSilently();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance',
          callback: (payload) {
            if (mounted && !_isRefreshing) _refreshLocationsSilently();
          },
        )
        ..subscribe();
    } catch (e) {
      debugPrint(' تعذر بدء اشتراك Realtime للتتبع: $e');
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    try {
      if (_trackingChannel != null) {
        SupabaseService.client.removeChannel(_trackingChannel as RealtimeChannel);
      }
    } catch (_) {}
    super.dispose();
  }

  /// تحميل كافة بيانات الفروع والموظفين وسجلات الحضور والتتبع الجغرافي
  Future<void> _loadAllTrackingData() async {
    if (!mounted) return;
    setState(() => _isRefreshing = true);

    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    try {
      // 1. التحقق من صلاحيات المدير أو الـ HR
      final empRole = await SupabaseService.client
          .from('employees')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (empRole == null || (empRole['role'] != 'admin' && empRole['role'] != 'manager')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('عذراً، هذه الشاشة مخصصة لحسابات الإدارة والمدراء فقط', style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppColors.danger,
            ),
          );
          context.go(AppRoutes.employeeHome);
        }
        return;
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final startOfDayUtc = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).toUtc().toIso8601String();
      final endOfDayUtc = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59, 999).toUtc().toIso8601String();

      // 2. جلب الفروع، الموظفين، سجلات الحضور، ونقاط التتبع لليوم المختار بالتوازي
      final results = await Future.wait([
        SupabaseService.client.from('branches').select().order('name'),
        SupabaseService.client
            .from('employees')
            .select('id, full_name, avatar_url, role, branch_id, branches(id, name, latitude, longitude, radius_meters)')
            .eq('is_active', true)
            .order('full_name'),
        SupabaseService.client
            .from('attendance')
            .select()
            .eq('work_date', dateStr),
        SupabaseService.client
            .from('location_tracking')
            .select()
            .gte('timestamp', startOfDayUtc)
            .lte('timestamp', endOfDayUtc)
            .order('timestamp', ascending: true),
      ]);

      _branchesList = List<Map<String, dynamic>>.from(results[0]);
      _employeesList = List<Map<String, dynamic>>.from(results[1]);
      _attendanceList = List<Map<String, dynamic>>.from(results[2]);
      _locationTrackingList = List<Map<String, dynamic>>.from(results[3]);

      // 3. معالجة وتجميع بيانات كل موظف
      _processAllData();

      // 4. ضبط مركز الخريطة على الفرع المحدد
      _centerMapOnSelectedBranch();

    } catch (e) {
      debugPrint('خطأ في تحميل بيانات التتبع: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تحميل بيانات التتبع: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  /// تحديث صامت لإحداثيات المواقع الحية بدون وميض الشاشة
  Future<void> _refreshLocationsSilently() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final startOfDayUtc = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).toUtc().toIso8601String();
    final endOfDayUtc = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59, 999).toUtc().toIso8601String();

    try {
      final results = await Future.wait([
        SupabaseService.client.from('attendance').select().eq('work_date', dateStr),
        SupabaseService.client
            .from('location_tracking')
            .select()
            .gte('timestamp', startOfDayUtc)
            .lte('timestamp', endOfDayUtc)
            .order('timestamp', ascending: true),
      ]);

      if (!mounted) return;
      _attendanceList = List<Map<String, dynamic>>.from(results[0]);
      _locationTrackingList = List<Map<String, dynamic>>.from(results[1]);

      _processAllData();

      // تحديث كائن الموظف المركز عليه إذا كان محدداً
      if (_selectedEmployeeForFocus != null) {
        final currentId = _selectedEmployeeForFocus!['employee']['id'];
        final updated = _processedData.firstWhere(
          (item) => item['employee']['id'] == currentId,
          orElse: () => _selectedEmployeeForFocus!,
        );
        setState(() => _selectedEmployeeForFocus = updated);
      } else {
        setState(() {});
      }
    } catch (_) {}
  }

  /// معالجة بيانات الموظفين وتحديد موقف الحضور ومسار التتبع
  void _processAllData() {
    final List<Map<String, dynamic>> list = [];
    int inside = 0;
    int outside = 0;
    int checkedOut = 0;
    int absent = 0;

    for (final emp in _employeesList) {
      final String empId = emp['id'] as String;
      final branch = emp['branches'];
      final double? branchLat = (branch?['latitude'] as num?)?.toDouble();
      final double? branchLng = (branch?['longitude'] as num?)?.toDouble();
      final double branchRadius = (branch?['radius_meters'] as num?)?.toDouble() ?? 100.0;

      // 1. فحص سجل الحضور في جدول attendance بالأسماء الدقيقة للأعمدة
      final att = _attendanceList.firstWhere(
        (a) => a['employee_id'] == empId,
        orElse: () => <String, dynamic>{},
      );

      final String? checkInTime = att['check_in_time']?.toString();
      final String? checkOutTime = att['check_out_time']?.toString();
      final double? checkInLat = (att['check_in_lat'] as num?)?.toDouble();
      final double? checkInLng = (att['check_in_lng'] as num?)?.toDouble();
      final double? checkOutLat = (att['check_out_lat'] as num?)?.toDouble();
      final double? checkOutLng = (att['check_out_lng'] as num?)?.toDouble();

      final bool hasPunchedIn = att.isNotEmpty && checkInTime != null;
      final bool hasCheckedOut = hasPunchedIn && checkOutTime != null;

      // 2. نقاط خط التتبع من جدول location_tracking
      final empTrackingPoints = _locationTrackingList.where((p) => p['employee_id'] == empId).toList();

      // بناء قائمة مسار التحركات (Trail Coordinates)
      final List<LatLng> trailCoords = [];
      if (checkInLat != null && checkInLng != null) {
        trailCoords.add(LatLng(checkInLat, checkInLng));
      }
      for (final p in empTrackingPoints) {
        final double? lat = (p['latitude'] as num?)?.toDouble();
        final double? lng = (p['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final coord = LatLng(lat, lng);
          if (trailCoords.isEmpty || trailCoords.last.latitude != lat || trailCoords.last.longitude != lng) {
            trailCoords.add(coord);
          }
        }
      }
      if (checkOutLat != null && checkOutLng != null) {
        final outCoord = LatLng(checkOutLat, checkOutLng);
        if (trailCoords.isEmpty || trailCoords.last.latitude != checkOutLat || trailCoords.last.longitude != checkOutLng) {
          trailCoords.add(outCoord);
        }
      }

      // 3. تحديد الموقع الحي الأخير للموظف (Live Position)
      double? currentLat;
      double? currentLng;
      DateTime? lastSeen;
      int? batteryLevel;
      bool isMoving = false;

      if (empTrackingPoints.isNotEmpty) {
        final latest = empTrackingPoints.last;
        currentLat = (latest['latitude'] as num?)?.toDouble();
        currentLng = (latest['longitude'] as num?)?.toDouble();
        batteryLevel = (latest['battery_level'] as num?)?.toInt();
        isMoving = latest['is_moving'] == true;
        if (latest['timestamp'] != null) {
          lastSeen = DateTime.tryParse(latest['timestamp'] as String)?.toLocal();
        }
      } else if (hasCheckedOut && checkOutLat != null && checkOutLng != null) {
        currentLat = checkOutLat;
        currentLng = checkOutLng;
        lastSeen = DateTime.tryParse(checkOutTime)?.toLocal();
      } else if (hasPunchedIn && checkInLat != null && checkInLng != null) {
        currentLat = checkInLat;
        currentLng = checkInLng;
        lastSeen = DateTime.tryParse(checkInTime)?.toLocal();
      }

      // 4. حساب المسافة عن الفرع
      double? distanceToBranch;
      bool isInsideBranch = false;
      if (currentLat != null && currentLng != null && branchLat != null && branchLng != null) {
        distanceToBranch = Geolocator.distanceBetween(currentLat, currentLng, branchLat, branchLng);
        isInsideBranch = distanceToBranch <= branchRadius;
      }

      // 5. حساب إجمالي المسافة المقطوعة في خط المسار اليوم (كم)
      double totalDistanceKm = 0;
      if (trailCoords.length >= 2) {
        for (int i = 0; i < trailCoords.length - 1; i++) {
          totalDistanceKm += Geolocator.distanceBetween(
            trailCoords[i].latitude,
            trailCoords[i].longitude,
            trailCoords[i + 1].latitude,
            trailCoords[i + 1].longitude,
          );
        }
        totalDistanceKm = totalDistanceKm / 1000.0;
      }

      // 6. تحديد الحالة الوظيفية الدقيقة
      String status = 'absent';
      if (hasCheckedOut) {
        status = 'checked_out';
        checkedOut++;
      } else if (hasPunchedIn) {
        if (isInsideBranch) {
          status = 'inside';
          inside++;
        } else {
          status = 'outside';
          outside++;
        }
      } else {
        status = 'absent';
        absent++;
      }

      list.add({
        'employee': emp,
        'attendance': att,
        'hasPunchedIn': hasPunchedIn,
        'hasCheckedOut': hasCheckedOut,
        'status': status, // 'inside', 'outside', 'checked_out', 'absent'
        'currentLat': currentLat,
        'currentLng': currentLng,
        'distanceToBranch': distanceToBranch,
        'isInsideBranch': isInsideBranch,
        'branchName': branch?['name'] ?? 'بدون فرع',
        'branchLat': branchLat,
        'branchLng': branchLng,
        'branchRadius': branchRadius,
        'checkInTimeFormatted': checkInTime != null ? _formatTimeString(checkInTime) : null,
        'checkOutTimeFormatted': checkOutTime != null ? _formatTimeString(checkOutTime) : null,
        'checkInLat': checkInLat,
        'checkInLng': checkInLng,
        'lastSeen': lastSeen,
        'batteryLevel': batteryLevel,
        'isMoving': isMoving,
        'trailCoords': trailCoords,
        'totalDistanceKm': totalDistanceKm,
      });
    }

    _processedData = list;
    _totalCount = _employeesList.length;
    _insideCount = inside;
    _outsideCount = outside;
    _checkedOutCount = checkedOut;
    _absentCount = absent;
  }

  void _centerMapOnSelectedBranch() {
    if (_branchesList.isNotEmpty && _selectedBranchId != 'all') {
      final b = _branchesList.firstWhere((br) => br['id'] == _selectedBranchId, orElse: () => _branchesList.first);
      if (b['latitude'] != null && b['longitude'] != null) {
        final lat = (b['latitude'] as num).toDouble();
        final lng = (b['longitude'] as num).toDouble();
        _mapCenter = LatLng(lat, lng);
        _mapController.move(_mapCenter, 14.0);
      }
    } else if (_branchesList.isNotEmpty) {
      final b = _branchesList.first;
      if (b['latitude'] != null && b['longitude'] != null) {
        final lat = (b['latitude'] as num).toDouble();
        final lng = (b['longitude'] as num).toDouble();
        _mapCenter = LatLng(lat, lng);
      }
    }
  }

  String _formatTimeString(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  List<Map<String, dynamic>> get _filteredList {
    return _processedData.where((item) {
      final emp = item['employee'] as Map<String, dynamic>;
      final name = (emp['full_name'] ?? '').toString().toLowerCase();
      final branchId = emp['branch_id']?.toString() ?? '';
      final status = item['status'] as String;

      // تصفية البحث بالاسم
      if (_searchQuery.isNotEmpty && !name.contains(_searchQuery.toLowerCase())) {
        return false;
      }

      // تصفية بالفرع
      if (_selectedBranchId != 'all' && branchId != _selectedBranchId) {
        return false;
      }

      // تصفية بالحالة
      if (_selectedStatusFilter == 'inside' && status != 'inside') return false;
      if (_selectedStatusFilter == 'outside' && status != 'outside') return false;
      if (_selectedStatusFilter == 'checked_out' && status != 'checked_out') return false;
      if (_selectedStatusFilter == 'absent' && status != 'absent') return false;

      return true;
    }).toList();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.brand,
              surface: AppColors.surface1,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _selectedEmployeeForFocus = null;
      });
      unawaited(_loadAllTrackingData());
    }
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
            'خريطة التتبع الحي للموظفين',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
          ),
          actions: [
            // زر تشغيل/إيقاف التحديث التلقائي الحي
            IconButton(
              icon: Icon(
                _autoRefreshEnabled ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
                color: _autoRefreshEnabled ? AppColors.success : AppColors.textDisabled,
                size: 20,
              ),
              tooltip: _autoRefreshEnabled ? 'التحديث التلقائي نشط (كل 15 ثانية)' : 'التحديث التلقائي متوقف',
              onPressed: () {
                setState(() => _autoRefreshEnabled = !_autoRefreshEnabled);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _autoRefreshEnabled ? 'تم تفعيل التحديث الحي التلقائي (كل 15 ثانية)' : 'تم إيقاف التحديث التلقائي ⏸',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),

            // زر التحديث اليدوي
            IconButton(
              icon: _isRefreshing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                  : const Icon(Icons.refresh_rounded, color: AppColors.brand),
              tooltip: 'تحديث البيانات الآن',
              onPressed: _loadAllTrackingData,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(135),
            child: Column(
              children: [
                // 1. شريط التاريخ واختيار الفرع
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  child: Row(
                    children: [
                      // زر اختيار التاريخ
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppColors.brandStrong.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.brand.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_rounded, color: AppColors.brand, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat('yyyy-MM-dd').format(_selectedDate),
                                style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // قائمة اختيار الفرع
                      Expanded(
                        child: Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _selectedBranchId != 'all' ? AppColors.brand : AppColors.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              dropdownColor: AppColors.surface1,
                              value: _selectedBranchId,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.brand, size: 18),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: 'all',
                                  child: Row(
                                    children: [
                                      Icon(Icons.domain_rounded, color: AppColors.brand, size: 15),
                                      SizedBox(width: 6),
                                      Flexible(child: Text(' جميع الفروع والمواقع', overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                                ),
                                ..._branchesList.map((branch) {
                                  return DropdownMenuItem<String>(
                                    value: branch['id'] as String,
                                    child: Row(
                                      children: [
                                        const Icon(Icons.storefront_rounded, color: AppColors.success, size: 15),
                                        const SizedBox(width: 6),
                                        Flexible(child: Text('فرع: ${branch['name']}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 11))),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() => _selectedBranchId = val);
                                _centerMapOnSelectedBranch();
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. شريط البحث باسم الموظف
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 11),
                            decoration: const InputDecoration(
                              hintText: 'البحث باسم الموظف المستهدف...',
                              hintStyle: TextStyle(fontFamily: 'Cairo', color: AppColors.textDisabled, fontSize: 11),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (val) => setState(() => _searchQuery = val.trim()),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _searchQuery = ''),
                            child: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 16),
                          ),
                      ],
                    ),
                  ),
                ),

                // 3. فلاتر الحالة مع الأعداد الحقيقية
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _buildFilterChip('الكل ($_totalCount)', 'all'),
                      const SizedBox(width: 6),
                      _buildFilterChip('داخل الفرع ($_insideCount)', 'inside', color: AppColors.success),
                      const SizedBox(width: 6),
                      _buildFilterChip('خارج النطاق ($_outsideCount)', 'outside', color: AppColors.danger),
                      const SizedBox(width: 6),
                      _buildFilterChip('انصراف ($_checkedOutCount)', 'checked_out', color: AppColors.warning),
                      const SizedBox(width: 6),
                      _buildFilterChip('لم يبصم ($_absentCount) ⏳', 'absent', color: AppColors.textMuted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: _isLoading
            ? const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList())
            : Stack(
                children: [
                  // 1. خريطة OpenStreetMap التفاعلية مع خطوط المسار والإشارات
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _mapCenter,
                      initialZoom: 13.5,
                      minZoom: 4,
                      maxZoom: 18,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.batra.hrpro',
                      ),

                      // دوائر السياج الجغرافي للفروع
                      CircleLayer(
                        circles: _buildBranchGeofenceCircles(),
                      ),

                      // خط مسار تتبع الموظف المحدد (Polyline Trail)
                      if (_showTrail && _selectedEmployeeForFocus != null)
                        PolylineLayer(
                          polylines: _buildEmployeeTrailPolylines(),
                        ),

                      // إشارات مواقع الموظفين ونقاط البصمة
                      MarkerLayer(
                        markers: _buildMapMarkers(),
                      ),
                    ],
                  ),

                  // 2. بطاقة تفاصيل الموظف ومساره المباشر عند اختياره
                  if (_selectedEmployeeForFocus != null)
                    Positioned(
                      top: 10,
                      left: 14,
                      right: 14,
                      child: _buildEmployeeFocusCard(_selectedEmployeeForFocus!),
                    ),

                  // 3. القائمة السفلية لكافة الموظفين وموقف دوامهم
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildDraggableEmployeeList(),
                  ),
                ],
              ),
      ),
    );
  }

  // دوائر السياج الجغرافي للفروع المعتمدة
  List<CircleMarker> _buildBranchGeofenceCircles() {
    final List<CircleMarker> circles = [];
    for (final branch in _branchesList) {
      if (_selectedBranchId != 'all' && branch['id'] != _selectedBranchId) continue;

      final lat = (branch['latitude'] as num?)?.toDouble();
      final lng = (branch['longitude'] as num?)?.toDouble();
      final radius = (branch['radius_meters'] as num?)?.toDouble() ?? 100.0;

      if (lat != null && lng != null) {
        circles.add(
          CircleMarker(
            point: LatLng(lat, lng),
            radius: radius,
            useRadiusInMeter: true,
            color: AppColors.brand.withValues(alpha: 0.12),
            borderColor: AppColors.brand,
            borderStrokeWidth: 2,
          ),
        );
      }
    }
    return circles;
  }

  // إنشاء خط مسار التتبع (Trail Polyline) للموظف المحدد
  List<Polyline> _buildEmployeeTrailPolylines() {
    if (_selectedEmployeeForFocus == null) return [];
    final List<LatLng> coords = List<LatLng>.from((_selectedEmployeeForFocus!['trailCoords'] ?? <dynamic>[]) as Iterable<dynamic>);
    if (coords.length < 2) return [];

    return [
      Polyline(
        points: coords,
        strokeWidth: 4.5,
        color: AppColors.brand,
        borderStrokeWidth: 2.0,
        borderColor: AppColors.shadow,
      ),
    ];
  }

  // إنشاء إشارات المواقع للموظفين
  List<Marker> _buildMapMarkers() {
    final List<Marker> markers = [];

    for (final item in _filteredList) {
      final double? lat = item['currentLat'] as double?;
      final double? lng = item['currentLng'] as double?;
      if (lat == null || lng == null) continue;

      final emp = item['employee'] as Map<String, dynamic>;
      final String name = (emp['full_name'] ?? '') as String;
      final String status = item['status'] as String;
      final bool isFocused = _selectedEmployeeForFocus != null && _selectedEmployeeForFocus!['employee']['id'] == emp['id'];

      Color markerColor = AppColors.textMuted;
      if (status == 'inside') markerColor = AppColors.success;
      if (status == 'outside') markerColor = AppColors.danger;
      if (status == 'checked_out') markerColor = AppColors.warning;

      markers.add(
        Marker(
          point: LatLng(lat, lng),
          width: isFocused ? 58 : 46,
          height: isFocused ? 68 : 56,
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedEmployeeForFocus = item);
              _mapController.move(LatLng(lat, lng), 15.5);
            },
            child: Column(
              children: [
                Container(
                  width: isFocused ? 42 : 36,
                  height: isFocused ? 42 : 36,
                  decoration: BoxDecoration(
                    color: markerColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.textPrimary, width: isFocused ? 3 : 2),
                    boxShadow: [
                      BoxShadow(
                        color: markerColor.withValues(alpha: 0.7),
                        blurRadius: isFocused ? 12 : 6,
                        spreadRadius: isFocused ? 3 : 1,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name.substring(0, 1) : '؟',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down_rounded, color: markerColor, size: isFocused ? 24 : 18),
              ],
            ),
          ),
        ),
      );
    }

    // إذا كان هناك موظف محدد وله مسار، نضع علامة البداية (مكان البصمة)
    if (_selectedEmployeeForFocus != null) {
      final double? startLat = _selectedEmployeeForFocus!['checkInLat'] as double?;
      final double? startLng = _selectedEmployeeForFocus!['checkInLng'] as double?;
      if (startLat != null && startLng != null) {
        markers.add(
          Marker(
            point: LatLng(startLat, startLng),
            width: 32,
            height: 32,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface1,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 4)],
              ),
              child: const Center(
                child: Text('', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        );
      }
    }

    return markers;
  }

  // بطاقة تفاصيل الموظف المركز عليه ومسار تحركاته
  Widget _buildEmployeeFocusCard(Map<String, dynamic> item) {
    final emp = item['employee'] as Map<String, dynamic>;
    final name = emp['full_name'] ?? 'بدون اسم';
    final branch = item['branchName'];
    final status = item['status'];
    final checkIn = item['checkInTimeFormatted'];
    final checkOut = item['checkOutTimeFormatted'];
    final distance = item['distanceToBranch'];
    final totalKm = item['totalDistanceKm'] as double? ?? 0.0;
    final int? battery = item['batteryLevel'] as int?;
    final List<LatLng> trail = (item['trailCoords'] ?? <LatLng>[]) as List<LatLng>;

    Color statusColor = AppColors.textMuted;
    String statusText = 'لم يبصم حضور اليوم';
    if (status == 'inside') {
      statusColor = AppColors.success;
      statusText = 'داخل نطاق الفرع (باصم حضور)';
    } else if (status == 'outside') {
      statusColor = AppColors.danger;
      statusText = 'خارج نطاق الفرع (باصم حضور)';
    } else if (status == 'checked_out') {
      statusColor = AppColors.warning;
      statusText = 'سجل انصراف من الدوام';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface1.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor, width: 1.5),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 16)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: statusColor.withValues(alpha: 0.2),
                    child: Text(((name.isNotEmpty as bool) ? name.substring(0, 1) : '؟') as String, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: statusColor)),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name as String, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 13)),
                      Text('فرع: $branch', style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 10)),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
                onPressed: () => setState(() => _selectedEmployeeForFocus = null),
              ),
            ],
          ),
          const Divider(color: AppColors.border, height: 14),

          // تفاصيل الموقف والبصمة
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الموقف: $statusText', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: statusColor, fontSize: 11)),
              if (distance != null)
                Text(
                  'المسافة عن الفرع: ${((distance < 1000) as bool) ? "${distance.round()} م" : "${(distance / 1000).toStringAsFixed(1)} كم"}',
                  style: const TextStyle(fontFamily: 'Cairo', color: AppColors.brand, fontSize: 11, fontWeight: FontWeight.bold),
                ),
            ],
          ),

          if (checkIn != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('بصمة الحضور: $checkIn ${checkOut != null ? " • الانصراف: $checkOut" : ""}', style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textSecondary, fontSize: 10)),
                if (battery != null)
                  Text('البطارية: $battery%', style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 10)),
              ],
            ),
          ],

          // تفاصيل خط المسار
          if (trail.length >= 2) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.route_rounded, color: AppColors.brand, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'مسار التحركات: ${totalKm.toStringAsFixed(2)} كم (${trail.length} نقطة رصد)',
                        style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => setState(() => _showTrail = !_showTrail),
                    child: Text(
                      _showTrail ? 'إخفاء المسار' : 'إظهار المسار',
                      style: const TextStyle(fontFamily: 'Cairo', color: AppColors.brand, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // القائمة السفلية لكافة الموظفين
  Widget _buildDraggableEmployeeList() {
    final filtered = _filteredList;

    return Container(
      height: 230,
      decoration: BoxDecoration(
        color: AppColors.surface1.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: AppColors.onStatus, blurRadius: 20)],
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.borderStrong, borderRadius: BorderRadius.circular(10)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                  'الموظفون وموقف البصمة (${filtered.length})',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                  'اضغط على موظف لتتبع مساره',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppColors.brand.withValues(alpha: 0.8)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),

          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('لا توجد بيانات تطابق الفلتر المحدد', style: TextStyle(fontFamily: 'Cairo', color: AppColors.textDisabled, fontSize: 12)),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final emp = item['employee'] as Map<String, dynamic>;
                      final name = emp['full_name'] ?? 'بدون اسم';
                      final branch = item['branchName'];
                      final status = item['status'];
                      final checkIn = item['checkInTimeFormatted'];
                      final double? lat = item['currentLat'] as double?;
                      final double? lng = item['currentLng'] as double?;
                      final distance = item['distanceToBranch'];
                      final List<LatLng> trail = (item['trailCoords'] ?? <LatLng>[]) as List<LatLng>;

                      Color statusColor = AppColors.textMuted;
                      String statusLabel = 'لم يبصم ⏳';
                      if (status == 'inside') {
                        statusColor = AppColors.success;
                        statusLabel = 'داخل الفرع';
                      } else if (status == 'outside') {
                        statusColor = AppColors.danger;
                        statusLabel = 'خارج النطاق';
                      } else if (status == 'checked_out') {
                        statusColor = AppColors.warning;
                        statusLabel = 'انصراف';
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.06)),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          leading: CircleAvatar(
                            backgroundColor: statusColor.withValues(alpha: 0.2),
                            radius: 16,
                            child: Text(((name.isNotEmpty as bool) ? name.substring(0, 1) : '؟') as String, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: statusColor, fontSize: 11)),
                          ),
                          title: Text(name as String, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 12)),
                          subtitle: Text(
                            '$branch ${checkIn != null ? "• حضور: $checkIn" : ""} ${distance != null ? "• (${((distance < 1000) as bool) ? "${distance.round()}م" : "${(distance / 1000).toStringAsFixed(1)}كم"})" : ""}',
                            style: const TextStyle(fontFamily: 'Cairo', color: AppColors.textMuted, fontSize: 9.5),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (trail.length >= 2)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.timeline_rounded, color: AppColors.brand, size: 16),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: statusColor, fontSize: 9.5),
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            if (lat != null && lng != null) {
                              setState(() => _selectedEmployeeForFocus = item);
                              _mapController.move(LatLng(lat, lng), 15.5);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('لم يتم تسجيل إحداثيات موقع لهذا الموظف في هذا اليوم حتى الآن', style: TextStyle(fontFamily: 'Cairo')),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, {Color? color}) {
    final bool isSelected = _selectedStatusFilter == value;
    final activeColor = color ?? AppColors.brand;

    return GestureDetector(
      onTap: () => setState(() => _selectedStatusFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.25) : AppColors.textPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? activeColor : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

