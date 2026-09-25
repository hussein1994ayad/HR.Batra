import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

/// هيكل صفحة موحّد: عنوان كبير، أزرار، سحب للتحديث، وعرض أقصى على التابلت.
///
/// [slivers] محتوى الصفحة كـ slivers (أسرع للقوائم الطويلة)، أو [body] لعنصر واحد.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
    this.slivers,
    this.body,
    this.onRefresh,
    this.floatingActionButton,
    this.bottomBar,
    this.maxWidth = AppBreakpoints.maxContent,
    this.padding = const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.sm, AppSpace.page, AppSpace.x3),
    this.showBack,
    this.controller,
  }) : assert(slivers != null || body != null);

  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final List<Widget>? slivers;
  final Widget? body;
  final Future<void> Function()? onRefresh;
  final Widget? floatingActionButton;
  final Widget? bottomBar;
  final double maxWidth;
  final EdgeInsets padding;
  final ScrollController? controller;

  /// زر الرجوع: تلقائي حسب إمكانية الرجوع إن لم يُحدد.
  final bool? showBack;

  @override
  Widget build(BuildContext context) {
    final canPop = showBack ?? Navigator.of(context).canPop();
    final width = MediaQuery.sizeOf(context).width;
    final side = width > maxWidth + padding.horizontal ? (width - maxWidth) / 2 : padding.left;
    final effPadding = EdgeInsets.fromLTRB(side, padding.top, side, padding.bottom);

    Widget scroll = CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        if (title != null)
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            leading: leading ?? (canPop ? const BackButton() : null),
            titleSpacing: canPop || leading != null ? 0 : side,
            toolbarHeight: subtitle == null ? kToolbarHeight : 64,
            title: _Title(title: title!, subtitle: subtitle),
            actions: [...actions, SizedBox(width: side - AppSpace.xs < 0 ? 0 : side - AppSpace.xs)],
          ),
        if (slivers != null)
          SliverPadding(padding: effPadding, sliver: SliverMainAxisGroup(slivers: slivers!))
        else
          SliverPadding(padding: effPadding, sliver: SliverToBoxAdapter(child: body)),
      ],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator.adaptive(onRefresh: onRefresh!, color: AppColors.brand, backgroundColor: AppColors.surface2, child: scroll);
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar,
      body: SafeArea(bottom: false, top: title == null, child: scroll),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    if (subtitle == null) return Text(title, style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(subtitle!, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// يحصر المحتوى بعرض أقصى ويوسّطه (للتابلت والوضع الأفقي).
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = AppBreakpoints.maxContent});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

/// عنوان قسم مع زر اختياري ("عرض الكل").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.trailing, this.padding = const EdgeInsets.only(top: AppSpace.xl, bottom: AppSpace.md)});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Expanded(child: Text(title, style: AppText.subtitle.copyWith(fontSize: 16))),
            if (trailing != null) trailing!,
            if (actionLabel != null)
              TextButton(onPressed: onAction, style: TextButton.styleFrom(minimumSize: const Size(48, 40)), child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}

/// صف قائمة موحّد: أيقونة/صورة + عنوان + وصف + عنصر نهائي.
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? showChevron;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final chevron = showChevron ?? (onTap != null && trailing == null);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.control,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpace.touch + 8),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: dense ? AppSpace.sm : AppSpace.md),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: AppSpace.md)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppText.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: AppSpace.sm), trailing!],
              if (chevron) const Icon(Icons.chevron_left_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// شبكة متجاوبة: عدد الأعمدة حسب العرض المتاح.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 150, this.spacing = AppSpace.md, this.maxColumns = 4});

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = ((c.maxWidth + spacing) / (minItemWidth + spacing)).floor().clamp(1, maxColumns);
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}
