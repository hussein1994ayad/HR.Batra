// =========================================================================
// HR Pro — السلف: حاسبة وطلب + سجل وأقساط
// =========================================================================
// • مبلغ وقسط بفواصل آلاف، اختيار سريع للمبلغ وعدد الأشهر، حساب فوري
// • صورة التعهد الموقّع إلزامية، ومراجعة قبل الإرسال
// • السجل: تقدم السداد وجدول الأقساط
// منطق الرفع والإدراج والتحقق لم يتغير.
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/constants.dart';
import '../../core/services/file_upload_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/utils/arabic_format.dart';
import '../../core/utils/input_formatters.dart';
import '../shared/ui/ui.dart';

class LoanRequestScreen extends StatefulWidget {
  const LoanRequestScreen({super.key});

  @override
  State<LoanRequestScreen> createState() => _LoanRequestScreenState();
}

class _LoanRequestScreenState extends State<LoanRequestScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  double _requestedAmount = 500000;
  double _monthlyInstallment = 250000;

  File? _pledgeFile;
  bool _isSubmitting = false;
  bool _isLoadingHistory = true;
  bool _historyError = false;

  List<Map<String, dynamic>> _loansHistory = [];

  late TextEditingController _amountController;
  late TextEditingController _installmentController;

  static const _quickAmounts = [250000, 500000, 1000000, 2000000];
  static const _quickMonths = [2, 3, 6, 10, 12];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _amountController = TextEditingController(text: formatThousands(_requestedAmount));
    _installmentController = TextEditingController(text: formatThousands(_monthlyInstallment));
    _loadLoansHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _installmentController.dispose();
    super.dispose();
  }

  // سلف الموظف مع أقساطها
  Future<void> _loadLoansHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final data = await SupabaseService.client
          .from('loans')
          .select('*, loan_installments(*)')
          .eq('employee_id', user.id)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _loansHistory = List<Map<String, dynamic>>.from(data);
        _historyError = false;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل تاريخ السلف: $e');
      if (mounted) setState(() => _historyError = true);
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  // تصوير التعهد الخطي الموقّع (بالكاميرا مباشرة لزيادة الموثوقية)
  Future<void> _pickPledge() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (pickedFile != null) {
      setState(() => _pledgeFile = File(pickedFile.path));
    }
  }

  int get _months => _monthlyInstallment > 0 ? (_requestedAmount / _monthlyInstallment).ceil() : 0;

  /// آخر قسط قد يكون أقل من القسط الشهري.
  double get _lastInstallment {
    if (_months <= 0) return 0;
    final rest = _requestedAmount - _monthlyInstallment * (_months - 1);
    return rest <= 0 ? _monthlyInstallment : rest;
  }

  void _setAmount(double v) {
    setState(() => _requestedAmount = v);
    _amountController.text = formatThousands(v);
  }

  void _setMonths(int m) {
    final inst = (_requestedAmount / m).ceilToDouble();
    setState(() => _monthlyInstallment = inst);
    _installmentController.text = formatThousands(inst);
  }

  String? get _validationError {
    if (_requestedAmount <= 0) return 'اكتب مبلغ السلفة';
    if (_monthlyInstallment <= 0) return 'اكتب القسط الشهري';
    if (_monthlyInstallment > _requestedAmount) return 'القسط أكبر من مبلغ السلفة';
    return null;
  }

  Future<void> _submitLoanRequest() async {
    if (_pledgeFile == null) {
      AppSnack.error(context, 'صوّر التعهد الموقّع أولاً حتى نكمل الطلب');
      return;
    }
    final err = _validationError;
    if (err != null) {
      AppSnack.error(context, err);
      return;
    }

    final confirmed = await showAppConfirm(
      context,
      title: 'إرسال طلب السلفة؟',
      message: 'المبلغ: ${Fmt.iqd(_requestedAmount)}\nالقسط: ${Fmt.iqd(_monthlyInstallment)} شهرياً لمدة ${Fmt.monthCount(_months)}',
      confirmLabel: 'إرسال',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isSubmitting = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      // 1. رفع صورة التعهد إلى bucket 'loan-pledges' (مع الضغط التلقائي)
      final uniqueId = const Uuid().v4();
      final fileExtension = _pledgeFile!.path.split('.').last;
      final remotePath = 'pledges/${user.id}/$uniqueId.$fileExtension';

      final pledgeUrl = await FileUploadService.uploadFile(
        file: _pledgeFile!,
        bucketName: 'loan-pledges',
        remotePath: remotePath,
      );

      final int installmentCount = (_requestedAmount / _monthlyInstallment).ceil();

      // 2. إدراج طلب السلفة
      await SupabaseService.client.from('loans').insert({
        'employee_id': user.id,
        'amount': _requestedAmount,
        'installment_amount': _monthlyInstallment,
        'installment_count': installmentCount,
        'remaining_amount': _requestedAmount,
        'pledge_url': pledgeUrl,
        'status': 'pending',
      });

      // 3. إشعار للموظف نفسه
      await SupabaseService.client.from('notifications').insert({
        'employee_id': user.id,
        'title': 'طلب سلفة جديدة 💰',
        'body': 'تم تقديم طلب السلفة المالية بقيمة (${_requestedAmount.toStringAsFixed(0)} ${AppConstants.currency}) رسمياً للإدارة المالية للتدقيق.',
        'type': 'loan',
      });

      // إشعار المدراء يُرسل من قاعدة البيانات (trg_notify_admins_new_loan_request)

      if (mounted) {
        AppSnack.success(context, 'وصل طلب السلفة للإدارة، وراح يوصلك إشعار بالقرار.');
        setState(() => _pledgeFile = null);
        _setAmount(500000);
        _monthlyInstallment = 250000;
        _installmentController.text = formatThousands(250000);
        _tabController.animateTo(1);
        unawaited(_loadLoansHistory());
      }
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر إرسال الطلب: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _loansHistory.where((l) => l['status'] == 'pending').length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('السلف'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'طلب سلفة'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Flexible(child: Text('سلفي وأقساطي', overflow: TextOverflow.ellipsis)),
                  if (active > 0) ...[const SizedBox(width: AppSpace.xs), Badge(label: Text('$active'), backgroundColor: AppColors.warning, textColor: AppColors.onStatus)],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.lg, AppSpace.page, AppSpace.x4),
            child: ContentWidth(
              maxWidth: AppBreakpoints.maxForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCalculator(),
                  const SizedBox(height: AppSpace.lg),
                  _buildPledgeCard(),
                  const SizedBox(height: AppSpace.xxl),
                  AppButton(
                    label: 'مراجعة وإرسال',
                    icon: Icons.send_rounded,
                    size: AppButtonSize.large,
                    expand: true,
                    loading: _isSubmitting,
                    onPressed: _submitLoanRequest,
                  ),
                ],
              ),
            ),
          ),
          _buildLoansHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildCalculator() {
    final err = _validationError;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _amountController,
            label: 'مبلغ السلفة',
            icon: Icons.payments_outlined,
            suffix: const Padding(padding: EdgeInsets.all(AppSpace.md), child: Text('د.ع', style: AppText.label)),
            keyboardType: TextInputType.number,
            inputFormatters: [DotThousandsSeparatorInputFormatter()],
            onChanged: (val) => setState(() => _requestedAmount = parseThousands(val)),
          ),
          const SizedBox(height: AppSpace.sm),
          AppChoiceChips<int>(
            scrollable: true,
            value: _quickAmounts.contains(_requestedAmount.round()) ? _requestedAmount.round() : null,
            options: [for (final a in _quickAmounts) (a, formatThousands(a), null)],
            onChanged: (v) => _setAmount(v.toDouble()),
          ),
          const SizedBox(height: AppSpace.lg),
          AppTextField(
            controller: _installmentController,
            label: 'القسط الشهري',
            icon: Icons.calendar_month_outlined,
            suffix: const Padding(padding: EdgeInsets.all(AppSpace.md), child: Text('د.ع', style: AppText.label)),
            keyboardType: TextInputType.number,
            inputFormatters: [DotThousandsSeparatorInputFormatter()],
            onChanged: (val) => setState(() => _monthlyInstallment = parseThousands(val)),
          ),
          const SizedBox(height: AppSpace.sm),
          AppChoiceChips<int>(
            scrollable: true,
            value: _quickMonths.contains(_months) && _requestedAmount > 0 ? _months : null,
            options: [for (final m in _quickMonths) (m, Fmt.monthCount(m), null)],
            onChanged: _requestedAmount > 0 ? _setMonths : (_) {},
          ),
          const SizedBox(height: AppSpace.lg),
          AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.fast),
            child: err != null
                ? AppCard(key: const ValueKey('err'), tone: AppTone.warning, child: Text(err, style: AppText.bodySm.copyWith(color: AppColors.textPrimary)))
                : AppCard(
                    key: const ValueKey('ok'),
                    color: AppColors.brandContainer.withValues(alpha: 0.35),
                    borderColor: AppColors.brand.withValues(alpha: 0.25),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(child: Text('مدة السداد', style: AppText.bodySm)),
                            Text(Fmt.monthCount(_months), style: AppText.titleSm.copyWith(color: AppColors.brand)),
                          ],
                        ),
                        if (_lastInstallment != _monthlyInstallment)
                          Text('آخر قسط ${Fmt.iqd(_lastInstallment)}', style: AppText.caption),
                        const SizedBox(height: AppSpace.xs),
                        const Text('يُستقطع القسط من راتبك تلقائياً بعد موافقة الإدارة.', style: AppText.caption),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPledgeCard() {
    final done = _pledgeFile != null;
    return AppCard(
      tone: done ? AppTone.success : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ToneIcon(done ? Icons.task_alt_rounded : Icons.draw_rounded, tone: done ? AppTone.success : AppTone.warning),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('التعهد الخطي الموقّع', style: AppText.subtitle),
                    Text(done ? 'تم إرفاق الصورة' : 'مطلوب — وقّع التعهد وصوّره بوضوح', style: AppText.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (done)
            Row(
              children: [
                ClipRRect(
                  borderRadius: AppRadius.control,
                  child: Image.file(_pledgeFile!, width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 192),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(child: AppButton.secondary(label: 'إعادة التصوير', icon: Icons.camera_alt_rounded, size: AppButtonSize.small, onPressed: _pickPledge)),
              ],
            )
          else
            AppButton.secondary(label: 'تصوير التعهد', icon: Icons.camera_alt_rounded, expand: true, onPressed: _pickPledge),
        ],
      ),
    );
  }

  Widget _buildLoansHistoryTab() {
    if (_isLoadingHistory) {
      return const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList(count: 3, itemHeight: 120));
    }
    if (_historyError && _loansHistory.isEmpty) {
      return ErrorView(onRetry: () {
        setState(() => _isLoadingHistory = true);
        _loadLoansHistory();
      });
    }
    if (_loansHistory.isEmpty) {
      return EmptyView(
        title: 'ما عندك سلف',
        message: 'طلباتك وأقساطها تظهر هنا.',
        icon: Icons.account_balance_wallet_rounded,
        actionLabel: 'اطلب سلفة',
        onAction: () => _tabController.animateTo(0),
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: _loadLoansHistory,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.lg, AppSpace.page, AppSpace.x4),
        itemCount: _loansHistory.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpace.md),
        itemBuilder: (context, index) => FadeSlideIn(index: index, child: ContentWidth(child: _LoanCard(loan: _loansHistory[index]))),
      ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.loan});
  final Map<String, dynamic> loan;

  @override
  Widget build(BuildContext context) {
    final amount = (loan['amount'] as num? ?? 0).toDouble();
    final remaining = (loan['remaining_amount'] as num? ?? 0).toDouble();
    final installmentAmount = (loan['installment_amount'] as num? ?? 0).toDouble();
    final status = (loan['status'] ?? 'pending').toString();
    final installments = [
      for (final i in (loan['loan_installments'] as List? ?? const [])) Map<String, dynamic>.from(i as Map),
    ]..sort((a, b) => (a['due_date'] ?? '').toString().compareTo((b['due_date'] ?? '').toString()));
    final paid = amount - remaining;
    final pledge = loan['pledge_url']?.toString();
    final rejection = loan['rejection_reason']?.toString();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const ToneIcon(Icons.account_balance_wallet_rounded, tone: AppTone.warning),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Fmt.iqd(amount), style: AppText.titleSm),
                    Text('طُلبت ${Fmt.relative(DateTime.tryParse(loan['created_at']?.toString() ?? ''))}', style: AppText.caption),
                  ],
                ),
              ),
              StatusBadge.request(status),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          KeyValueRow('القسط الشهري', Fmt.iqd(installmentAmount)),
          KeyValueRow('عدد الأقساط', '${loan['installment_count'] ?? '—'}'),
          if (status == 'approved') ...[
            KeyValueRow('المتبقي', Fmt.iqd(remaining), valueColor: AppColors.brand, bold: true),
            const SizedBox(height: AppSpace.xs),
            AppProgressBar(value: amount > 0 ? paid / amount : 0, tone: AppTone.success),
            const SizedBox(height: AppSpace.xs),
            Text('سُدّد ${Fmt.iqd(paid)} من ${Fmt.iqd(amount)}', style: AppText.caption),
          ],
          if (rejection != null && rejection.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text('سبب الرفض: $rejection', style: AppText.bodySm.copyWith(color: AppColors.danger)),
          ],
          if (status == 'approved' && installments.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text('جدول الأقساط (${installments.where((i) => i['is_paid'] == true).length}/${installments.length} مدفوع)', style: AppText.label),
                children: [
                  for (var i = 0; i < installments.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                      child: Row(
                        children: [
                          SizedBox(width: 28, child: Text('${i + 1}', style: AppText.caption)),
                          Expanded(child: Text(Fmt.date(DateTime.tryParse(installments[i]['due_date']?.toString() ?? ''), withYear: true), style: AppText.bodySm)),
                          Text(Fmt.iqd(installments[i]['amount'] as num?), style: AppText.bodySm.copyWith(color: AppColors.textPrimary)),
                          const SizedBox(width: AppSpace.sm),
                          installments[i]['is_paid'] == true
                              ? const StatusBadge('مدفوع', tone: AppTone.success)
                              : const StatusBadge('قادم'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (pledge != null && pledge.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(
                label: 'عرض التعهد',
                icon: Icons.attach_file_rounded,
                size: AppButtonSize.small,
                onPressed: () async {
                  final url = Uri.tryParse(pledge);
                  if (url != null && await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else if (context.mounted) {
                    AppSnack.error(context, 'تعذّر فتح التعهد');
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
