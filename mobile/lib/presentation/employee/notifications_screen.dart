// =========================================================================
// نظام HR Pro v6.0 - شاشة إشعارات الموظف المفصلة (Employee Notifications Screen)
// =========================================================================

import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

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

  // جلب الإشعارات وتحديث حالتها لتصبح مقروءة تلقائياً للتخفيف عن الموظف
  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final List<dynamic> data = await SupabaseService.client
          .from('notifications')
          .select()
          .eq('employee_id', user.id)
          .order('created_at', ascending: false);

      setState(() {
        _notifications = List<Map<String, dynamic>>.from(data);
      });

      // 2. تحديث جميع الإشعارات غير المقروءة لتصبح مقروءة الآن
      final unreadIds = _notifications
          .where((n) => !(n['is_read'] ?? false))
          .map((n) => n['id'] as String)
          .toList();

      if (unreadIds.isNotEmpty) {
        await SupabaseService.client
            .from('notifications')
            .update({'is_read': true})
            .inFilter('id', unreadIds);
      }
    } catch (e) {
      debugPrint('خطأ في تحميل إشعارات الموظف: $e');
    } finally {
      setState(() => _isLoading = false);
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: const Text(
            'لوحة الإشعارات والتنبيهات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: AppTheme.neonCyan,
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppTheme.neonCyan,
                ),
              )
            : _notifications.isEmpty
                ? Center(
                    child: GlassContainer(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      margin: const EdgeInsets.all(24),
                      borderRadius: 24,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_off_rounded,
                            size: 48,
                            color: Colors.white.withOpacity(0.4),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'صندوق الإشعارات فارغ حالياً ✨',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'عند تلقي أي إشعار جديد من الإدارة سيظهر هنا فوراً.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5),
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadNotifications,
                    color: AppTheme.neonCyan,
                    backgroundColor: AppTheme.darkSurface,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final n = _notifications[index];
                        final type = n['type'] ?? 'system';
                        final title = n['title'] ?? 'تنبيه النظام';
                        final body = n['body'] ?? '';
                        final isRead = n['is_read'] ?? false;
                        final typeColor = _getTypeColor(type);

                        return GlassContainer(
                          borderRadius: 18,
                          opacity: !isRead ? 0.14 : 0.06,
                          borderColor: !isRead 
                              ? typeColor.withOpacity(0.7) 
                              : Colors.white.withOpacity(0.08),
                          boxShadow: !isRead
                              ? [
                                  BoxShadow(
                                    color: typeColor.withOpacity(0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : null,
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // أيقونة نوع الإشعار المتوهجة
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: typeColor.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: typeColor.withOpacity(0.35),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: typeColor.withOpacity(0.2),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _getTypeIcon(type),
                                  color: typeColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),

                              // محتوى الإشعار
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontWeight: !isRead ? FontWeight.w800 : FontWeight.bold,
                                              fontSize: 13,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatNotificationDate(n['created_at']),
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 9, 
                                            color: Colors.white.withOpacity(0.4),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      body,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: Colors.white.withOpacity(0.8),
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  // تصنيف الأيقونات طبقاً لنوع الإشعار
  IconData _getTypeIcon(String type) {
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

  // تصنيف ألوان الأيقونات بما يتماشى مع لوحة النيون
  Color _getTypeColor(String type) {
    switch (type) {
      case 'leave':
        return AppTheme.neonCyan;
      case 'loan':
        return AppTheme.cyberPurple;
      case 'attendance':
        return AppTheme.successGreen;
      case 'device':
        return AppTheme.dangerRed;
      case 'ota':
        return AppTheme.warningOrange;
      default:
        return AppTheme.neonPink;
    }
  }

  String _formatNotificationDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      if (date.year == now.year && date.month == now.month && date.day == now.day) {
        final minute = date.minute.toString().padLeft(2, '0');
        final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
        final amPm = date.hour >= 12 ? 'PM' : 'AM';
        return '$hour:$minute $amPm';
      }
      return '${date.year}/${date.month}/${date.day}';
    } catch (_) {
      return '';
    }
  }
}
