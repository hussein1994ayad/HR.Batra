// =========================================================================
// HR Pro v6.0 - Skeleton Loaders (Shimmer placeholders)
// =========================================================================
// استخدم هذي الويدجت بدل CircularProgressIndicator في أي شاشة قائمة/بطاقة
// أثناء تحميل البيانات — تعطي إحساساً أسرع بالاستجابة.
//
// أمثلة:
//   SkeletonBox(height: 80)
//   SkeletonList(itemCount: 5, itemHeight: 72)
//   SkeletonCard()
// =========================================================================

import 'package:flutter/material.dart';

import '../../../core/design/design.dart';

/// صندوق skeleton أساسي بحركة shimmer.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = AppRadius.sm,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? AppColors.surface2
        : AppColors.surface2;
    final highlight = isDark
        ? AppColors.borderStrong.withValues(alpha: 0.5)
        : AppColors.textPrimary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 - _controller.value * 2, 0),
              end: Alignment(1.0 + _controller.value * 2, 0),
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// قائمة عمودية من SkeletonBox (لقوائم البيانات).
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final double spacing;

  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.itemHeight = 72,
    this.spacing = AppSpace.md,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(itemCount, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i < itemCount - 1 ? spacing : 0),
          child: SkeletonBox(
            width: double.infinity,
            height: itemHeight,
            radius: AppRadius.md,
          ),
        );
      }),
    );
  }
}

/// بطاقة skeleton (رأس + سطرين).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark
              ? AppColors.borderStrong.withValues(alpha: 0.5)
              : AppColors.borderStrong,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(width: 40, height: 40, radius: AppRadius.full),
              SizedBox(width: AppSpace.md),
              Expanded(child: SkeletonBox()),
            ],
          ),
          SizedBox(height: AppSpace.lg),
          SkeletonBox(width: double.infinity, height: 12),
          SizedBox(height: AppSpace.sm),
          SkeletonBox(width: 200, height: 12),
        ],
      ),
    );
  }
}
