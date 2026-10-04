// =========================================================================
// HR Pro — التتبع الحي للمدراء
// =========================================================================
// خريطة بملء الشاشة + قائمة سفلية قابلة للسحب (على التابلت الأفقي: قائمة
// جانبية). الحالة: داخل الفرع / خارج النطاق / انصراف / لم يبصم. اختيار موظف
// يعرض بطاقته ومسار تحركاته. تحديث لحظي (Realtime) + كل 15 ثانية احتياطاً.
// المنطق: core/logic/tracking_rules.dart
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/logic/tracking_rules.dart';
import '../../../core/models/models.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_log.dart';
import '../../../data/repositories/live_tracking_repository.dart';
import '../../../data/repositories/role_repository.dart';
import '../../shared/ui/ui.dart';
import 'widgets/live_tracking_widgets.dart';

class AdminLiveTrackingScreen extends StatefulWidget {
  const AdminLiveTrackingScreen({super.key});

  @override
  State<AdminLiveTrackingScreen> createState() => _AdminLiveTrackingScreenState();
}

class _AdminLiveTrackingScreenState extends State<AdminLiveTrackingScreen> {
  final LiveTrackingRepository _repo = LiveTrackingRepository();
  final MapController _mapController = MapController();
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _autoRefreshEnabled = true;
  Timer? _autoRefreshTimer;
  RealtimeChannel? _trackingChannel;

  DateTime _selectedDate = DateTime.now();
  String _selectedBranchId = 'all';
  TrackStatus? _statusFilter;
  String _searchQuery = '';

  List<BranchModel> _branchesList = [];
  List<Map<String, dynamic>> _employeesList = [];
  List<Map<String, dynamic>> _attendanceList = [];
  List<Map<String, dynamic>> _locationTrackingList = [];
  List<TrackedEmployee> _tracked = [];

  String? _focusedId;
  bool _showTrail = true;
  LatLng _mapCenter = const LatLng(33.3152, 44.3661);

