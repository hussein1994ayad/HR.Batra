import 'package:flutter_map/flutter_map.dart';

/// طبقة خريطة موحّدة: OpenStreetMap مجانية وبدون مفتاح، معتّمة لتناسب
/// الوضع الداكن. (خرائط Carto صارت تطلب مفتاح API.)
TileLayer appMapTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.batra.hrpro',
      tileBuilder: darkModeTileBuilder,
    );
