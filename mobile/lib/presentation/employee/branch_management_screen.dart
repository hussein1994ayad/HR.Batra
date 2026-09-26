// =========================================================================
// HR Pro — إدارة الأفرع (النطاق الجغرافي للبصمة)
// =========================================================================
// قائمة الأفرع مع خريطة مصغّرة، وإضافة/تعديل عبر نافذة فيها خريطة تفاعلية،
// شريط لتحديد النطاق بالمتر، وزر "موقعي الحالي". الحذف بعد تأكيد.
// =========================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';

class BranchManagementScreen extends StatefulWidget {
  const BranchManagementScreen({super.key});

  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _branches = [];

  // مركز افتراضي للخريطة (بغداد)
  static const LatLng _defaultCenter = LatLng(33.3152, 44.3661);

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    try {
      final data = await SupabaseService.client.from('branches').select().order('name');
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(data);
        _hasError = false;
      });
    } catch (e) {
      debugPrint('Error loading branches: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static LatLng? _pointOf(Map<String, dynamic> b) {
    final lat = b['latitude'];
    final lng = b['longitude'];
    if (lat is! num || lng is! num) return null;
    return LatLng(lat.toDouble(), lng.toDouble());
  }

  Future<void> _openEditor([Map<String, dynamic>? branch]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _BranchEditor(branch: branch, initial: branch == null ? null : _pointOf(branch)),
    );
    if (saved == true && mounted) {
      AppSnack.success(context, branch == null ? 'أُضيف الفرع' : 'حُفظت التعديلات');
      unawaited(_loadBranches());
    }
  }

  Future<void> _deleteBranch(Map<String, dynamic> branch) async {
    final confirm = await showAppConfirm(
      context,
      title: 'حذف ${branch['name'] ?? 'الفرع'}؟',
      message: 'الموظفون المرتبطون بهذا الفرع راح يحتاجون فرعاً جديداً حتى يبصمون.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!confirm) return;

    try {
      setState(() => _isLoading = true);
      await SupabaseService.client.from('branches').delete().eq('id', branch['id'] as String);
      if (mounted) AppSnack.success(context, 'حُذف الفرع');
      unawaited(_loadBranches());
    } catch (e) {
      debugPrint('Error deleting branch: $e');
      if (mounted) {
        AppSnack.error(context, 'تعذّر الحذف — قد يكون الفرع مرتبطاً بموظفين أو سجلات');
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> content;
    if (_isLoading && _branches.isEmpty) {
      content = const [SkeletonList(count: 3, itemHeight: 96)];
    } else if (_hasError && _branches.isEmpty) {
      content = [ErrorView(onRetry: _loadBranches)];
    } else if (_branches.isEmpty) {
      content = [
        EmptyView(title: 'لا توجد أفرع', message: 'أضف فرعاً وحدد مكانه ونطاقه حتى يقدر الموظفون يبصمون.', icon: Icons.store_rounded, actionLabel: 'إضافة فرع', onAction: _openEditor),
      ];
    } else {
      content = [
        for (var i = 0; i < _branches.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: FadeSlideIn(index: i, child: _branchCard(_branches[i])),
          ),
      ];
    }
    return AppPage(
      title: 'الأفرع',
      subtitle: _branches.isEmpty ? null : '${_branches.length} فرع',
      onRefresh: _loadBranches,
      floatingActionButton: FloatingActionButton.extended(onPressed: _openEditor, icon: const Icon(Icons.add_business_rounded), label: const Text('فرع جديد')),
      slivers: [SliverList.list(children: content)],
    );
  }

  Widget _branchCard(Map<String, dynamic> branch) {
    final point = _pointOf(branch);
    final radius = (branch['radius_meters'] as num? ?? 50).toDouble();
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => _openEditor(branch),
      child: Row(
        children: [
          if (point != null)
            SizedBox(
              width: 96,
              height: 96,
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(AppRadius.md)).resolve(Directionality.of(context)),
                  child: _MiniMap(point: point, radius: radius),
                ),
              ),
            )
          else
            const Padding(padding: EdgeInsets.all(AppSpace.lg), child: ToneIcon(Icons.store_rounded, tone: AppTone.accent)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((branch['name'] ?? 'بدون اسم').toString(), style: AppText.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpace.xs),
                  StatusBadge('النطاق ${radius.round()} م', tone: AppTone.brand, icon: Icons.radar_rounded),
                  if (point == null) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text('لم يُحدد الموقع بعد', style: AppText.caption.copyWith(color: AppColors.warning)),
                  ],
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'خيارات',
            onSelected: (v) => v == 'edit' ? _openEditor(branch) : _deleteBranch(branch),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('تعديل'))),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger), title: Text('حذف'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.point, required this.radius});
  final LatLng point;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(initialCenter: point, initialZoom: 15, backgroundColor: AppColors.surface2, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
      children: [
        appMapTiles(),
        CircleLayer(circles: [
          CircleMarker(point: point, radius: radius, useRadiusInMeter: true, color: AppColors.brand.withValues(alpha: 0.2), borderColor: AppColors.brand, borderStrokeWidth: 1.5),
        ]),
      ],
    );
  }
}

