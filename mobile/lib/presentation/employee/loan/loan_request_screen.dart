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

import '../../../core/models/models.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/utils/arabic_format.dart';
import '../../../core/utils/error_text.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../data/repositories/loan_repository.dart';
import '../../shared/ui/ui.dart';
import 'loan_request_logic.dart';
import 'widgets/loan_widgets.dart';

class LoanRequestScreen extends StatefulWidget {
  const LoanRequestScreen({super.key});

  @override
  State<LoanRequestScreen> createState() => _LoanRequestScreenState();
}

class _LoanRequestScreenState extends State<LoanRequestScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final LoanRepository _repo = LoanRepository();

  double _requestedAmount = 500000;
  double _monthlyInstallment = 250000;

  File? _pledgeFile;
  bool _isSubmitting = false;
  bool _isLoadingHistory = true;
  bool _historyError = false;

  List<LoanModel> _loansHistory = [];

  /// راتب الموظف الشهري (لتنبيه القسط فوق نص الراتب أو فوق الراتب كله)
  double? _salary;

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
      final data = await _repo.fetchMyLoans(user.id);

      final salary = await _repo.fetchMySalary(user.id);

      if (!mounted) return;
      setState(() {
        _loansHistory = data;
        _salary = salary;
        _historyError = false;
      });
    } catch (e) {
      appLog('خطأ في تحميل تاريخ السلف: $e');
      if (mounted) setState(() => _historyError = true);
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  // تصوير التعهد الخطي الموقّع (بالكاميرا مباشرة لزيادة الموثوقية)
  Future<void> _pickPledge() async {
    final pickedFile = await AppImagePicker.pickOne(context, source: ImageSource.camera, imageQuality: 80);
    if (pickedFile != null) {
      setState(() => _pledgeFile = File(pickedFile.path));
    }
  }

  int get _months => loanMonths(_requestedAmount, _monthlyInstallment);

  /// آخر قسط قد يكون أقل من القسط الشهري.
  double get _lastInstallment => loanLastInstallment(_requestedAmount, _monthlyInstallment);

  void _setAmount(double v) {
    setState(() => _requestedAmount = v);
    _amountController.text = formatThousands(v);
  }

  void _setMonths(int m) {
    final inst = (_requestedAmount / m).ceilToDouble();
    setState(() => _monthlyInstallment = inst);
    _installmentController.text = formatThousands(inst);
  }

  String? get _validationError => loanRequestError(amount: _requestedAmount, installment: _monthlyInstallment, history: _loansHistory);

  /// تنبيه فقط (الطلب مسموح): القسط أكثر من نص الراتب، أو أكثر من الراتب كله فيطلع الراتب بالسالب.
  String? get _salaryWarning => loanSalaryWarning(salary: _salary, installment: _monthlyInstallment);

  Future<void> _submitLoanRequest() async {
    FocusManager.instance.primaryFocus?.unfocus();
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
      message: 'المبلغ: ${Fmt.iqd(_requestedAmount)}\nالقسط: ${Fmt.iqd(_monthlyInstallment)} شهرياً لمدة ${Fmt.monthCount(_months)}'
          '${_salaryWarning != null ? '\n\n${_salaryWarning!}' : ''}',
      confirmLabel: 'إرسال',
    );
    if (!confirmed || !mounted) return;

    final user = SupabaseService.currentUser;
    if (user == null) {
      AppSnack.error(context, 'انتهت الجلسة، سجّل الدخول مرة ثانية.');
      return;
    }
    setState(() => _isSubmitting = true);

    try {
      // 1. رفع صورة التعهد إلى bucket 'loan-pledges' (مع الضغط التلقائي)
      final pledgeUrl = await _repo.uploadPledge(user.id, _pledgeFile!);

      final int installmentCount = (_requestedAmount / _monthlyInstallment).ceil();

      // 2. إدراج طلب السلفة
      await _repo.submitLoanRequest({
        'employee_id': user.id,
        'amount': _requestedAmount,
        'installment_amount': _monthlyInstallment,
        'installment_count': installmentCount,
        'remaining_amount': _requestedAmount,
        'pledge_url': pledgeUrl,
        'status': 'pending',
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
      if (mounted) AppSnack.error(context, 'تعذّر إرسال الطلب: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _loansHistory.where((l) => l.isPending).length;
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
                  LoanPledgeCard(file: _pledgeFile, onPick: _pickPledge),
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
                        if (_salaryWarning != null) ...[
                          const SizedBox(height: AppSpace.sm),
                          Text(_salaryWarning!, style: AppText.bodySm.copyWith(color: AppColors.warning)),
                        ],
                      ],
                    ),
                  ),
          ),
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
        itemBuilder: (context, index) => FadeSlideIn(index: index, child: ContentWidth(child: MyLoanCard(loan: _loansHistory[index], onCancel: _cancelLoan))),
      ),
    );
  }

  /// إلغاء طلب سلفة ما زال قيد المراجعة
  Future<void> _cancelLoan(LoanModel loan) async {
    final ok = await showAppConfirm(
      context,
      title: 'إلغاء طلب السلفة؟',
      message: 'يُلغى الطلب ولا يصل للإدارة، وتگدر تقدّم طلب جديد.',
      confirmLabel: 'إلغاء الطلب',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await _repo.cancelMyLoanRequest(loan.id);
      if (!mounted) return;
      AppSnack.success(context, 'أُلغي طلب السلفة');
      unawaited(_loadLoansHistory());
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر إلغاء الطلب: ${errorText(e)}');
    }
  }
}
