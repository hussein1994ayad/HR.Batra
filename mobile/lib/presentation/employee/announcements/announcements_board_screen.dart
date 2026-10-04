// =========================================================================
// HR Pro — لوحة التعاميم: التعاميم السارية + المجازون اليوم
// =========================================================================
// التعميم يظهر من تاريخ بدايته حتى تاريخ انتهائه ثم يختفي (get_active_announcements)،
// والمجاز يظهر طوال إجازته، والزمنية حتى تنتهي ساعتها (get_on_leave_now).
// =========================================================================

import 'package:flutter/material.dart';

import '../../../data/repositories/announcement_repository.dart';
import '../../shared/ui/ui.dart';
import 'announcement_widgets.dart';

class AnnouncementsBoardScreen extends StatefulWidget {
  const AnnouncementsBoardScreen({super.key});

  @override
  State<AnnouncementsBoardScreen> createState() => _AnnouncementsBoardScreenState();
}

class _AnnouncementsBoardScreenState extends State<AnnouncementsBoardScreen> {
  final AnnouncementRepository _repo = AnnouncementRepository();
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _onLeave = [];
  List<Map<String, dynamic>> _late = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _repo.fetchBoard();
      if (!mounted) return;
      setState(() {
        _announcements = List<Map<String, dynamic>>.from(r[0] as List);
        _onLeave = List<Map<String, dynamic>>.from(r[1] as List);
        _late = List<Map<String, dynamic>>.from(r[2] as List);
        _failed = false;
      });
    } catch (e) {
      debugPrint('Error loading announcements board: $e');
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> content;
    if (_loading) {
      content = [const SkeletonList(count: 4, itemHeight: 88)];
    } else if (_failed) {
      content = [ErrorView(title: 'تعذّر تحميل التعاميم', onRetry: _load)];
    } else {
      final daily = _onLeave.where((p) => p['is_hourly'] != true).toList();
      final hourly = _onLeave.where((p) => p['is_hourly'] == true).toList();
      content = [
        SectionHeader('المجازون اليوم', trailing: _onLeave.isEmpty ? null : StatusBadge('${_onLeave.length}', tone: AppTone.accent)),
        if (_onLeave.isEmpty)
          const AppCard(child: EmptyView(title: 'لا أحد مجاز اليوم', message: 'الكل على رأس العمل.', icon: Icons.groups_rounded, compact: true))
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Column(
              children: [
                for (final p in daily) OnLeaveTile(p),
                if (daily.isNotEmpty && hourly.isNotEmpty) const Divider(indent: AppSpace.lg, endIndent: AppSpace.lg),
                for (final p in hourly) OnLeaveTile(p),
              ],
            ),
          ),
        if (_late.isNotEmpty) ...[
          SectionHeader('المتأخرون اليوم', trailing: StatusBadge('${_late.length}', tone: AppTone.warning)),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Column(children: [for (final p in _late) LateTile(p)]),
          ),
        ],
        const SectionHeader('التعاميم السارية'),
        if (_announcements.isEmpty)
          const AppCard(child: EmptyView(title: 'لا توجد تعاميم حالياً', message: 'ستظهر هنا إعلانات الإدارة.', icon: Icons.campaign_rounded, compact: true))
        else
          for (var i = 0; i < _announcements.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: FadeSlideIn(index: i, child: AnnouncementCard(_announcements[i], maxLines: null)),
            ),
      ];
    }

    return AppPage(
      title: 'التعاميم',
      subtitle: _loading ? null : '${_announcements.length} تعميم ساري',
      onRefresh: _load,
      slivers: [SliverList.list(children: content)],
    );
  }
}
