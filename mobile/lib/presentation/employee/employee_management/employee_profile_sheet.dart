import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/share_helper.dart';
import '../../shared/ui/ui.dart';
import 'employee_documents.dart';

String employeeRoleLabel(Object? role) => switch (role) {
      'admin' => 'أدمن',
      'manager' => 'مدير فرع',
      _ => 'موظف',
    };

/// ملف الموظف: تواصل سريع، المعلومات الوظيفية، الجهاز، والوثائق.
Future<void> showEmployeeProfileSheet(
  BuildContext context,
  Map<String, dynamic> emp, {
  required VoidCallback onEditDocuments,
}) {
  final name = (emp['full_name'] ?? 'بدون اسم').toString();
  final phone = (emp['phone_number'] ?? emp['phone'] ?? '').toString();
  final hasPhone = phone.trim().isNotEmpty;
  final branches = emp['branches'];
  final departments = emp['departments'];
  final branch = branches is Map ? branches['name']?.toString() : null;
  final department = departments is Map ? departments['name']?.toString() : null;
  final isActive = emp['is_active'] != false;
  final salary = emp['monthly_salary_iqd'] as num?;
  final docUrls = [for (final u in (emp['document_urls'] as List<dynamic>? ?? const [])) u.toString()];
  final devices = emp['employee_devices'] as List<dynamic>? ?? const [];
  final device = devices.isEmpty ? null : devices.first;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.x3),
        children: [
          Row(
            children: [
              AppAvatar(name: name, url: emp['avatar_url']?.toString(), size: 60),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.title),
                    const SizedBox(height: AppSpace.xs),
                    Wrap(
                      spacing: AppSpace.xs,
                      runSpacing: AppSpace.xs,
                      children: [
                        StatusBadge(employeeRoleLabel(emp['role']), tone: AppTone.accent),
                        StatusBadge(isActive ? 'نشط' : 'معطل', tone: isActive ? AppTone.success : AppTone.danger, dot: true),
                        StatusBadge((emp['employee_code'] ?? '—').toString(), tone: AppTone.brand),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'اتصال',
                  icon: Icons.phone_rounded,
                  onPressed: hasPhone
                      ? () async {
                          final uri = Uri.parse('tel:$phone');
                          if (await canLaunchUrl(uri)) await launchUrl(uri);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: AppButton.secondary(
                  label: 'واتساب',
                  icon: Icons.chat_rounded,
                  onPressed: hasPhone
                      ? () async {
                          final uri = Uri.parse('https://wa.me/${phone.replaceAll(RegExp(r'\D'), '')}');
                          if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      : null,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              AppIconButton(
                icon: Icons.copy_rounded,
                tooltip: 'نسخ الرقم',
                onPressed: hasPhone
                    ? () {
                        Clipboard.setData(ClipboardData(text: phone));
                        AppSnack.info(ctx, 'نُسخ رقم الهاتف');
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
            child: Column(
              children: [
                KeyValueRow('البريد', (emp['email'] ?? '—').toString(), icon: Icons.alternate_email_rounded),
                KeyValueRow('الهاتف', hasPhone ? phone : 'غير مسجل', icon: Icons.phone_iphone_rounded),
                KeyValueRow('الفرع', branch ?? 'غير محدد', icon: Icons.store_rounded, valueColor: branch == null ? AppColors.warning : null),
                KeyValueRow('القسم', department ?? 'غير محدد', icon: Icons.apartment_rounded),
                KeyValueRow('الراتب', salary == null || salary == 0 ? 'غير محدد' : Fmt.iqd(salary), icon: Icons.payments_outlined),
                KeyValueRow(
                  'الجهاز',
                  device == null ? 'غير مربوط' : 'مربوط (${(device as Map)['model'] ?? 'هاتف'})',
                  icon: Icons.smartphone_rounded,
                ),
              ],
            ),
          ),
          SectionHeader(
            'المستمسكات (${docUrls.length})',
            trailing: docUrls.length > 1
                ? IconButton(
                    tooltip: 'مشاركة الكل',
                    icon: const Icon(Icons.ios_share_rounded, size: 20),
                    onPressed: () => ShareHelper.shareLinks(docUrls, subject: 'وثائق الموظف: $name', context: ctx),
                  )
                : null,
            actionLabel: 'تعديل',
            onAction: () {
              Navigator.pop(ctx);
              onEditDocuments();
            },
          ),
          if (docUrls.isEmpty)
            const Text('لا توجد مستمسكات مرفوعة.', style: AppText.caption)
          else
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Column(
                children: [
                  for (var i = 0; i < docUrls.length; i++)
                    AppListTile(
                      dense: true,
                      leading: ToneIcon(
                        docUrls[i].toLowerCase().contains('.pdf') ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                        tone: docUrls[i].toLowerCase().contains('.pdf') ? AppTone.accent : AppTone.brand,
                        size: 36,
                      ),
                      title: 'وثيقة ${i + 1}',
                      onTap: () => previewEmployeeDocument(ctx, docUrls[i], 'وثيقة ${i + 1} — $name'),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
