import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import 'app_layout.dart';
import 'app_overlays.dart';

/// رقاقة فلتر تفتح اختياراً (تاريخ، فرع، موظف...). تتلوّن عندما يكون الفلتر مفعّلاً.
class AppFilterPill extends StatelessWidget {
  const AppFilterPill({super.key, required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.onBrandContainer : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpace.sm),
      child: ActionChip(
        avatar: Icon(icon, size: 16, color: active ? AppColors.onBrandContainer : AppColors.textSecondary),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 170), child: Text(label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 16, color: active ? AppColors.onBrandContainer : AppColors.textMuted),
          ],
        ),
        labelStyle: AppText.bodySm.copyWith(color: fg, fontWeight: FontWeight.w700),
        backgroundColor: active ? AppColors.brandContainer : AppColors.surface2,
        side: BorderSide(color: active ? AppColors.brand.withValues(alpha: 0.5) : AppColors.border),
        onPressed: onTap,
      ),
    );
  }
}

/// صف رقاقات فلاتر قابل للتمرير أفقياً بهامش الصفحة.
class AppFilterBar extends StatelessWidget {
  const AppFilterBar({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.page)});
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: padding,
          child: Row(children: children),
        ),
      );
}

/// يفتح قائمة اختيار (مع بحث إذا كانت طويلة) ويرجع المعرّف المختار.
Future<String?> showAppOptions(BuildContext context, {required String title, required List<(String id, String label)> options, String? current}) {
  return showAppSheet<String>(
    context,
    title: title,
    builder: (ctx) => _SearchableOptions(options: options, current: current),
  );
}

class _SearchableOptions extends StatefulWidget {
  const _SearchableOptions({required this.options, this.current});
  final List<(String id, String label)> options;
  final String? current;

  @override
  State<_SearchableOptions> createState() => _SearchableOptionsState();
}

class _SearchableOptionsState extends State<_SearchableOptions> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final items = widget.options.where((o) => _q.isEmpty || o.$2.contains(_q)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.options.length > 8) ...[
          TextField(
            decoration: const InputDecoration(hintText: 'بحث', prefixIcon: Icon(Icons.search_rounded)),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        for (final o in items)
          AppListTile(
            dense: true,
            title: o.$2,
            trailing: o.$1 == widget.current ? const Icon(Icons.check_rounded, color: AppColors.brand) : null,
            onTap: () => Navigator.pop(context, o.$1),
          ),
      ],
    );
  }
}
