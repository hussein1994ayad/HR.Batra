import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/design/design.dart';
import '../../../core/services/storage_links.dart';
import '../ui/app_overlays.dart';

/// صف معلومة: أيقونة + عنوان صغير + قيمة. إذا أُعطي [url] تصير القيمة رابطاً يُفتح.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.isCode = false,
    this.url,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isCode;
  final String? url;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url == null ? '' : await StorageLinks.resolve(url!));
    final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) AppSnack.error(context, 'تعذّر فتح المرفق');
  }

  @override
  Widget build(BuildContext context) {
    final Widget valueWidget;
    if (url != null) {
      valueWidget = InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(value, style: AppText.bodySm.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700))),
              const SizedBox(width: AppSpace.xs),
              const Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.brand),
            ],
          ),
        ),
      );
    } else if (isCode) {
      valueWidget = SelectableText(value, style: AppText.caption.copyWith(color: AppColors.textSecondary, fontFamily: 'monospace'));
    } else {
      valueWidget = Text(value, style: AppText.bodySm.copyWith(color: AppColors.textPrimary));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 18, color: AppColors.textMuted)),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.overline),
              valueWidget,
            ],
          ),
        ),
      ],
    );
  }
}
