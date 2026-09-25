import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/design.dart';

/// حقل إدخال موحّد مع عنوان فوق الحقل (أوضح للعربي من العنوان العائم).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.icon,
    this.suffix,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.autofillHints,
    this.textDirection,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;
  final IconData? icon;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;
  final Iterable<String>? autofillHints;
  final TextDirection? textDirection;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final field = TextFormField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      maxLength: maxLength,
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      autofillHints: autofillHints,
      textDirection: textDirection,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: AppText.body,
      cursorColor: AppColors.brand,
      decoration: InputDecoration(
        hintText: hint,
        helperText: helper,
        helperMaxLines: 2,
        errorMaxLines: 2,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        suffixIcon: suffix,
        counterText: '',
      ),
    );
    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.xs, bottom: AppSpace.sm),
          child: Text(label!, style: AppText.bodySm.copyWith(fontWeight: FontWeight.w700)),
        ),
        field,
      ],
    );
  }
}

/// حقل اختيار (تاريخ، قائمة...) يبدو مثل حقل الإدخال ويفتح شيئاً عند الضغط.
class AppPickerField extends StatelessWidget {
  const AppPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon = Icons.calendar_month_rounded,
    this.placeholder = 'اختر',
    this.errorText,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final IconData icon;
  final String placeholder;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.xs, bottom: AppSpace.sm),
          child: Text(label, style: AppText.bodySm.copyWith(fontWeight: FontWeight.w700)),
        ),
        Semantics(
          button: true,
          label: '$label: ${hasValue ? value : placeholder}',
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.control,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: AppRadius.control,
                border: Border.all(color: errorText != null ? AppColors.danger : AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: hasValue ? AppColors.brand : AppColors.textMuted),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Text(
                      hasValue ? value! : placeholder,
                      style: AppText.body.copyWith(color: hasValue ? AppColors.textPrimary : AppColors.textMuted),
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: AppSpace.md, top: AppSpace.xs),
            child: Text(errorText!, style: AppText.caption.copyWith(color: AppColors.danger)),
          ),
      ],
    );
  }
}

/// خيارات كرقاقات (chips) — لاختيار نوع الإجازة، الفترة، الفلتر...
class AppChoiceChips<T> extends StatelessWidget {
  const AppChoiceChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.label,
    this.scrollable = false,
  });

  final List<(T value, String label, IconData? icon)> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? label;

  /// سطر واحد قابل للتمرير بدل التفاف لعدة أسطر.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final (v, text, icon) in options)
        ChoiceChip(
          label: Text(text),
          avatar: icon == null ? null : Icon(icon, size: 16, color: v == value ? AppColors.onBrandContainer : AppColors.textSecondary),
          selected: v == value,
          showCheckmark: false,
          onSelected: (_) {
            AppHaptics.select();
            onChanged(v);
          },
          labelStyle: AppText.bodySm.copyWith(
            color: v == value ? AppColors.onBrandContainer : AppColors.textPrimary,
            fontWeight: v == value ? FontWeight.w700 : FontWeight.w600,
          ),
          side: BorderSide(color: v == value ? AppColors.brand.withValues(alpha: 0.5) : AppColors.border),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
    ];
    final body = scrollable
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [for (final c in chips) Padding(padding: const EdgeInsetsDirectional.only(end: AppSpace.sm), child: c)]),
          )
        : Wrap(spacing: AppSpace.sm, runSpacing: 0, children: chips);
    if (label == null) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.xs, bottom: AppSpace.xs),
          child: Text(label!, style: AppText.bodySm.copyWith(fontWeight: FontWeight.w700)),
        ),
        body,
      ],
    );
  }
}

/// مفتاح تشغيل/إطفاء بسطر كامل قابل للضغط.
class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({super.key, required this.title, required this.value, required this.onChanged, this.subtitle, this.icon});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged == null
          ? null
          : (v) {
              AppHaptics.select();
              onChanged!(v);
            },
      secondary: icon == null ? null : Icon(icon, color: AppColors.textSecondary),
      title: Text(title, style: AppText.subtitle),
      subtitle: subtitle == null ? null : Text(subtitle!, style: AppText.caption),
      activeTrackColor: AppColors.brand,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
    );
  }
}
