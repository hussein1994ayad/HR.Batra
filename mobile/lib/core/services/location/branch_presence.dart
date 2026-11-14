// قرار دخول/خروج فرع واحد من نقاط الموقع، بدون ما تخدعه قفزات الموقع (الموبايل أحياناً ينطي نقطة على بعد
// 100–200 م لثواني والموظف واقف بمكانه — بلاغ 14/11/2026):
//   • النقطة «داخل» إذا بُعدها ضمن نصف القطر، و«خارج» بس إذا حتى ويا هامش خطئها (البعد − الدقة) تبقى برا الدائرة.
//     غير هيج النقطة غير أكيدة وما تغيّر شي.
//   • الحالة الجديدة تنعتمد بس إذا بقت ثابتة [confirmAfter] (كل النقاط بيها على نفس الجهة)، فقفزة ثواني ما تطلّع إشعار.
//   • أول نقطة تعرّف الحالة بدون إشعار.
// منطق بحت (بدون موقع ولا شبكة) حتى ينفحص بسهولة.

class BranchPresence {
  BranchPresence({this.confirmAfter = const Duration(minutes: 2)});

  final Duration confirmAfter;

  bool? _inside; // آخر حالة معتمدة
  bool? _pending; // الجهة الجديدة اللي ننتظر تثبت
  DateTime? _pendingSince;

  /// يرجع `true` = دخل الفرع، `false` = طلع منه، `null` = ماكو تغيير.
  bool? update({required double distance, required double radius, required double accuracy, required DateTime at}) {
    final bool? side = distance <= radius ? true : (distance - accuracy > radius ? false : null);
    if (side == null) return null;

    if (_inside == null) {
      _inside = side;
      return null;
    }
    if (side == _inside) {
      _pending = null;
      return null;
    }
    if (_pending != side) {
      _pending = side;
      _pendingSince = at;
      return null;
    }
    if (at.difference(_pendingSince!) < confirmAfter) return null;

    _inside = side;
    _pending = null;
    return side;
  }
}
