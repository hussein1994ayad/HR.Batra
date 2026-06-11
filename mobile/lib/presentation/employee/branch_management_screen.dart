// =========================================================================
// نظام HR Pro v6.0 - شاشة إدارة الأفرع (Geofences)
// =========================================================================

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/glass_background.dart';
import '../shared/widgets/glass_container.dart';

class BranchManagementScreen extends StatefulWidget {
  const BranchManagementScreen({super.key});

  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _branches = [];
  
  // Default map center (e.g., Baghdad)
  final LatLng _defaultCenter = const LatLng(33.3152, 44.3661);

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    try {
      final data = await SupabaseService.client
          .from('branches')
          .select('*')
          .order('name');
          
      setState(() {
        _branches = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('Error loading branches: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showAddEditBranchModal([Map<String, dynamic>? branch]) {
    final nameController = TextEditingController(text: branch?['name'] ?? '');
    final radiusController = TextEditingController(text: (branch?['radius_meters'] ?? 50).toString());
    
    LatLng selectedLocation = branch != null && branch['latitude'] != null && branch['longitude'] != null
        ? LatLng(branch['latitude'], branch['longitude'])
        : _defaultCenter;
        
    bool isSaving = false;
    final mapController = MapController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F3A),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: AppTheme.neonCyan.withOpacity(0.2)),
              ),
              child: isSaving 
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan))
                  : Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.neonCyan.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(branch == null ? Icons.add_location_alt_rounded : Icons.edit_location_alt_rounded, color: AppTheme.neonCyan, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          branch == null ? 'إضافة فرع جديد' : 'تعديل بيانات الفرع',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildTextField(nameController, 'اسم الفرع', Icons.business_rounded),
                        const SizedBox(height: 16),
                        _buildTextField(radiusController, 'نطاق الفرع (بالمتر)', Icons.radar_rounded, isNumber: true),
                        const SizedBox(height: 16),
                        const Text('حدد موقع الفرع على الخريطة:', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 8),
                        Container(
                          height: 250,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.neonCyan.withOpacity(0.3)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: FlutterMap(
                            mapController: mapController,
                            options: MapOptions(
                              initialCenter: selectedLocation,
                              initialZoom: 15.0,
                              onTap: (tapPosition, point) {
                                setModalState(() {
                                  selectedLocation = point;
                                });
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.hr.pro',
                              ),
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: selectedLocation,
                                    color: AppTheme.neonCyan.withOpacity(0.3),
                                    borderStrokeWidth: 2,
                                    borderColor: AppTheme.neonCyan,
                                    useRadiusInMeter: true,
                                    radius: double.tryParse(radiusController.text) ?? 50.0,
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: selectedLocation,
                                    width: 40,
                                    height: 40,
                                    child: const Icon(Icons.location_on, color: AppTheme.dangerRed, size: 40),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('💡 اضغط على أي نقطة في الخريطة لتغيير الموقع', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.warningOrange, fontSize: 10)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (nameController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('الرجاء إدخال اسم الفرع', style: TextStyle(fontFamily: 'Cairo'))),
                            );
                            return;
                          }

                          setModalState(() => isSaving = true);
                          try {
                            final data = {
                              'name': nameController.text.trim(),
                              'latitude': selectedLocation.latitude,
                              'longitude': selectedLocation.longitude,
                              'radius_meters': double.tryParse(radiusController.text) ?? 50.0,
                            };

                            if (branch == null) {
                              await SupabaseService.client.from('branches').insert(data);
                            } else {
                              await SupabaseService.client.from('branches').update(data).eq('id', branch['id']);
                            }

                            if (mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم حفظ الفرع بنجاح ✅', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.successGreen),
                              );
                              _loadBranches();
                            }
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.dangerRed),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.neonCyan,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(branch == null ? 'إضافة الفرع' : 'حفظ التعديلات', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white54, fontSize: 12),
        prefixIcon: Icon(icon, color: AppTheme.neonCyan, size: 20),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.neonCyan)),
      ),
    );
  }

  Future<void> _deleteBranch(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        title: const Text('حذف الفرع', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        content: const Text('هل أنت متأكد من حذف هذا الفرع؟', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.dangerRed),
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => _isLoading = true);
      await SupabaseService.client.from('branches').delete().eq('id', id);
      _loadBranches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الفرع بنجاح', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.successGreen),
        );
      }
    } catch (e) {
      debugPrint('Error deleting branch: $e');
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
          title: const Text('إدارة الأفرع 🏢', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.add_business_rounded, color: AppTheme.neonCyan),
              onPressed: () => _showAddEditBranchModal(),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.neonCyan))
            : _branches.isEmpty
                ? const Center(child: Text('لا توجد أفرع مسجلة', style: TextStyle(color: Colors.white54, fontFamily: 'Cairo')))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _branches.length,
                    itemBuilder: (context, index) {
                      final branch = _branches[index];
                      return GlassContainer(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        borderRadius: 16,
                        opacity: 0.08,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.neonCyan.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.business_rounded, color: AppTheme.neonCyan, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(branch['name'] ?? 'بدون اسم', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
                                  const SizedBox(height: 4),
                                  Text('النطاق: ${branch['radius_meters'] ?? 50} متر', style: const TextStyle(color: AppTheme.warningOrange, fontSize: 11, fontFamily: 'Cairo')),
                                  if (branch['latitude'] != null)
                                    Text('${branch['latitude']}, ${branch['longitude']}', style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace')),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, color: AppTheme.neonCyan),
                              onPressed: () => _showAddEditBranchModal(branch),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_rounded, color: AppTheme.dangerRed),
                              onPressed: () => _deleteBranch(branch['id']),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
