// =========================================================================
// نموذج الفرع — الجدول: public.branches
// =========================================================================

import '../utils/json_map.dart';

class BranchModel {
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  /// نصف قطر السياج الجغرافي بالأمتار (radius_meters)
  final double radiusMeters;
  final String? address;
  final DateTime? createdAt;

  const BranchModel({
    required this.id,
    required this.name,
    this.latitude = 0,
    this.longitude = 0,
    this.radiusMeters = 100,
    this.address,
    this.createdAt,
  });

  factory BranchModel.fromMap(JsonRow map) => BranchModel(
        id: map.str('id') ?? '',
        name: map.str('name') ?? 'فرع',
        latitude: map.dbl('latitude') ?? 0,
        longitude: map.dbl('longitude') ?? 0,
        radiusMeters: map.dbl('radius_meters') ?? 100,
        address: map.str('address'),
        createdAt: map.date('created_at'),
      );

  Map<String, dynamic> toInsert() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': radiusMeters,
        'address': address,
      };
}
