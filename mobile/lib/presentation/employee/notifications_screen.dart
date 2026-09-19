// =========================================================================
// HR Pro v6.0 - شاشة إشعارات الموظف (Notifications)
// إعادة تصميم عصرية: ألوان الثيم بالكامل، skeleton loading، empty state أنيق.
// كل منطق التحميل ووضع علامة "مقروء" محفوظ كما هو.
// =========================================================================

import 'package:flutter/material.dart';

import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/skeleton_loader.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

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
      });

      final unreadIds = _notifications
          .where((n) => !(n['is_read'] ?? false))
          .map((n) => n['id'] as String)
          .toList();

      if (unreadIds.isNotEmpty) {
        await SupabaseService.client
            .from('notifications')
            .update({'is_read': true}).inFilter('id', unreadIds);
      }
    } catch (e) {
      debugPrint('خطأ في تحميل الإشعارات: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final t = theme.textTheme;
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotifications,
        color: cs.primary,
        child: _buildBody(isDark, t, cs),
      ),
    );
  }

  Widget _buildBody(bool isDark, TextTheme t, ColorScheme cs) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(AppTheme.space4),
        child: SkeletonList(itemCount: 6, itemHeight: 84),
      );
    }

    if (_notifications.isEmpty) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space6),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(AppTheme.space8),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: cs.outline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_off_rounded,
                    size: 56,
                    color: cs.outline,
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    'لا توجد إشعارات حالياً',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.space2),
                  Text(
                    'ستظهر التنبيهات والإشعارات الجديدة هنا فور وصولها.',
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(
                      color: isDark
                          ? AppTheme.darkTextMuted
                          : AppTheme.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppTheme.space4),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppTheme.space3),
      itemBuilder: (context, index) {
        final n = _notifications[index];
        return _NotificationCard(
          type: n['type']?.toString() ?? 'system',
          title: n['title']?.toString() ?? 'تنبيه النظام',
          body: n['body']?.toString() ?? '',
          isRead: n['is_read'] as bool? ?? false,
          createdAt: n['created_at']?.toString(),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final String? createdAt;

  const _NotificationCard({
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final t = theme.textTheme;
    final accent = _typeColor(type);

    return Container(
      padding: const EdgeInsets.all(AppTheme.space4),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(
          color: isRead
              ? (isDark
                  ? AppTheme.darkBorder.withValues(alpha: 0.5)
                  : AppTheme.lightBorder)
              : accent.withValues(alpha: 0.4),
          width: isRead ? 1 : 1.5,
        ),
        boxShadow: isRead ? null : AppTheme.shadowSm(isDark),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.space3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Icon(_typeIcon(type), color: accent, size: 22),
          ),
          const SizedBox(width: AppTheme.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: t.titleMedium?.copyWith(
                          fontWeight:
                              isRead ? FontWeight.w600 : FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTheme.space2),
                    Text(
                      _formatDate(createdAt),
                      style: t.bodySmall?.copyWith(
                        color: isDark
                            ? AppTheme.darkTextMuted
                            : AppTheme.lightTextMuted,
                        fontSize: 11,
                      ),
                    ),
                    if (!isRead) ...[
                      const SizedBox(width: AppTheme.space2),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppTheme.space2),
                Text(
                  body,
                  style: t.bodyMedium?.copyWith(
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'leave':
        return Icons.calendar_month_rounded;
      case 'loan':
        return Icons.monetization_on_rounded;
      case 'attendance':
        return Icons.fingerprint_rounded;
      case 'salary':
        return Icons.receipt_long_rounded;
      case 'device':
        return Icons.phonelink_lock_rounded;
      case 'ota':
        return Icons.system_update_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'leave':
        return AppTheme.accentIndigo;
      case 'loan':
        return AppTheme.warningOrange;
      case 'attendance':
        return AppTheme.successGreen;
      case 'salary':
        return AppTheme.primaryTeal;
      case 'device':
        return AppTheme.dangerRed;
      case 'ota':
        return AppTheme.cyberPurple;
      default:
        return AppTheme.neonCyan;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return 'الآن';
      if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
      if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
      if (date.year == now.year &&
          date.month == now.month &&
          date.day == now.day) {
        final minute = date.minute.toString().padLeft(2, '0');
        final hour = date.hour > 12
            ? date.hour - 12
            : (date.hour == 0 ? 12 : date.hour);
        final amPm = date.hour >= 12 ? 'PM' : 'AM';
        return '$hour:$minute $amPm';
      }
      return '${date.year}/${date.month}/${date.day}';
    } catch (_) {
      return '';
    }
  }
}
