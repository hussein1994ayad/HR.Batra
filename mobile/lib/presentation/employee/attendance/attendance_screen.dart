// =========================================================================
// HR Pro — بصمة الدوام: الخريطة، النطاق الجغرافي، وتسجيل الحضور/الانصراف
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/services/attendance_sync_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/precise_location.dart';
import '../../../core/services/schedule_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/utils/company_time.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../shared/ui/ui.dart';
import 'attendance_logic.dart';
import 'widgets/attendance_history_card.dart';
import 'widgets/attendance_widgets.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
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
  bool _preciseDenied = false;
  String? _errorMessage;
  Map<String, dynamic>? _todayAttendance;
  Map<String, dynamic>? _workSchedule;

  final MapController _mapController = MapController();
  final AttendanceRepository _repo = AttendanceRepository();
  StreamSubscription<Position>? _positionStreamSubscription;

  @override
  void initState() {
    super.initState();
    _initLocationAndBranch();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  // بدء الاستماع المباشر والمستمر للموقع الجغرافي لتحديث الإحداثيات فورياً دون تأخير
  void _startPositionStream() {
    _positionStreamSubscription?.cancel();
    const locationSettings = LocationSettings(
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
          _distanceToBranch = _distanceFromBranch(position);
          // رسالة "خارج النطاق" القديمة تختفي أول ما يدخل الموظف النطاق
          if (_inRange && (_errorMessage?.contains(attendanceOutOfRangeMessage) ?? false)) _errorMessage = null;
        });
      },
      onError: (dynamic e) {
        appLog('GPS Stream Error: $e');
      },
    );
  }

  // إعادة تحديث الموقع الجغرافي يدوياً أو تلقائياً بسرعة فائقة
  Future<void> _refreshGpsLocation({bool userInitiated = false}) async {
    if (userInitiated) {
      AppSnack.info(context, 'جاري تحديث موقعك...');
    }

    try {
      final freshPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          
        ),
      ).timeout(const Duration(seconds: 3));

      if (mounted) {
        setState(() {
          _currentPosition = freshPos;
          _isLocating = false;
          _distanceToBranch = _distanceFromBranch(freshPos);
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
          _distanceToBranch = _distanceFromBranch(lastPos);
        });
      }
    }
  }

  /// المسافة بالمتر بين [p] وموقع الفرع.
  double _distanceFromBranch(Position p) => Geolocator.distanceBetween(p.latitude, p.longitude, _branchLat, _branchLng);

  /// موقع الفرع ونطاقه (من الكاش أو من السيرفر).
  void _applyBranch(Map<String, dynamic> branch) {
    _branchId = branch['id'] as String?;
    _branchName = (branch['name'] ?? 'فرع الشركة') as String;
    _branchLat = (branch['latitude'] as num).toDouble();
    _branchLng = (branch['longitude'] as num).toDouble();
    _branchRadius = (branch['radius_meters'] as num).toDouble();
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
        final branch = Map<String, dynamic>.from(cached['branch'] as Map);
        _applyBranch(branch);
        _workSchedule = cached['schedule'] as Map<String, dynamic>?;
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

      // الموقع الدقيق مطلوب: أندرويد 12+ وiOS 14+ يسمحون بموقع تقريبي يبعد كيلومترات
      _preciseDenied = !await PreciseLocation.ensure();
      if (_preciseDenied) throw Exception(PreciseLocation.reducedMessage);

      // 3. المرحلة الأولى الفورية (Fast-Path): قراءة آخر موقع معروف في أقل من 20ms لتجهيز الشاشة فوراً
      Position? initialPosition = await Geolocator.getLastKnownPosition();
      if (initialPosition != null && mounted) {
        setState(() {
          _currentPosition = initialPosition;
          _isLocating = false;
          _distanceToBranch = _distanceFromBranch(initialPosition);
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
      final todayStr = companyDateStr();
      String? syncWarning;
      try {
        // رفع البصمات المحفوظة أوفلاين أولاً حتى تظهر حالة اليوم الصحيحة
        final rejectedPunches = await AttendanceSyncService.syncOfflinePunches();
        if (rejectedPunches.isNotEmpty) {
          syncWarning = rejectedPunches.first.message ??
              'تعذر اعتماد بصمة محفوظة بدون إنترنت. راجع الإدارة.';
        }

        final List<Future<dynamic>> parallelQueries = [
          _repo.fetchEmployeeBranch(user.id),
          _repo.fetchTodayAttendance(user.id, todayStr),
        ];

        final results = await Future.wait(parallelQueries);
        final empData = results[0] as Map<String, dynamic>?;
        final attendanceData = results[1];

        if (empData != null && empData['branches'] != null) {
          final branch = Map<String, dynamic>.from(empData['branches'] as Map);
          _applyBranch(branch);

          final schedData = await ScheduleService.fetchEffectiveSchedule();

          _workSchedule = schedData;

          // تحديث الكاش المحلي
          await AttendanceSyncService.cacheBranchAndSchedule(
            branchData: branch,
            scheduleData: schedData,
          );
        }

        _todayAttendance = attendanceData as Map<String, dynamic>?;

      } catch (networkError) {
        appLog(' وضع الأوفلاين نشط: $networkError');
      }

      // 6. دمج البصمات المحلية المعلقة في طابور التزامن
      final offlinePunches = await AttendanceSyncService.getOfflinePunchesQueue();
      final combinedAttendance = mergeTodayOfflinePunches(
        serverToday: _todayAttendance,
        offlineQueue: offlinePunches,
        userId: SupabaseService.currentUser?.id,
        todayStr: todayStr,
      );

      if (mounted) {
        setState(() {
          if (syncWarning != null) _errorMessage = syncWarning;
          if (combinedAttendance.isNotEmpty) {
            _todayAttendance = combinedAttendance;
            _selectedPunchType = nextPunchType(combinedAttendance);
          } else {
            _todayAttendance = null;
            _selectedPunchType = 'check_in';
          }

          if (_currentPosition != null) {
            _distanceToBranch = _distanceFromBranch(_currentPosition!);
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

  // إجراء عملية البصمة (حضور أو انصراف). السيرفر يحسب الوقت والمسافة والحالة؛
  // الفحوصات المحلية هنا فقط لإظهار رسالة فورية قبل الإرسال.
  Future<void> _handleAttendanceSubmit() async {
    if (_currentPosition == null || _branchId == null || _mockDetected) return;

    // الانصراف قبل نهاية الدوام يُسجَّل خروجاً مبكراً (خصم بانتظار قرار الإدارة) — نأكد أولاً
    if (_selectedPunchType == 'check_out') {
      final early = _punchNote(false);
      if (early != null) {
        final ok = await showAppConfirm(
          context,
          title: 'انصراف قبل نهاية الدوام؟',
          message: '$early، ويُسجَّل خروجاً مبكراً تقرر عليه الإدارة.',
          confirmLabel: 'تسجيل الانصراف',
        );
        if (!ok || !mounted) return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final user = SupabaseService.currentUser;
    if (user == null) return;
    final punchType = _selectedPunchType;
    final position = _currentPosition!;

    try {
      final double distanceInMeters = _distanceFromBranch(position);
      final localError = localPunchError(
        punchType: punchType,
        accuracy: position.accuracy,
        distanceMeters: distanceInMeters,
        branchRadius: _branchRadius,
        today: _todayAttendance,
      );
      if (localError != null) throw Exception(localError);

      final result = await AttendanceSyncService.punch(
        type: punchType,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        isMocked: position.isMocked,
      );
      if (!result.ok) {
        throw Exception(result.message ?? 'تعذر تسجيل البصمة، حاول مرة أخرى.');
      }

      // تشغيل التتبع الجغرافي عند الحضور أو إيقافه عند الانصراف
      if (punchType == 'check_in') {
        unawaited(LocationService.startTracking(employeeId: user.id));
      } else {
        unawaited(LocationService.stopTracking());
      }

      if (mounted) {
        _showSuccessDialog(punchType == 'check_in', !result.queued);
      }

      unawaited(_initLocationAndBranch());
    } on PostgrestException catch (e) {
      // رفض صريح من السيرفر (جهاز غير معتمد، حساب معطل...)
      if (mounted) setState(() => _errorMessage = e.message);
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


  void _showSuccessDialog(bool isCheckIn, bool isSynced) {
    if (isSynced) {
      AppHaptics.success();
    } else {
      AppHaptics.submit();
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => PunchSuccessDialog(isCheckIn: isCheckIn, isSynced: isSynced, note: _punchNote(isCheckIn)),
    );
  }

  String? _punchNote(bool isCheckIn) => punchNote(isCheckIn: isCheckIn, schedule: _workSchedule, now: DateTime.now());

  bool get _hasCheckOut => _todayAttendance?['check_out_time'] != null;
  bool get _inRange => _distanceToBranch != null && _distanceToBranch! <= _branchRadius;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscapeWide = size.width >= AppBreakpoints.medium && size.width > size.height;
    final map = ClipRRect(
      borderRadius: landscapeWide ? AppRadius.card : BorderRadius.zero,
      child: RepaintBoundary(
        child: AttendanceBranchMap(
          mapController: _mapController,
          branchLat: _branchLat,
          branchLng: _branchLng,
          branchRadius: _branchRadius,
          branchName: _branchName,
          currentPosition: _currentPosition,
        ),
      ),
    );
    final panel = _buildPanel();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('بصمة الدوام'),
        actions: [
          IconButton(
            tooltip: 'تحديث الموقع',
            icon: const Icon(Icons.my_location_rounded),
            onPressed: () => _refreshGpsLocation(userInitiated: true),
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: landscapeWide
          ? Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: map),
                  const SizedBox(width: AppSpace.lg),
                  SizedBox(width: 400, child: SingleChildScrollView(child: panel)),
                ],
              ),
            )
          : RefreshIndicator.adaptive(
              onRefresh: _initLocationAndBranch,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  SizedBox(height: (size.height * 0.34).clamp(200.0, 380.0), child: map),
                  ContentWidth(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.lg, AppSpace.page, AppSpace.x3),
                      child: panel,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPanel() {
    if (_isLocating) {
      return const AttendancePanelSkeleton();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AttendanceLocationCard(
          branchName: _branchName,
          branchRadius: _branchRadius,
          currentPosition: _currentPosition,
          distanceToBranch: _distanceToBranch,
          inRange: _inRange,
          mockDetected: _mockDetected,
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpace.md),
          AttendanceErrorCard(message: _errorMessage!, preciseDenied: _preciseDenied, onRetry: _initLocationAndBranch),
        ],
        const SizedBox(height: AppSpace.lg),
        if (_hasCheckOut)
          const AttendanceDayCompleteCard()
        else
          AttendancePunchControls(
            selectedType: _selectedPunchType,
            onTypeChanged: (t) => setState(() => _selectedPunchType = t),
            submitting: _isSubmitting,
            mockDetected: _mockDetected,
            hasPosition: _currentPosition != null,
            inRange: _inRange,
            onSubmit: _handleAttendanceSubmit,
          ),
        const SizedBox(height: AppSpace.lg),
        AttendanceTodayCard(todayAttendance: _todayAttendance, workSchedule: _workSchedule),
        const SizedBox(height: AppSpace.lg),
        const AttendanceHistoryCard(),
        const SizedBox(height: AppSpace.lg),
        const AttendancePrivacyNote(),
      ],
    );
  }
}