  @override
  void initState() {
    super.initState();
    _loadAllTrackingData();

    // تحديث احتياطي كل 15 ثانية
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_autoRefreshEnabled && mounted && !_isRefreshing) _refreshLocationsSilently();
    });

    // تحديث لحظي عند أي حركة أو بصمة
    try {
      _trackingChannel = _repo.subscribe(() {
        if (mounted && !_isRefreshing && _autoRefreshEnabled) _refreshLocationsSilently();
      });
    } catch (e) {
      appLog('تعذر بدء اشتراك Realtime للتتبع: $e');
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    try {
      if (_trackingChannel != null) _repo.removeChannel(_trackingChannel!);
    } catch (_) {}
    super.dispose();
  }

  (String date, String start, String end) get _dayRange {
    final d = _selectedDate;
    return (
      DateFormat('yyyy-MM-dd').format(d),
      DateTime(d.year, d.month, d.day).toUtc().toIso8601String(),
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999).toUtc().toIso8601String(),
    );
  }

  Future<List<dynamic>> _fetchDay() {
    final (dateStr, start, end) = _dayRange;
    return _repo.fetchDay(date: dateStr, start: start, end: end);
  }

  Future<void> _loadAllTrackingData() async {
    if (!mounted) return;
    setState(() => _isRefreshing = true);

    final user = SupabaseService.currentUser;
    if (user == null) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    try {
      if (!await RoleRepository().isAdminOrManager()) {
        if (mounted) {
          AppSnack.error(context, 'هذه الشاشة للإدارة فقط');
          context.go(AppRoutes.employeeHome);
        }
        return;
      }

      final results = await Future.wait<dynamic>([
        _repo.fetchBranches(),
        _repo.fetchActiveEmployees(),
        _fetchDay(),
      ]);

      _branchesList = results[0] as List<BranchModel>;
      _employeesList = List<Map<String, dynamic>>.from(results[1] as Iterable<dynamic>);
      final day = results[2] as List<dynamic>;
      _attendanceList = List<Map<String, dynamic>>.from(day[0] as Iterable<dynamic>);
      _locationTrackingList = List<Map<String, dynamic>>.from(day[1] as Iterable<dynamic>);
      _process();
      _centerMapOnSelectedBranch();
    } catch (e) {
      appLog('خطأ في تحميل بيانات التتبع: $e');
      if (mounted) AppSnack.error(context, 'تعذّر تحميل بيانات التتبع');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  /// تحديث صامت للمواقع بدون وميض.
  Future<void> _refreshLocationsSilently() async {
    try {
      final day = await _fetchDay();
      if (!mounted) return;
      _attendanceList = List<Map<String, dynamic>>.from(day[0] as Iterable<dynamic>);
      _locationTrackingList = List<Map<String, dynamic>>.from(day[1] as Iterable<dynamic>);
      setState(_process);
    } catch (_) {}
  }

  void _process() {
    _tracked = buildTracking(employees: _employeesList, attendance: _attendanceList, trackingPoints: _locationTrackingList);
  }

  void _centerMapOnSelectedBranch() {
    if (_branchesList.isEmpty) return;
    final b = _selectedBranchId == 'all' ? _branchesList.first : _branchesList.firstWhere((br) => br.id == _selectedBranchId, orElse: () => _branchesList.first);
    final lat = b.latitude;
    final lng = b.longitude;
    if (lat != null && lng != null) {
      _mapCenter = LatLng(lat, lng);
      if (_selectedBranchId != 'all') {
        try {
          _mapController.move(_mapCenter, 14);
        } catch (_) {}
      }
    }
  }

  Iterable<TrackedEmployee> get _inBranch => _tracked.where((t) => _selectedBranchId == 'all' || t.branchId == _selectedBranchId);

  List<TrackedEmployee> get _filtered {
    final q = _searchQuery.trim();
    return _inBranch.where((t) => (_statusFilter == null || t.status == _statusFilter) && (q.isEmpty || t.name.contains(q))).toList();
  }

  TrackedEmployee? get _focused => _focusedId == null ? null : _tracked.where((t) => t.id == _focusedId).firstOrNull;

  void _focus(TrackedEmployee t) {
    if (t.position == null) {
      AppSnack.info(context, 'لا يوجد موقع مسجل لهذا الموظف اليوم');
      return;
    }
    AppHaptics.select();
    setState(() => _focusedId = t.id);
    _mapController.move(t.position!, 15.5);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar'),
      helpText: 'يوم التتبع',
    );
    if (picked != null && !DateUtils.isSameDay(picked, _selectedDate)) {
      setState(() {
        _selectedDate = picked;
        _focusedId = null;
      });
      unawaited(_loadAllTrackingData());
    }
  }

  Future<void> _pickBranch() async {
    final id = await showAppOptions(
      context,
      title: 'الفرع',
      current: _selectedBranchId,
      options: [('all', 'كل الفروع'), for (final b in _branchesList) (b.id, '${b.rawName}')],
    );
    if (id == null) return;
    setState(() {
      _selectedBranchId = id;
      _focusedId = null;
    });
    _centerMapOnSelectedBranch();
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    final branchName = _branchesList.where((b) => b.id == _selectedBranchId).firstOrNull?.rawName;
    final size = MediaQuery.sizeOf(context);
    final sidePanel = size.width >= AppBreakpoints.expanded || (size.width >= AppBreakpoints.medium && size.width > size.height);

    final map = LiveTrackingMap(
      controller: _mapController,
      center: _mapCenter,
      branches: _branchesList.where((b) => _selectedBranchId == 'all' || b.id == _selectedBranchId).toList(),
      employees: _filtered,
      focused: _focused,
      showTrail: _showTrail,
      onTapEmployee: _focus,
    );

    final focusCard = _focused == null
        ? null
        : TrackingFocusCard(
            item: _focused!,
            showTrail: _showTrail,
            onToggleTrail: () => setState(() => _showTrail = !_showTrail),
            onClose: () => setState(() => _focusedId = null),
          );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('التتبع الحي'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _autoRefreshEnabled && isToday ? AppColors.success : AppColors.textDisabled),
                ),
                const SizedBox(width: AppSpace.xs),
                Text(_autoRefreshEnabled && isToday ? 'مباشر' : 'متوقف', style: AppText.caption),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _autoRefreshEnabled ? 'إيقاف التحديث المباشر' : 'تشغيل التحديث المباشر',
            icon: Icon(_autoRefreshEnabled ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded),
            onPressed: () => setState(() => _autoRefreshEnabled = !_autoRefreshEnabled),
          ),
          IconButton(
            tooltip: 'تحديث الآن',
            icon: _isRefreshing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
            onPressed: _isRefreshing ? null : _loadAllTrackingData,
          ),
          const SizedBox(width: AppSpace.xs),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: AppFilterBar(
              children: [
                AppFilterPill(icon: Icons.event_rounded, label: isToday ? 'اليوم' : Fmt.date(_selectedDate, withYear: true), active: !isToday, onTap: _pickDate),
                AppFilterPill(icon: Icons.store_rounded, label: branchName ?? 'كل الفروع', active: _selectedBranchId != 'all', onTap: _pickBranch),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList(header: true))
          : sidePanel
              ? Row(
                  children: [
                    SizedBox(width: 380, child: _buildListPanel(null)),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(child: map),
                          if (focusCard != null) Positioned(top: AppSpace.md, left: AppSpace.md, right: AppSpace.md, child: focusCard),
                        ],
                      ),
                    ),
                  ],
                )
              : Stack(
                  children: [
                    Positioned.fill(child: map),
                    if (focusCard != null) Positioned(top: AppSpace.md, left: AppSpace.md, right: AppSpace.md, child: focusCard),
                    DraggableScrollableSheet(
                      initialChildSize: 0.34,
                      minChildSize: 0.16,
                      maxChildSize: 0.9,
                      snap: true,
                      snapSizes: const [0.16, 0.34, 0.9],
                      builder: (context, scroll) => DecoratedBox(
                        decoration: const BoxDecoration(
                          color: AppColors.surface1,
                          borderRadius: AppRadius.sheet,
                          boxShadow: AppElevation.high,
                        ),
                        child: _buildListPanel(scroll),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildListPanel(ScrollController? scroll) {
    final counts = {for (final s in TrackStatus.values) s: _inBranch.where((t) => t.status == s).length};
    final filtered = _filtered;
    return CustomScrollView(
      controller: scroll,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (scroll != null)
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                    decoration: const BoxDecoration(color: AppColors.borderStrong, borderRadius: AppRadius.pill),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.sm, AppSpace.page, 0),
                child: Row(
                  children: [
                    for (final s in [TrackStatus.inside, TrackStatus.outside, TrackStatus.checkedOut, TrackStatus.absent])
                      Expanded(child: TrackingStatusCounter(status: s, count: counts[s]!, selected: _statusFilter == s, onTap: () => setState(() => _statusFilter = _statusFilter == s ? null : s))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.md, AppSpace.page, AppSpace.sm),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: AppText.body,
                  decoration: const InputDecoration(hintText: 'ابحث باسم الموظف', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                ),
              ),
            ],
          ),
        ),
        if (filtered.isEmpty)
          const SliverToBoxAdapter(child: EmptyView(title: 'لا يوجد موظفون بهذا الفلتر', icon: Icons.person_search_rounded, compact: true))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.x3),
            sliver: SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final t = filtered[i];
                final (tone, label) = trackStatusStyle(t.status);
                final parts = [
                  t.branchName,
                  if (t.checkIn != null) 'حضور ${Fmt.time(t.checkIn)}',
                  if (t.distanceToBranch != null) formatDistance(t.distanceToBranch!),
                ];
                return AppListTile(
                  dense: true,
                  leading: AppAvatar(name: t.name, url: t.employee['avatar_url']?.toString(), size: 40, tone: tone),
                  title: t.name,
                  subtitle: parts.join(' · '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (t.trail.length >= 2) const Padding(padding: EdgeInsetsDirectional.only(end: AppSpace.xs), child: Icon(Icons.route_rounded, size: 18, color: AppColors.brand)),
                      StatusBadge(label, tone: tone, dot: true),
                    ],
                  ),
                  onTap: () => _focus(t),
                );
              },
            ),
          ),
      ],
    );
  }
}
