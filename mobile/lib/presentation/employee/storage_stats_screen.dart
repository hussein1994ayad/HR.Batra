import 'package:flutter/material.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

class StorageStatsScreen extends StatefulWidget {
  const StorageStatsScreen({super.key});

  @override
  State<StorageStatsScreen> createState() => _StorageStatsScreenState();
}

class _StorageStatsScreenState extends State<StorageStatsScreen> {
  bool _isLoading = true;
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
      for (var row in trashData) {
        if (row['file_size_bytes'] != null) {
          totalTrash += (row['file_size_bytes'] as num).toDouble();
        }
      }

      // 2. قراءة المساحات الحقيقية من الدالة في Supabase
      final dynamic statsData = await SupabaseService.client.rpc('get_storage_stats');
      
      double avatars = 0;
      double documents = 0;
      double pledges = 0;
      double others = 0;

      if (statsData != null && statsData is List) {
        for (var stat in statsData) {
          final bucket = stat['bucket_name']?.toString();
          final size = (stat['total_size'] as num?)?.toDouble() ?? 0.0;
          if (bucket == 'avatars') {
            avatars += size;
          } else if (bucket == 'documents') {
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
        });
      }
    } catch (e) {
      debugPrint('خطأ في تحميل إحصائيات التخزين: $e');
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
    // مجموع المساحة المستخدمة الكلية
    final double totalUsedBytes = _avatarBytes + _documentBytes + _pledgeBytes + _otherBytes + _trashSizeBytes;
    final double usageRatio = totalUsedBytes / _maxCapacityBytes;
    final double usagePercentage = usageRatio * 100;
    
    // التحذير عند تخطي 80%
    final bool isWarning = usageRatio >= 0.8;

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
            'تحليلات التخزين السحابي 📊',
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
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // بطاقة التخزين الإجمالية الإبداعية
                    GlassContainer(
                      padding: const EdgeInsets.all(24),
                      borderRadius: 24,
                      opacity: 0.12,
                      borderColor: isWarning 
                          ? AppTheme.dangerRed.withOpacity(0.5) 
                          : AppTheme.neonCyan.withOpacity(0.3),
                      boxShadow: [
                        BoxShadow(
                          color: (isWarning ? AppTheme.dangerRed : AppTheme.neonCyan).withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        )
                      ],
                      child: Column(
                        children: [
                          const Text(
                            'إجمالي المساحة المستخدمة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: Colors.white60,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatBytes(totalUsedBytes),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: isWarning ? AppTheme.dangerRed : AppTheme.neonCyan,
                              shadows: [
                                Shadow(
                                  color: isWarning ? AppTheme.dangerRed : AppTheme.neonCyan,
                                  blurRadius: 15,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'من أصل ${_formatBytes(_maxCapacityBytes)} المتاحة في الباقة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // مؤشر شريط التقدم العصري
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 10,
                              child: LinearProgressIndicator(
                                value: usageRatio.clamp(0.0, 1.0),
                                backgroundColor: Colors.white.withOpacity(0.1),
                                color: isWarning ? AppTheme.dangerRed : AppTheme.neonCyan,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${usagePercentage.toStringAsFixed(1)}% مستهلك',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isWarning ? AppTheme.dangerRed : AppTheme.neonCyan,
                                ),
                              ),
                              Text(
                                'المتبقي: ${_formatBytes(_maxCapacityBytes - totalUsedBytes)}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // كرت التحذير المتقدم
                    if (isWarning) ...[
                      GlassContainer(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 16,
                        opacity: 0.16,
                        borderColor: AppTheme.dangerRed.withOpacity(0.4),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppTheme.dangerRed, size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'تحذير: التخزين يوشك على الامتلاء! ⚠️',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppTheme.dangerRed,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'لقد تجاوزت نسبة استهلاك المساحة 80%. يرجى إفراغ سلة المحذوفات أو تقليص مساحات الوثائق لتفادي توقف الخدمة.',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.7),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // توزيع المساحة لكل فئة
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'توزيع الملفات حسب الفئة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    _buildCategoryRow('الصورة الشخصية (Avatars)', _avatarBytes, totalUsedBytes, AppTheme.neonCyan, Icons.person),
                    _buildCategoryRow('المستندات والوثائق', _documentBytes, totalUsedBytes, AppTheme.primaryTealLight, Icons.description),
                    _buildCategoryRow('تعهدات السلف (Pledges)', _pledgeBytes, totalUsedBytes, AppTheme.warningOrange, Icons.monetization_on),
                    _buildCategoryRow('سلة المحذوفات مؤقتاً', _trashSizeBytes, totalUsedBytes, AppTheme.dangerRed, Icons.delete),
                    _buildCategoryRow('أخرى والنسخ الاحتياطية', _otherBytes, totalUsedBytes, AppTheme.cyberPurple, Icons.devices_other),
                    
                    const SizedBox(height: 24),
                    
                    // زر تحديث فوري وإفراغ السلة
                    ElevatedButton.icon(
                      onPressed: _loadStorageData,
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text(
                        'تحديث التحليلات المباشرة ⚡',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.neonCyan,
                        shadowColor: AppTheme.neonCyan.withOpacity(0.3),
                        elevation: 8,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // صف تصنيف الملفات بنظام زجاجي متكامل
  Widget _buildCategoryRow(String title, double bytes, double totalBytes, Color color, IconData icon) {
    final double percentage = totalBytes > 0 ? (bytes / totalBytes) * 100 : 0.0;

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      borderRadius: 16,
      opacity: 0.08,
      borderColor: color.withOpacity(0.25),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.3), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatBytes(bytes),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 100,
                        height: 5,
                        child: LinearProgressIndicator(
                          value: (bytes / totalBytes).clamp(0.0, 1.0),
                          backgroundColor: Colors.white.withOpacity(0.08),
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
