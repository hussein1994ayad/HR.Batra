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

import '../../core/logic/tracking_rules.dart';
import '../../core/routes/app_router.dart';
import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';

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
  RealtimeChannel? _trackingChannel;

  DateTime _selectedDate = DateTime.now();
  String _selectedBranchId = 'all';
  TrackStatus? _statusFilter;
  String _searchQuery = '';

  List<Map<String, dynamic>> _branchesList = [];
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
      _trackingChannel = SupabaseService.client.channel('live-admin-tracking')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'location_tracking',
          callback: (_) {
            if (mounted && !_isRefreshing && _autoRefreshEnabled) _refreshLocationsSilently();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance',
          callback: (_) {
            if (mounted && !_isRefreshing && _autoRefreshEnabled) _refreshLocationsSilently();
          },
        )
        ..subscribe();
    } catch (e) {
      debugPrint('تعذر بدء اشتراك Realtime للتتبع: $e');
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    try {
      if (_trackingChannel != null) SupabaseService.client.removeChannel(_trackingChannel!);
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
    return Future.wait<dynamic>([
      SupabaseService.client.from('attendance').select().eq('work_date', dateStr),
      SupabaseService.client.from('location_tracking').select().gte('timestamp', start).lte('timestamp', end).order('timestamp', ascending: true),
    ]);
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
      final empRole = await SupabaseService.client.from('employees').select('role').eq('id', user.id).maybeSingle();
      if (empRole == null || (empRole['role'] != 'admin' && empRole['role'] != 'manager')) {
        if (mounted) {
          AppSnack.error(context, 'هذه الشاشة للإدارة فقط');
          context.go(AppRoutes.employeeHome);
        }
        return;
      }

      final results = await Future.wait<dynamic>([
        SupabaseService.client.from('branches').select().order('name'),
        SupabaseService.client
            .from('employees')
            .select('id, full_name, avatar_url, role, branch_id, branches(id, name, latitude, longitude, radius_meters)')
            .eq('is_active', true)
            .order('full_name'),
        _fetchDay(),
      ]);

      _branchesList = List<Map<String, dynamic>>.from(results[0] as Iterable<dynamic>);
      _employeesList = List<Map<String, dynamic>>.from(results[1] as Iterable<dynamic>);
      final day = results[2] as List<dynamic>;
      _attendanceList = List<Map<String, dynamic>>.from(day[0] as Iterable<dynamic>);
      _locationTrackingList = List<Map<String, dynamic>>.from(day[1] as Iterable<dynamic>);
      _process();
      _centerMapOnSelectedBranch();
    } catch (e) {
      debugPrint('خطأ في تحميل بيانات التتبع: $e');
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
    final b = _selectedBranchId == 'all' ? _branchesList.first : _branchesList.firstWhere((br) => br['id'] == _selectedBranchId, orElse: () => _branchesList.first);
    final lat = b['latitude'];
    final lng = b['longitude'];
    if (lat is num && lng is num) {
      _mapCenter = LatLng(lat.toDouble(), lng.toDouble());
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
      options: [('all', 'كل الفروع'), for (final b in _branchesList) (b['id'] as String, b['name'].toString())],
    );
    if (id == null) return;
    setState(() {
      _selectedBranchId = id;
      _focusedId = null;
    });
    _centerMapOnSelectedBranch();
  }

  static (AppTone, String) statusStyle(TrackStatus s) => switch (s) {
        TrackStatus.inside => (AppTone.success, 'داخل الفرع'),
        TrackStatus.outside => (AppTone.danger, 'خارج النطاق'),
        TrackStatus.checkedOut => (AppTone.warning, 'انصراف'),
        TrackStatus.absent => (AppTone.neutral, 'لم يبصم'),
      };

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    final branchName = _branchesList.where((b) => b['id'] == _selectedBranchId).firstOrNull?['name']?.toString();
    final size = MediaQuery.sizeOf(context);
    final sidePanel = size.width >= AppBreakpoints.expanded || (size.width >= AppBreakpoints.medium && size.width > size.height);

    final map = _TrackingMap(
      controller: _mapController,
      center: _mapCenter,
      branches: _branchesList.where((b) => _selectedBranchId == 'all' || b['id'] == _selectedBranchId).toList(),
      employees: _filtered,
      focused: _focused,
      showTrail: _showTrail,
      onTapEmployee: _focus,
    );

    final focusCard = _focused == null
        ? null
        : _FocusCard(
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
                      Expanded(child: _StatusCounter(status: s, count: counts[s]!, selected: _statusFilter == s, onTap: () => setState(() => _statusFilter = _statusFilter == s ? null : s))),
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
                final (tone, label) = statusStyle(t.status);
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

class _StatusCounter extends StatelessWidget {
  const _StatusCounter({required this.status, required this.count, required this.selected, required this.onTap});
  final TrackStatus status;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (tone, label) = _AdminLiveTrackingScreenState.statusStyle(status);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label: $count',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.control,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.fast),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          decoration: BoxDecoration(
            color: selected ? tone.container : Colors.transparent,
            borderRadius: AppRadius.control,
            border: Border.all(color: selected ? tone.color.withValues(alpha: 0.5) : AppColors.border),
          ),
          child: ExcludeSemantics(
            child: Column(
              children: [
                Text('$count', style: AppText.titleSm.copyWith(color: tone == AppTone.neutral ? AppColors.textPrimary : tone.color)),
                Text(label, style: AppText.overline, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackingMap extends StatelessWidget {
  const _TrackingMap({
    required this.controller,
    required this.center,
    required this.branches,
    required this.employees,
    required this.focused,
    required this.showTrail,
    required this.onTapEmployee,
  });

  final MapController controller;
  final LatLng center;
  final List<Map<String, dynamic>> branches;
  final List<TrackedEmployee> employees;
  final TrackedEmployee? focused;
  final bool showTrail;
  final ValueChanged<TrackedEmployee> onTapEmployee;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FlutterMap(
        mapController: controller,
        options: MapOptions(initialCenter: center, initialZoom: 13.5, minZoom: 4, maxZoom: 18, backgroundColor: AppColors.surface2),
        children: [
          appMapTiles(),
          CircleLayer(
            circles: [
              for (final b in branches)
                if (b['latitude'] is num && b['longitude'] is num)
                  CircleMarker(
                    point: LatLng((b['latitude'] as num).toDouble(), (b['longitude'] as num).toDouble()),
                    radius: (b['radius_meters'] as num?)?.toDouble() ?? 100,
                    useRadiusInMeter: true,
                    color: AppColors.brand.withValues(alpha: 0.12),
                    borderColor: AppColors.brand,
                    borderStrokeWidth: 2,
                  ),
            ],
          ),
          if (showTrail && focused != null && focused!.trail.length >= 2)
            PolylineLayer(polylines: [Polyline(points: focused!.trail, strokeWidth: 4, color: AppColors.brand, borderStrokeWidth: 1.5, borderColor: AppColors.bg)]),
          MarkerLayer(
            markers: [
              for (final t in employees)
                if (t.position != null) _marker(t),
              if (focused?.checkInPoint != null)
                Marker(
                  point: focused!.checkInPoint!,
                  child: Container(
                    decoration: BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle, border: Border.all(color: AppColors.success, width: 2)),
                    child: const Icon(Icons.flag_rounded, size: 16, color: AppColors.success),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Marker _marker(TrackedEmployee t) {
    final isFocused = focused?.id == t.id;
    final (tone, label) = _AdminLiveTrackingScreenState.statusStyle(t.status);
    final size = isFocused ? 44.0 : 34.0;
    return Marker(
      point: t.position!,
      width: size + 8,
      height: size + 8,
      child: Semantics(
        button: true,
        label: '${t.name}، $label',
        child: GestureDetector(
          onTap: () => onTapEmployee(t),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: tone == AppTone.neutral ? AppColors.surface3 : tone.color,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: isFocused ? 3 : 2),
                boxShadow: AppElevation.low,
              ),
              alignment: Alignment.center,
              child: Text(
                t.name.characters.first,
                style: AppText.label.copyWith(color: tone == AppTone.neutral ? AppColors.textPrimary : AppColors.onStatus, fontSize: isFocused ? 16 : 13, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.item, required this.showTrail, required this.onToggleTrail, required this.onClose});
  final TrackedEmployee item;
  final bool showTrail;
  final VoidCallback onToggleTrail;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final (tone, label) = _AdminLiveTrackingScreenState.statusStyle(item.status);
    return ContentWidth(
      maxWidth: 520,
      child: Material(
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card, side: BorderSide(color: tone.color.withValues(alpha: 0.5))),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppAvatar(name: item.name, url: item.employee['avatar_url']?.toString(), size: 40, tone: tone),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: AppText.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(item.branchName, style: AppText.caption),
                      ],
                    ),
                  ),
                  StatusBadge(label, tone: tone, dot: true),
                  IconButton(tooltip: 'إغلاق', icon: const Icon(Icons.close_rounded, size: 20), onPressed: onClose),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.lg,
                runSpacing: AppSpace.xs,
                children: [
                  if (item.checkIn != null) _Fact(Icons.login_rounded, Fmt.time(item.checkIn)),
                  if (item.checkOut != null) _Fact(Icons.logout_rounded, Fmt.time(item.checkOut)),
                  if (item.distanceToBranch != null) _Fact(Icons.near_me_rounded, 'عن الفرع ${formatDistance(item.distanceToBranch!)}'),
                  if (item.lastSeen != null) _Fact(Icons.update_rounded, Fmt.relative(item.lastSeen)),
                  if (item.batteryLevel != null) _Fact(Icons.battery_std_rounded, '${item.batteryLevel}%'),
                  if (item.isMoving) const _Fact(Icons.directions_walk_rounded, 'يتحرك'),
                ],
              ),
              if (item.trail.length >= 2) ...[
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    const Icon(Icons.route_rounded, size: 18, color: AppColors.brand),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(child: Text('المسار ${item.totalDistanceKm.toStringAsFixed(2)} كم · ${item.trail.length} نقطة', style: AppText.bodySm)),
                    TextButton(onPressed: onToggleTrail, child: Text(showTrail ? 'إخفاء' : 'إظهار')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSpace.xs),
          Text(text, style: AppText.bodySm.copyWith(color: AppColors.textPrimary)),
        ],
      );
}