/// نافذة إضافة/تعديل فرع: الاسم، النطاق، والموقع على الخريطة.
class _BranchEditor extends StatefulWidget {
  const _BranchEditor({this.branch, this.initial});
  final Map<String, dynamic>? branch;
  final LatLng? initial;

  @override
  State<_BranchEditor> createState() => _BranchEditorState();
}

class _BranchEditorState extends State<_BranchEditor> {
  final _formKey = GlobalKey<FormState>();
  final _mapController = MapController();
  late final _name = TextEditingController(text: (widget.branch?['name'] ?? '').toString());
  late LatLng _location = widget.initial ?? _BranchManagementScreenState._defaultCenter;
  late double _radius = ((widget.branch?['radius_meters'] as num?) ?? 100).toDouble().clamp(20, 1000);
  bool _saving = false;
  bool _locating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) AppSnack.error(context, 'اسمح للتطبيق بالوصول للموقع أولاً');
        return;
      }
      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 10));
      setState(() => _location = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_location, 17);
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر تحديد موقعك الحالي');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _name.text.trim(),
        'latitude': _location.latitude,
        'longitude': _location.longitude,
        'radius_meters': _radius.roundToDouble(),
      };
      if (widget.branch == null) {
        await SupabaseService.client.from('branches').insert(data);
      } else {
        await SupabaseService.client.from('branches').update(data).eq('id', widget.branch!['id'] as Object);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        AppSnack.error(context, 'تعذّر الحفظ: $e');
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapHeight = (MediaQuery.sizeOf(context).height * 0.34).clamp(200.0, 360.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.branch == null ? 'فرع جديد' : 'تعديل الفرع', style: AppText.title),
              const SizedBox(height: AppSpace.lg),
              AppTextField(
                controller: _name,
                label: 'اسم الفرع',
                hint: 'مثلاً: فرع المنصور',
                icon: Icons.store_rounded,
                validator: (v) => v == null || v.trim().isEmpty ? 'اكتب اسم الفرع' : null,
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  Expanded(child: Text('نطاق البصمة', style: AppText.bodySm.copyWith(fontWeight: FontWeight.w700))),
                  Text('${_radius.round()} م', style: AppText.subtitle.copyWith(color: AppColors.brand)),
                ],
              ),
              Slider.adaptive(
                value: _radius,
                min: 20,
                max: 1000,
                divisions: 98,
                label: '${_radius.round()} م',
                activeColor: AppColors.brand,
                onChanged: (v) => setState(() => _radius = v),
              ),
              const SizedBox(height: AppSpace.sm),
              ClipRRect(
                borderRadius: AppRadius.card,
                child: SizedBox(
                  height: mapHeight,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _location,
                          initialZoom: 16,
                          backgroundColor: AppColors.surface2,
                          onTap: (_, point) => setState(() => _location = point),
                        ),
                        children: [
                          appMapTiles(),
                          CircleLayer(circles: [
                            CircleMarker(
                              point: _location,
                              color: AppColors.brand.withValues(alpha: 0.25),
                              borderStrokeWidth: 2,
                              borderColor: AppColors.brand,
                              useRadiusInMeter: true,
                              radius: _radius,
                            ),
                          ]),
                          MarkerLayer(markers: [
                            Marker(point: _location, width: 40, height: 40, alignment: Alignment.topCenter, child: const Icon(Icons.location_on_rounded, color: AppColors.danger, size: 40)),
                          ]),
                        ],
                      ),
                      PositionedDirectional(
                        top: AppSpace.sm,
                        end: AppSpace.sm,
                        child: AppButton.secondary(
                          label: 'موقعي الحالي',
                          icon: Icons.my_location_rounded,
                          size: AppButtonSize.small,
                          loading: _locating,
                          onPressed: _useMyLocation,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              const Text('اضغط على الخريطة لنقل موقع الفرع، أو استعمل موقعك إذا كنت داخل الفرع الآن.', style: AppText.caption),
              const SizedBox(height: AppSpace.xl),
              AppButton(
                label: widget.branch == null ? 'إضافة الفرع' : 'حفظ التعديلات',
                icon: Icons.check_rounded,
                size: AppButtonSize.large,
                expand: true,
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
