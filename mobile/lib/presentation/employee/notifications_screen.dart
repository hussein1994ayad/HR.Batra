// =========================================================================
// HR Pro — الإشعارات مجمّعة حسب اليوم
// كل منطق التحميل ووضع علامة "مقروء" محفوظ كما هو.
// =========================================================================

import 'package:flutter/material.dart';


import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final List<dynamic> data = await SupabaseService.client
          .from('notifications')
          .select()
          .eq('employee_id', user.id)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _notifications = List<Map<String, dynamic>>.from(data);
        _hasError = false;
      });

      final unreadIds = _notifications
          .where((n) => !((n['is_read'] ?? false) as bool))
          .map((n) => n['id'] as String)
          .toList();

      if (unreadIds.isNotEmpty) {
        await SupabaseService.client
            .from('notifications')
            .update({'is_read': true}).inFilter('id', unreadIds);
      }
    } catch (e) {
      debugPrint('خطأ في تحميل الإشعارات: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// عنوان مجموعة التاريخ: اليوم، أمس، هذا الأسبوع، أو الشهر.
  static String _groupOf(DateTime? d) {
    if (d == null) return 'أقدم';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    if (diff < 7) return 'هذا الأسبوع';
    return Fmt.monthYear(d.month, d.year);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> content;
    if (_isLoading && _notifications.isEmpty) {
      content = const [SkeletonList(count: 6, itemHeight: 84)];
    } else if (_hasError && _notifications.isEmpty) {
      content = [ErrorView(onRetry: _loadNotifications)];
    } else if (_notifications.isEmpty) {
      content = const [
        EmptyView(title: 'لا توجد إشعارات', message: 'قرارات الإدارة والتذكيرات تظهر هنا فور وصولها.', icon: Icons.notifications_none_rounded),
      ];
    } else {
      content = [];
      String? group;
      var i = 0;
      for (final n in _notifications) {
        final created = DateTime.tryParse(n['created_at']?.toString() ?? '')?.toLocal();
        final g = _groupOf(created);
        if (g != group) {
          content.add(SectionHeader(g, padding: EdgeInsets.only(top: group == null ? 0 : AppSpace.lg, bottom: AppSpace.sm)));
          group = g;
        }
        content.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: FadeSlideIn(
            index: i++,
            child: _NotificationCard(
              type: n['type']?.toString() ?? 'system',
              title: n['title']?.toString() ?? 'تنبيه',
              body: n['body']?.toString() ?? '',
              isRead: n['is_read'] as bool? ?? false,
              createdAt: created,
            ),
          ),
        ));
      }
    }
    final unread = _notifications.where((n) => n['is_read'] != true).length;
    return AppPage(
      title: 'الإشعارات',
      subtitle: unread > 0 ? '$unread جديدة' : null,
      onRefresh: _loadNotifications,
      slivers: [SliverList.list(children: content)],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.type, required this.title, required this.body, required this.isRead, required this.createdAt});

  final String type;
  final String title;
  final String body;
  final bool isRead;
  final DateTime? createdAt;

  (IconData, AppTone) get _style => switch (type) {
        'leave' => (Icons.event_note_rounded, AppTone.accent),
        'loan' => (Icons.account_balance_wallet_rounded, AppTone.warning),
        'attendance' => (Icons.fingerprint_rounded, AppTone.success),
        'salary' => (Icons.receipt_long_rounded, AppTone.brand),
        'device' => (Icons.phonelink_lock_rounded, AppTone.danger),
        'ota' => (Icons.system_update_rounded, AppTone.info),
        _ => (Icons.notifications_rounded, AppTone.neutral),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = _style;
    return AppCard(
      color: isRead ? AppColors.surface1 : AppColors.surface2,
      borderColor: isRead ? AppColors.border : tone.color.withValues(alpha: 0.35),
      semanticLabel: '${isRead ? '' : 'جديد: '}$title',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ToneIcon(icon, tone: tone),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(title, style: AppText.subtitle.copyWith(fontWeight: isRead ? FontWeight.w600 : FontWeight.w800))),
                    const SizedBox(width: AppSpace.sm),
                    Text(Fmt.relative(createdAt), style: AppText.caption),
                    if (!isRead) ...[
                      const SizedBox(width: AppSpace.xs),
                      Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: tone.color, shape: BoxShape.circle)),
                    ],
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(body, style: AppText.bodySm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
