// =========================================================================
// HR Pro v6.0 — إحصاءات التخزين (Storage Stats)
// عرض حجم ملفات Supabase Storage المستخدمة
// =========================================================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes/app_router.dart';
import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';

class StorageStatsScreen extends StatefulWidget {
  const StorageStatsScreen({super.key});

  @override
  State<StorageStatsScreen> createState() => _StorageStatsScreenState();
}

class _StorageStatsScreenState extends State<StorageStatsScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  double _trashSizeBytes = 0;
  
  double _avatarBytes = 0;
  double _documentBytes = 0;
  double _pledgeBytes = 0;
  double _otherBytes = 0;
  
  final double _maxCapacityBytes = 3.0 * 1024 * 1024 * 1024; // الحد المجاني: 3.0 GB

  @override
  void initState() {
    super.initState();
    _loadStorageData();
  }

  // تحميل حجم سلة المحذوفات الفعلي وحساب الإحصائيات
  Future<void> _loadStorageData() async {
    setState(() => _isLoading = true);
    try {
      // 1. حساب مجموع أحجام الملفات المحذوفة مؤقتاً من جدول deleted_files
      final List<dynamic> trashData = await SupabaseService.client
          .from('deleted_files')
          .select('file_size_bytes')
          .isFilter('restored_at', null);

      double totalTrash = 0;
      for (final row in trashData) {
        if (row['file_size_bytes'] != null) {
          totalTrash += (row['file_size_bytes'] as num).toDouble();
        }
      }

      // 2. قراءة المساحات الحقيقية من الدالة في Supabase
      final dynamic statsData = await SupabaseService.client.rpc<dynamic>('get_storage_stats');
      
      double avatars = 0;
      double documents = 0;
      double pledges = 0;
      double others = 0;

      if (statsData != null && statsData is List) {
        for (final raw in statsData) {
          final stat = Map<String, dynamic>.from(raw as Map);
          final bucket = stat['bucket_name']?.toString();
          final size = (stat['total_size'] as num?)?.toDouble() ?? 0.0;
          if (bucket == 'avatars') {
            avatars += size;
          } else if (bucket == 'employee-documents' || bucket == 'documents') {
            documents += size;
          } else if (bucket == 'loan-pledges') {
            pledges += size;
          } else {
            others += size;
          }
        }
      }

      if (mounted) {
        setState(() {
          _trashSizeBytes = totalTrash;
          _avatarBytes = avatars;
          _documentBytes = documents;
          _pledgeBytes = pledges;
          _otherBytes = others;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('خطأ في تحميل إحصائيات التخزين: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // تنسيق الحجم بالـ KB/MB/GB
  String _formatBytes(double bytes) {
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }


  @override
  Widget build(BuildContext context) {
    final total = _avatarBytes + _documentBytes + _pledgeBytes + _otherBytes + _trashSizeBytes;
    final ratio = (total / _maxCapacityBytes).clamp(0.0, 1.0);
    final tone = ratio >= 0.9
        ? AppTone.danger
        : ratio >= 0.8
            ? AppTone.warning
            : AppTone.brand;

    final List<Widget> content;
    if (_isLoading && total == 0) {
      content = const [Skeleton(height: 160, radius: AppRadius.md), SizedBox(height: AppSpace.lg), SkeletonList(count: 4, itemHeight: 64)];
    } else if (_hasError && total == 0) {
      content = [ErrorView(onRetry: _loadStorageData)];
    } else {
      final rows = [
        (Icons.person_rounded, 'الصور الشخصية', _avatarBytes, AppTone.info),
        (Icons.description_rounded, 'وثائق الموظفين', _documentBytes, AppTone.brand),
        (Icons.draw_rounded, 'تعهدات السلف', _pledgeBytes, AppTone.warning),
        (Icons.folder_rounded, 'ملفات أخرى', _otherBytes, AppTone.accent),
        (Icons.delete_outline_rounded, 'سلة المحذوفات', _trashSizeBytes, AppTone.danger),
      ];
      content = [
        AppCard(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('المساحة المستخدمة', style: AppText.bodySm),
              const SizedBox(height: AppSpace.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_formatBytes(total), style: AppText.display.copyWith(color: tone.color, fontSize: 30)),
                  const SizedBox(width: AppSpace.sm),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('من ${_formatBytes(_maxCapacityBytes)}', style: AppText.bodySm),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              AppProgressBar(value: ratio, tone: tone, height: 10),
              const SizedBox(height: AppSpace.sm),
              Text(
                ratio >= 0.8
                    ? 'المساحة قاربت على الامتلاء (${(ratio * 100).toStringAsFixed(1)}%). نظّف سلة المحذوفات أو الملفات القديمة.'
                    : 'مستخدم ${(ratio * 100).toStringAsFixed(1)}% من المساحة المجانية.',
                style: AppText.caption.copyWith(color: ratio >= 0.8 ? tone.color : null),
              ),
            ],
          ),
        ),
        const SectionHeader('التفاصيل'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Column(
            children: [
              for (final (icon, label, bytes, rowTone) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
                  child: Row(
                    children: [
                      ToneIcon(icon, tone: rowTone, size: 36),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(label, style: AppText.bodySm.copyWith(color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
                                Text(_formatBytes(bytes), style: AppText.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: AppSpace.xs),
                            AppProgressBar(value: total == 0 ? 0 : bytes / total, tone: rowTone, height: 5),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        AppButton.secondary(
          label: 'فتح سلة المحذوفات',
          icon: Icons.delete_sweep_rounded,
          expand: true,
          onPressed: () => context.push(AppRoutes.adminTrash),
        ),
      ];
    }

    return AppPage(
      title: 'التخزين',
      onRefresh: _loadStorageData,
      slivers: [SliverList.list(children: content)],
    );
  }
}
