import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

/// سطر معلومة: أيقونة، عنوان صغير، وقيمة (نص، رمز قابل للنسخ، أو رابط يُفتح خارجياً).
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

  /// عند تمريره تصبح القيمة رابطاً يفتح المرفق في تطبيق خارجي
  final String? url;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url ?? '');
    final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح المرفق', style: TextStyle(fontFamily: 'Cairo'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget valueWidget;
    if (url != null) {
      valueWidget = GestureDetector(
        onTap: () => _open(context),
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.neonCyan,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.underline,
            fontFamily: 'Cairo',
          ),
        ),
      );
    } else if (isCode) {
      valueWidget = SelectableText(
        value,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, fontFamily: 'monospace', color: AppTheme.neonCyan),
      );
    } else {
      valueWidget = Text(
        value,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: Colors.white),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.white38, fontFamily: 'Cairo')),
              const SizedBox(height: 2),
              valueWidget,
            ],
          ),
        ),
      ],
    );
  }
}
