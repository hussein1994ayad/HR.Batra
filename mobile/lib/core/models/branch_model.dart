// =========================================================================
// نموذج الفرع — الجدول: public.branches
// =========================================================================

import '../utils/json_map.dart';

double? _numOrNull(Object? v) => v is num ? v.toDouble() : null;

class BranchModel {
  final String id;

  /// الاسم كما هو بالقاعدة؛ القوائم تستعمل [name]، وشاشة الأفرع تعرض بديلها الخاص.
  final String? rawName;

  /// موقع الفرع؛ null إذا ما تحدد بعد.
  final double? latitude;
  final double? longitude;

  /// نصف قطر السياج الجغرافي بالأمتار (radius_meters)؛ null = غير محدد (كل شاشة تعرض بديلها).
  final double? radiusMeters;
  final String? address;
  final DateTime? createdAt;

  const BranchModel({
    required this.id,
    this.rawName,
    this.latitude,
    this.longitude,
    this.radiusMeters,
    this.address,
    this.createdAt,
  });

  factory BranchModel.fromMap(JsonRow map) => BranchModel(
        id: map.str('id') ?? '',
        rawName: map.str('name'),
        latitude: _numOrNull(map['latitude']),
        longitude: _numOrNull(map['longitude']),
        radiusMeters: _numOrNull(map['radius_meters']),
        address: map.str('address'),
        createdAt: map.date('created_at'),
      );

  /// اسم الفرع للقوائم والفلاتر.
  String get name => rawName ?? 'فرع';

  bool get hasLocation => latitude != null && longitude != null;
}
