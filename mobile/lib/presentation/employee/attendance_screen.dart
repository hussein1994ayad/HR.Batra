// =========================================================================
// نظام HR Pro v6.0 - شاشة بصمة الدوام والخرائط الجغرافية (Attendance Map & Verification Screen)
// =========================================================================

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:dio/dio.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/attendance_sync_service.dart';
import '../../core/services/location_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_container.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> with SingleTickerProviderStateMixin {
  // إحداثيات افتراضية للفرع في حال لم يتم تحميل فرع الموظف بعد
  double _branchLat = 33.3152; // بغداد، العراق كافتراضي
  double _branchLng = 44.3661;
  double _branchRadius = 100.0; // 100 متر
  String _branchName = 'جاري تحميل الفرع...';
  String? _branchId;
  String _selectedPunchType = 'check_in';

  Position? _currentPosition;
  double? _distanceToBranch;
  bool _isLocating = true;
  bool _isSubmitting = false;
  bool _mockDetected = false;
  String? _errorMessage;
  Map<String, dynamic>? _todayAttendance;
  Map<String, dynamic>? _workSchedule;

  final MapController _mapController = MapController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  void initState() {
    super.initState();
    // إعداد حركة النبض لزر البصمة المضيء
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initLocationAndBranch();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // بدء الاستماع المباشر والمستمر للموقع الجغرافي لتحديث الإحداثيات فورياً دون تأخير
  void _startPositionStream() {
    _positionStreamSubscription?.cancel();
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 1, // تحديث كل متر واحد للحصول على دقة فورية
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        if (!mounted) return;
        if (position.isMocked) {
          setState(() {
            _mockDetected = true;
            _errorMessage = 'تم رصد محاولة استخدام تطبيق لتزييف الموقع (Mock GPS). تم إيقاف التبصيم.';
          });
          return;
        }

        setState(() {
          _currentPosition = position;
          _isLocating = false;
          _distanceToBranch = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            _branchLat,
            _branchLng,
          );
        });
      },
      onError: (e) {
        debugPrint('GPS Stream Error: $e');
      },
    );
  }

  // إعادة تحديث الموقع الجغرافي يدوياً أو تلقائياً بسرعة فائقة
  Future<void> _refreshGpsLocation({bool userInitiated = false}) async {
    if (userInitiated) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جاري جلب إحداثيات الـ GPS الفورية بأعلى دقة... 📍', style: TextStyle(fontFamily: 'Cairo')),
          duration: Duration(seconds: 1),
          backgroundColor: AppTheme.primaryTeal,
        ),
      );
    }

    try {
      final freshPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      ).timeout(const Duration(seconds: 3));

      if (mounted) {
        setState(() {
          _currentPosition = freshPos;
          _isLocating = false;
          _distanceToBranch = Geolocator.distanceBetween(
            freshPos.latitude,
            freshPos.longitude,
            _branchLat,
            _branchLng,
          );
        });

        _mapController.move(LatLng(freshPos.latitude, freshPos.longitude), 16.0);
      }
    } catch (_) {
      // الهبوط السريع إلى آخر موقع
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) {
        setState(() {
          _currentPosition = lastPos;
          _isLocating = false;
          _distanceToBranch = Geolocator.distanceBetween(
            lastPos.latitude,
            lastPos.longitude,
            _branchLat,
            _branchLng,
          );
        });
      }
    }
  }

  // تهيئة وتحديد موقع الموظف والفرع المخصص له بسرعة فائقة (Dual-phase Fast Init)
  Future<void> _initLocationAndBranch() async {
    setState(() {
      _isLocating = true;
      _errorMessage = null;
      _mockDetected = false;
    });

    try {
      final user = SupabaseService.currentUser;
      if (user == null) return;

      // 1. قراءة البيانات من الكاش المحلي أولاً للرسم الفوري للواجهة بدون انتظار الإنترنت
      final cached = await AttendanceSyncService.getCachedData();
      if (cached != null && cached['branch'] != null) {
        final branch = cached['branch'];
        _branchId = branch['id'];
        _branchName = branch['name'] ?? 'فرع الشركة';
        _branchLat = (branch['latitude'] as num).toDouble();
        _branchLng = (branch['longitude'] as num).toDouble();
        _branchRadius = (branch['radius_meters'] as num).toDouble();
        _workSchedule = cached['schedule'];
      }

      // 2. فحص صلاحيات الـ GPS
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('خدمة تحديد الموقع الجغرافي (GPS) معطلة في هاتفك. يرجى تفعيلها.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('تم رفض منح صلاحية الوصول للموقع الجغرافي.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('تم رفض صلاحية الموقع الجغرافي نهائياً، يرجى تفعيلها من إعدادات الهاتف.');
      }

      // 3. المرحلة الأولى الفورية (Fast-Path): قراءة آخر موقع معروف في أقل من 20ms لتجهيز الشاشة فوراً
      Position? initialPosition = await Geolocator.getLastKnownPosition();
      if (initialPosition != null && mounted) {
        setState(() {
          _currentPosition = initialPosition;
          _isLocating = false;
          _distanceToBranch = Geolocator.distanceBetween(
            initialPosition.latitude,
            initialPosition.longitude,
            _branchLat,
            _branchLng,
          );
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              _mapController.move(LatLng(initialPosition.latitude, initialPosition.longitude), 16.0);
            } catch (_) {}
          }
        });
      }

      // 4. بدء تتبع الإحداثيات المباشر (Active GPS Stream)
      _startPositionStream();

      // 5. محاولة جلب أحدث بيانات الفرع والجدول والبصمات من Supabase بشكل متوازي
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      try {
        final List<Future<dynamic>> parallelQueries = [
          SupabaseService.client
              .from('employees')
              .select('branch_id, department_id, branches(id, name, latitude, longitude, radius_meters)')
              .eq('id', user.id)
              .maybeSingle(),
          SupabaseService.client
              .from('attendance')
              .select()
              .eq('employee_id', user.id)
              .eq('work_date', todayStr)
              .maybeSingle(),
        ];

        final results = await Future.wait(parallelQueries);
        final empData = results[0];
        final attendanceData = results[1];

        if (empData != null && empData['branches'] != null) {
          final branch = empData['branches'];
          _branchId = branch['id'];
          _branchName = branch['name'] ?? 'فرع الشركة';
          _branchLat = (branch['latitude'] as num).toDouble();
          _branchLng = (branch['longitude'] as num).toDouble();
          _branchRadius = (branch['radius_meters'] as num).toDouble();

          final List<String> orFilters = ['employee_id.eq.${user.id}'];
          if (empData['department_id'] != null) {
            orFilters.add('department_id.eq.${empData['department_id']}');
          }
          if (empData['branch_id'] != null) {
            orFilters.add('branch_id.eq.${empData['branch_id']}');
          }

          final schedData = await SupabaseService.client
              .from('work_schedules')
              .select()
              .or(orFilters.join(','))
              .limit(1)
              .maybeSingle();

          _workSchedule = schedData;

          // تحديث الكاش المحلي
          await AttendanceSyncService.cacheBranchAndSchedule(
            branchData: Map<String, dynamic>.from(branch),
            scheduleData: schedData,
          );
        }

        _todayAttendance = attendanceData;
        AttendanceSyncService.syncOfflinePunches();

      } catch (networkError) {
        debugPrint('⚠️ وضع الأوفلاين نشط: $networkError');
      }

      // 6. دمج البصمات المحلية المعلقة في طابور التزامن
      final offlinePunches = await AttendanceSyncService.getOfflinePunchesQueue();
      final todayOfflinePunches = offlinePunches.where((p) => p['work_date'] == todayStr).toList();
      
      Map<String, dynamic> combinedAttendance = _todayAttendance != null 
          ? Map<String, dynamic>.from(_todayAttendance!) 
          : {};

      for (var punch in todayOfflinePunches) {
        if (punch['type'] == 'check_in') {
          combinedAttendance['check_in_time'] = punch['time'];
          combinedAttendance['check_in_lat'] = punch['latitude'];
          combinedAttendance['check_in_lng'] = punch['longitude'];
          combinedAttendance['status'] = punch['status'];
        } else if (punch['type'] == 'check_out') {
          combinedAttendance['check_out_time'] = punch['time'];
          combinedAttendance['check_out_lat'] = punch['latitude'];
          combinedAttendance['check_out_lng'] = punch['longitude'];
          combinedAttendance['status'] = punch['status'];
        }
      }

      if (mounted) {
        setState(() {
          if (combinedAttendance.isNotEmpty) {
            _todayAttendance = combinedAttendance;
            if (combinedAttendance['check_in_time'] != null && combinedAttendance['check_out_time'] == null) {
              _selectedPunchType = 'check_out';
            } else {
              _selectedPunchType = 'check_in';
            }
          } else {
            _todayAttendance = null;
            _selectedPunchType = 'check_in';
          }

          if (_currentPosition != null) {
            _distanceToBranch = Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              _branchLat,
              _branchLng,
            );
          }
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception:', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  // إجراء عملية البصمة (حضور أو انصراف) - فوري وفائق السرعة دون أي تأخير شبكة مصطنع
  Future<void> _handleAttendanceSubmit() async {
    if (_currentPosition == null || _branchId == null || _mockDetected) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      // 1. حساب المسافة الجغرافية الفاصلة بين الموظف وحدود الفرع (محلياً)
      double distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _branchLat,
        _branchLng,
      );

      if (distanceInMeters > _branchRadius) {
        final double outOfRange = distanceInMeters - _branchRadius;
        throw Exception('أنت خارج نطاق الفرع الجغرافي المسموح به للتبصيم. المتبقي لتصل للفرع: ${outOfRange.toStringAsFixed(1)} متر.');
      }

      // التوقيت المباشر الدقيق
      final now = DateTime.now();
      final String todayStr = now.toIso8601String().split('T')[0];
      final String nowUtcStr = now.toUtc().toIso8601String();

      // تحديد حالة البصمة (حاضر/متأخر/خروج مبكر) محلياً بناءً على الجدول المتاح
      final status = _selectedPunchType == 'check_in' 
          ? _determineAttendanceStatus() 
          : _determineCheckOutStatus(_todayAttendance?['status'] ?? 'present');

      bool isSynced = true;

      try {
        if (_selectedPunchType == 'check_in') {
          // فحص ما إذا كان قد سجّل حضور بالفعل
          if (_todayAttendance != null && _todayAttendance!['check_in_time'] != null) {
            throw Exception('لقد قمت بتسجيل بصمة الحضور مسبقاً لهذا اليوم!');
          }
          
          if (_todayAttendance != null) {
            // يوجد سطر (مثلاً تبصم انصراف أولاً بالخطأ)، نقوم بتحديث الحضور فيه
            await SupabaseService.client.from('attendance').update({
              'check_in_time': nowUtcStr,
              'check_in_lat': _currentPosition!.latitude,
              'check_in_lng': _currentPosition!.longitude,
              'status': status,
            }).eq('employee_id', user.id).eq('work_date', todayStr);
          } else {
            // سطر جديد بالكامل
            await SupabaseService.client.from('attendance').insert({
              'employee_id': user.id,
              'branch_id': _branchId,
              'check_in_time': nowUtcStr,
              'check_in_lat': _currentPosition!.latitude,
              'check_in_lng': _currentPosition!.longitude,
              'status': status,
              'work_date': todayStr,
            });
          }

          // تسجيل نقطة انطلاق التتبع في جدول location_tracking
          try {
            await SupabaseService.client.from('location_tracking').insert({
              'employee_id': user.id,
              'latitude': _currentPosition!.latitude,
              'longitude': _currentPosition!.longitude,
              'battery_level': 100,
              'is_moving': false,
              'timestamp': nowUtcStr,
            });
          } catch (_) {}

          // تسجيل إشعار بنجاح الحضور في السيرفر
          try {
            await SupabaseService.client.from('notifications').insert({
              'employee_id': user.id,
              'title': 'بصمة حضور ناجحة 🟢',
              'body': 'تم تسجيل حضورك اليوم بنجاح في فرع ($_branchName). دواماً موفقاً!',
              'type': 'attendance',
            });
          } catch (_) {}
        } else {
          // تسجيل انصراف
          if (_todayAttendance != null && _todayAttendance!['check_out_time'] != null) {
            throw Exception('لقد قمت بتسجيل بصمة الانصراف مسبقاً لهذا اليوم!');
          }

          if (_todayAttendance == null) {
            // لم يبصم حضور اليوم! ننشئ بصمة انصراف مع Missed Check-in ونوع دوام نصف يوم
            await SupabaseService.client.from('attendance').insert({
              'employee_id': user.id,
              'branch_id': _branchId,
              'check_out_time': nowUtcStr,
              'check_out_lat': _currentPosition!.latitude,
              'check_out_lng': _currentPosition!.longitude,
              'status': 'half_day',
              'work_date': todayStr,
            });
          } else {
            // تحديث بصمة الانصراف
            await SupabaseService.client.from('attendance').update({
              'check_out_time': nowUtcStr,
              'check_out_lat': _currentPosition!.latitude,
              'check_out_lng': _currentPosition!.longitude,
              'status': status,
            }).eq('employee_id', user.id).eq('work_date', todayStr);
          }

          // تسجيل نقطة الانصراف في جدول location_tracking
          try {
            await SupabaseService.client.from('location_tracking').insert({
              'employee_id': user.id,
              'latitude': _currentPosition!.latitude,
              'longitude': _currentPosition!.longitude,
              'battery_level': 100,
              'is_moving': false,
              'timestamp': nowUtcStr,
            });
          } catch (_) {}

          // تسجيل إشعار بنجاح الانصراف في السيرفر
          try {
            await SupabaseService.client.from('notifications').insert({
              'employee_id': user.id,
              'title': 'بصمة انصراف ناجحة 🔴',
              'body': 'تم تسجيل انصرافك بنجاح من فرع ($_branchName). يعطيك العافية!',
              'type': 'attendance',
            });
          } catch (_) {}
        }
      } catch (networkError) {
        debugPrint('⚠️ تعذر الاتصال بالسيرفر لتسجيل البصمة. سيتم حفظها محلياً: $networkError');
        
        // التحقق الإضافي لمنع تكرار البصمة محلياً
        if (_selectedPunchType == 'check_in' && _todayAttendance != null && _todayAttendance!['check_in_time'] != null) {
          throw Exception('لقد قمت بتسجيل بصمة الحضور مسبقاً لهذا اليوم (محلياً)!');
        }
        if (_selectedPunchType == 'check_out' && _todayAttendance != null && _todayAttendance!['check_out_time'] != null) {
          throw Exception('لقد قمت بتسجيل بصمة الانصراف مسبقاً لهذا اليوم (محلياً)!');
        }

        isSynced = false;

        // حفظ البصمة في طابور الانتظار المحلي
        final punchData = {
          'employee_id': user.id,
          'branch_id': _branchId,
          'work_date': todayStr,
          'type': _selectedPunchType,
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
          'time': nowUtcStr,
          'status': status,
        };
        await AttendanceSyncService.queueOfflinePunch(punchData);
      }

      // تشغيل التتبع الجغرافي عند الحضور أو إيقافه عند الانصراف فوراً
      if (_selectedPunchType == 'check_in') {
        LocationService.recordInstantLocation(
          employeeId: user.id,
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
        );
        LocationService.startTracking(employeeId: user.id);
      } else {
        LocationService.recordInstantLocation(
          employeeId: user.id,
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
        );
        LocationService.stopTracking();
      }

      // إظهار حوار النجاح (مع توضيح حالة الحفظ المحلي إن كان أوفلاين)
      if (mounted) {
        _showSuccessDialog(_selectedPunchType == 'check_in', isSynced);
      }

      // تحديث البيانات بعد البصمة
      _initLocationAndBranch();

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception:', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // تحديد حالة الدخول (مثال: متأخر أو حاضر طبقاً لدوام الشركة)
  String _determineAttendanceStatus() {
    final now = DateTime.now();
    if (_workSchedule != null && _workSchedule!['check_in_time'] != null) {
      try {
        final timeStr = _workSchedule!['check_in_time'] as String;
        final parts = timeStr.split(':');
        final int schedHour = int.parse(parts[0]);
        final int schedMin = int.parse(parts[1]);
        final int grace = _workSchedule!['grace_period_minutes'] ?? 15;
        
        final deadline = DateTime(now.year, now.month, now.day, schedHour, schedMin).add(Duration(minutes: grace));
        if (now.isAfter(deadline)) {
          return 'late';
        }
        return 'present';
      } catch (e) {
        debugPrint('خطأ في تحليل موعد الحضور: $e');
      }
    }
    // افتراضاً: الدوام يبدأ الساعة 08:30 صباحاً
    final checkInDeadline = DateTime(now.year, now.month, now.day, 8, 45); // 15 دقيقة فترة سماح
    if (now.isAfter(checkInDeadline)) {
      return 'late';
    }
    return 'present';
  }

  // تحديد خروج مبكر (يُعتبر نصف يوم)
  String _determineCheckOutStatus(String currentStatus) {
    final now = DateTime.now();
    if (_workSchedule != null && _workSchedule!['check_out_time'] != null) {
      try {
        final timeStr = _workSchedule!['check_out_time'] as String;
        final parts = timeStr.split(':');
        final int schedHour = int.parse(parts[0]);
        final int schedMin = int.parse(parts[1]);
        
        final scheduledCheckout = DateTime(now.year, now.month, now.day, schedHour, schedMin);
        
        // خروج مبكر بأكثر من 15 دقيقة يعتبر نصف يوم
        if (now.isBefore(scheduledCheckout.subtract(const Duration(minutes: 15)))) {
          return 'half_day';
        }
        return currentStatus;
      } catch (e) {
        debugPrint('خطأ في تحليل موعد الانصراف: $e');
      }
    }
    // افتراضاً: الانصراف الساعة 16:30 مساءً (4:30)
    final checkOutTime = DateTime(now.year, now.month, now.day, 16, 30);
    if (now.isBefore(checkOutTime.subtract(const Duration(minutes: 15)))) {
      return 'half_day';
    }
    return currentStatus;
  }

  void _showSuccessDialog(bool isCheckIn, bool isSynced) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: (isSynced ? AppTheme.successGreen : AppTheme.warningOrange).withValues(alpha: 0.3), width: 1.5),
          ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: (isSynced ? AppTheme.successGreen : AppTheme.warningOrange).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: isSynced ? AppTheme.successGreen : AppTheme.warningOrange, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: (isSynced ? AppTheme.successGreen : AppTheme.warningOrange).withValues(alpha: 0.3),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Icon(
                    isSynced ? Icons.check_circle_outline_rounded : Icons.cloud_off_rounded,
                    color: isSynced ? AppTheme.successGreen : AppTheme.warningOrange,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isCheckIn ? 'تم تسجيل حضورك اليوم بنجاح!' : 'تم تسجيل انصرافك بنجاح!',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo', color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  isSynced
                      ? 'نتمنى لك يوماً رائعاً ودواماً موفقاً مع عائلة شركتكم الموقرة.'
                      : 'تم حفظ بصمتك محلياً بنجاح (بسبب انقطاع الإنترنت). سيتم رفعها تلقائياً فور عودة الاتصال.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12, 
                    color: isSynced ? Colors.white70 : AppTheme.warningOrange, 
                    fontWeight: isSynced ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo'
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: isSynced 
                          ? AppTheme.cyberGradient 
                          : const LinearGradient(colors: [AppTheme.warningOrange, Colors.orange]),
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      child: const Text('موافق', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

  @override
  Widget build(BuildContext context) {
    final hasCheckIn = _todayAttendance != null && _todayAttendance!['check_in_time'] != null;
    final hasCheckOut = _todayAttendance != null && _todayAttendance!['check_out_time'] != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'تسجيل الدوام الجغرافي',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location_rounded, color: AppTheme.neonCyan),
            onPressed: _initLocationAndBranch,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. خريطة الفرع والموظف التفاعلية (Leaflet / OSM Map)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(_branchLat, _branchLng),
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.hrpro.app',
              ),
              // سياج الفرع الجغرافي (Geofence Circle)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(_branchLat, _branchLng),
                    color: AppTheme.neonCyan.withValues(alpha: 0.15),
                    borderStrokeWidth: 2,
                    borderColor: AppTheme.neonCyan,
                    useRadiusInMeter: true,
                    radius: _branchRadius,
                  ),
                ],
              ),
              // علامات الموقع (الموظف + الفرع)
              MarkerLayer(
                markers: [
                  // علامة الفرع المعتمد
                  Marker(
                    point: LatLng(_branchLat, _branchLng),
                    width: 60,
                    height: 60,
                    child: Tooltip(
                      message: _branchName,
                      child: Column(
                        children: [
                          const Icon(Icons.business_center, color: AppTheme.neonCyan, size: 36),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.neonCyan, width: 1),
                            ),
                            child: Text(
                              _branchName.length > 10 ? '${_branchName.substring(0, 9)}..' : _branchName,
                              style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // علامة الموظف الجغرافية
                  if (_currentPosition != null)
                    Marker(
                      point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.person_pin_circle_rounded,
                        color: AppTheme.neonPink,
                        size: 42,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 1.5 لافتة معلوماتية بحدود زجاجية جذابة لتوضيح تتبع الموقع للموظف
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              borderRadius: 16,
              opacity: 0.2,
              borderColor: AppTheme.neonCyan.withValues(alpha: 0.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                )
              ],
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppTheme.neonCyan, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'يتم استخدام الموقع لتأكيد التواجد ضمن الفروع المعتمدة ولأغراض إثبات الحضور والانصراف الذكي تلقائياً أثناء ساعات العمل الرسمية فقط.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 10.5,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // زر إعادة تمركز وتحديث الـ GPS الفوري عالي الدقة
          Positioned(
            bottom: 275,
            left: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _refreshGpsLocation(userInitiated: true),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.5), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.neonCyan.withValues(alpha: 0.2),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.my_location_rounded, color: AppTheme.neonCyan, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'تحديث الموقع 📍',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. لوحة التحكم السفلية المتميزة بتقنية الزجاج
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: GlassContainer(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              borderRadius: 28,
              opacity: 0.15,
              borderColor: AppTheme.neonCyan.withValues(alpha: 0.3),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.neonCyan.withValues(alpha: 0.08),
                  blurRadius: 24,
                  spreadRadius: 2,
                )
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLocating) ...[
                    const CircularProgressIndicator(color: AppTheme.neonCyan),
                    const SizedBox(height: 12),
                    const Text(
                      'جاري التحقق من الموقع الجغرافي والإحداثيات الفورية...',
                      style: TextStyle(fontSize: 12, color: Colors.white70, fontFamily: 'Cairo'),
                    ),
                  ] else ...[
                    // إظهار رسالة الخطأ أو التحذير إن وجد مع زر إعادة المحاولة
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.dangerRed.withAlpha(20),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.dangerRed.withAlpha(50)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: AppTheme.dangerRed, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: AppTheme.dangerRed, 
                                      fontSize: 11.5, 
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _initLocationAndBranch,
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text(
                                  'إعادة محاولة جلب الموقع', 
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.dangerRed,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_workSchedule != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.neonPink.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.neonPink.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_filled_rounded, color: AppTheme.neonPink, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'أوقات الدوام المعتمدة للفرع',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo'),
                                  ),
                                  Text(
                                    'الدخول: ${_formatTimeString12Hr(_workSchedule!['check_in_time']?.toString())} | الخروج: ${_formatTimeString12Hr(_workSchedule!['check_out_time']?.toString())}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Cairo'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // حالة دوام الموظف التفصيلية لليوم
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'الحالة: ${hasCheckOut ? "مكتمل 🟢" : (hasCheckIn ? "دوام نشط 🟡" : "لم تبصم بعد 🔴")}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo'),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'الموقع المعتمد: $_branchName',
                                style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'Cairo'),
                              ),
                              if (_currentPosition != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.my_location_rounded,
                                      size: 12,
                                      color: _distanceToBranch != null && _distanceToBranch! <= _branchRadius
                                          ? AppTheme.successGreen
                                          : AppTheme.neonPink,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _distanceToBranch != null
                                            ? 'تبعد عن الفرع: ${_distanceToBranch!.toStringAsFixed(1)} م (دقة الموقع: ${_currentPosition!.accuracy.toStringAsFixed(1)} م)'
                                            : 'دقة الموقع الحالية: ${_currentPosition!.accuracy.toStringAsFixed(1)} م',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                          color: _distanceToBranch != null && _distanceToBranch! <= _branchRadius
                                              ? AppTheme.successGreen
                                              : AppTheme.neonPink,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (hasCheckIn)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.successGreen.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: AppTheme.successGreen, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  _formatTime(_todayAttendance?['check_in_time']),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.successGreen, fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (!hasCheckOut)
                      _buildPunchTypeSwitch(),

                    // زر التبصيم الفخم بلمسات مضيئة في الوسط
                    if (!hasCheckOut)
                      GestureDetector(
                        onTap: _isSubmitting || _mockDetected ? null : _handleAttendanceSubmit,
                        child: ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _selectedPunchType == 'check_out' 
                                  ? const LinearGradient(colors: [AppTheme.neonPink, AppTheme.dangerRed])
                                  : AppTheme.cyberGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: (_selectedPunchType == 'check_out' ? AppTheme.neonPink : AppTheme.neonCyan).withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                )
                              ],
                            ),
                            child: Center(
                              child: _isSubmitting
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : Icon(
                                      _selectedPunchType == 'check_out' ? Icons.exit_to_app_rounded : Icons.fingerprint_rounded,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    
                    if (hasCheckOut)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.successGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.successGreen.withValues(alpha: 0.3)),
                        ),
                        child: const Center(
                          child: Text(
                            'لقد أتممت بصمة حضور وانصراف هذا اليوم. دوام موفق! 🎉',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.successGreen, fontFamily: 'Cairo'),
                          ),
                        ),
                      ),
                    
                    const SizedBox(height: 12),
                    if (!hasCheckOut)
                      Text(
                        _selectedPunchType == 'check_out' ? 'اضغط لتسجيل بصمة الانصراف 🔴' : 'اضغط لتسجيل بصمة الحضور 🟢',
                        style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600, fontFamily: 'Cairo'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPunchTypeSwitch() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          // حضور tab
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPunchType = 'check_in';
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _selectedPunchType == 'check_in'
                      ? AppTheme.neonCyan.withValues(alpha: 0.2)
                      : Colors.transparent,
                  border: Border.all(
                    color: _selectedPunchType == 'check_in'
                        ? AppTheme.neonCyan.withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.login_rounded,
                      size: 16,
                      color: _selectedPunchType == 'check_in'
                          ? AppTheme.neonCyan
                          : Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'تسجيل حضور',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _selectedPunchType == 'check_in'
                            ? Colors.white
                            : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // انصراف tab
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPunchType = 'check_out';
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _selectedPunchType == 'check_out'
                      ? AppTheme.neonPink.withValues(alpha: 0.2)
                      : Colors.transparent,
                  border: Border.all(
                    color: _selectedPunchType == 'check_out'
                        ? AppTheme.neonPink.withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 16,
                      color: _selectedPunchType == 'check_out'
                          ? AppTheme.neonPink
                          : Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'تسجيل انصراف',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _selectedPunchType == 'check_out'
                            ? Colors.white
                            : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

  String _formatTimeString12Hr(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '--:--';
    try {
      final parts = timeStr.split(':');
      int hour = int.parse(parts[0]);
      final minute = parts[1];
      final amPm = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute $amPm';
    } catch (e) {
      return timeStr.length > 5 ? timeStr.substring(0, 5) : timeStr;
    }
  }
}

