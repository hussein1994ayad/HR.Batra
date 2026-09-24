// =========================================================================
// HR Pro v6.0 — نموذج بيانات الفرع (Branch Model)
// =========================================================================
// الجدول المقابل في قاعدة البيانات: public.branches
//
// الحقول:
//   id           UUID    معرف الفرع
//   name         TEXT    اسم الفرع (مثال: القناة، العكد، بغداد الجديدة)
//   latitude     FLOAT8  خط العرض لموقع الفرع
//   longitude    FLOAT8  خط الطول لموقع الفرع
//   radius       FLOAT8  نصف قطر السياج الجغرافي بالأمتار (افتراضي: 200م)
//   address      TEXT    العنوان النصي للفرع (اختياري)
//   is_active    BOOL    هل الفرع نشط؟
//   created_at   TIMESTAMPTZ تاريخ إنشاء الفرع
// =========================================================================

/// يمثّل فرع الشركة.
/// السياج الجغرافي (Geofence): دائرة مركزها (latitude, longitude)
/// ونصف قطرها [radius] متراً — الموظف داخل النطاق إذا كانت المسافة ≤ radius.
class BranchModel {
  final String id;
  final String name;

  /// خط العرض (مثال: 33.3152)
  final double latitude;

  /// خط الطول (مثال: 44.3661)
  final double longitude;

  /// نصف قطر السياج الجغرافي بالأمتار (افتراضي: 200م)
  final double radius;

  final String? address;
  final bool isActive;
  final DateTime? createdAt;

  const BranchModel({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radius = 200.0,
    this.address,
    this.isActive = true,
    this.createdAt,
  });

  factory BranchModel.fromMap(Map<String, dynamic> map) {
    return BranchModel(
      id:        (map['id'] ?? '') as String,
      name:      (map['name'] ?? 'فرع') as String,
      latitude:  (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      radius:    (map['radius'] as num?)?.toDouble() ?? 200.0,
      address:   map['address'] as String?,
      isActive:  (map['is_active'] as bool?) ?? true,
      createdAt: map['created_at'] != null
                     ? DateTime.parse(map['created_at'] as String)
                     : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'id':        id,
    'name':      name,
    'latitude':  latitude,
    'longitude': longitude,
    'radius':    radius,
    if (address != null) 'address': address,
    'is_active': isActive,
  };
}
