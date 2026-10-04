// أجزاء عرض شاشة الإعدادات: كارت الملف الشخصي، حالة الإشعارات، ووثائقي (المستمسكات).

import 'package:flutter/material.dart';

import '../../../../core/services/storage_links.dart';
import '../../../shared/ui/ui.dart';

/// الصورة (تضغط عليها لتغييرها)، الاسم، الرقم الوظيفي، البريد والهاتف.
class SettingsProfileCard extends StatelessWidget {
  const SettingsProfileCard({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.code,
    required this.email,
    required this.phone,
    required this.uploading,
    required this.onChangeAvatar,
  });

  final String name;
  final String avatarUrl;
  final String code;
  final String email;
  final String phone;
  final bool uploading;
  final VoidCallback onChangeAvatar;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        children: [
          Semantics(
            button: true,
            label: 'تغيير الصورة الشخصية',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: uploading ? null : onChangeAvatar,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AppAvatar(name: name, url: avatarUrl, size: 88),
                  PositionedDirectional(
                    bottom: -2,
                    end: -2,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.brand,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface1, width: 3),
                      ),
                      child: uploading
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand),
                            )
                          : const Icon(Icons.photo_camera_rounded, size: 16, color: AppColors.onBrand),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(name, style: AppText.title, textAlign: TextAlign.center),
          const SizedBox(height: AppSpace.xs),
          StatusBadge(code, tone: AppTone.brand, icon: Icons.badge_outlined),
          const SizedBox(height: AppSpace.lg),
          const Divider(),
          KeyValueRow('البريد', email, icon: Icons.alternate_email_rounded),
          KeyValueRow('الهاتف', phone, icon: Icons.phone_outlined),
        ],
      ),
    );
  }
}

class SettingsNotificationsCard extends StatelessWidget {
  const SettingsNotificationsCard({super.key, required this.granted, required this.onEnable});

  final bool granted;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
        return AppCard(
      tone: granted ? null : AppTone.warning,
      child: Row(
        children: [
          ToneIcon(granted ? Icons.notifications_active_rounded : Icons.notifications_off_rounded, tone: granted ? AppTone.success : AppTone.warning),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(granted ? 'الإشعارات مفعّلة' : 'الإشعارات متوقفة', style: AppText.subtitle),
                Text(granted ? 'توصلك القرارات وتذكيرات البصمة.' : 'فعّلها حتى توصلك القرارات والتذكيرات.', style: AppText.caption),
              ],
            ),
          ),
          if (!granted) AppButton(label: 'تفعيل', size: AppButtonSize.small, onPressed: onEnable),
        ],
      ),
    );
  }
}

/// المستمسكات: الموظف يضيف فقط، والتعديل أو الحذف من قسم الموارد البشرية.
class SettingsDocumentsCard extends StatelessWidget {
  const SettingsDocumentsCard({super.key, required this.urls, required this.uploading, required this.onOpen, required this.onAdd});

  final List<String> urls;
  final bool uploading;
  final ValueChanged<String> onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: [
              for (final url in urls)
                Semantics(
                  button: true,
                  label: 'فتح وثيقة',
                  child: InkWell(
                    onTap: () => onOpen(url),
                    borderRadius: AppRadius.control,
                    child: ClipRRect(
                      borderRadius: AppRadius.control,
                      child: Container(
                        width: 72,
                        height: 72,
                        color: AppColors.surface2,
                        child: SignedNetworkImage(
                          url,
                          fit: BoxFit.cover,
                          cacheWidth: 216,
                          errorBuilder: (_, __, ___) => const Icon(Icons.picture_as_pdf_rounded, color: AppColors.accent),
                        ),
                      ),
                    ),
                  ),
                ),
              Semantics(
                button: true,
                label: 'إضافة مستمسك',
                child: InkWell(
                  onTap: uploading ? null : onAdd,
                  borderRadius: AppRadius.control,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.control,
                      border: Border.all(color: AppColors.borderStrong),
                    ),
                    child: uploading
                        ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, color: AppColors.brand),
                              Text('إضافة', style: AppText.caption),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const Text('تقدر تضيف مستمسكات جديدة؛ تعديلها أو حذفها من قسم الموارد البشرية.', style: AppText.caption),
        ],
      ),
    );
  }
}
