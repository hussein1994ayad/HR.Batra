// =========================================================================
// HR Pro — الإجازات: تقديم طلب + سجل طلباتي
// =========================================================================
// • النوع بالرقاقات (chips)، يومية أو ساعية، مدفوعة أو بدون راتب
// • ملخص حي للمدة قبل الإرسال + خطوة تأكيد
// • السجل مع فلتر الحالة وسحب للتحديث
// منطق الإرسال والتحقق (التواريخ، التداخل، المرفق) لم يتغير.
// =========================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/models.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/utils/error_text.dart';
import '../../../data/repositories/leave_repository.dart';
import '../../shared/ui/ui.dart';
import 'leave_logic.dart';
import 'widgets/leave_widgets.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final LeaveRepository _repo = LeaveRepository();
  final _formKey = GlobalKey<FormState>();

  // حقول الطلب
  String _leaveType = 'annual';
  bool _isHourly = false;
  bool _isPaid = true;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startHour = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _endHour = const TimeOfDay(hour: 12, minute: 0);
  final _reasonController = TextEditingController();

  File? _attachmentFile;
  bool _isUploading = false;
  bool _isLoadingHistory = true;
  bool _historyError = false;
  String _historyFilter = 'all';

  List<LeaveRequestModel> _leaveHistory = [];

  List<Map<String, String>> _leaveTypes = [
    {'id': 'annual', 'name': 'اعتيادية'},
    {'id': 'sick', 'name': 'مرضية'},
    {'id': 'emergency', 'name': 'طارئة'},
    {'id': 'maternity', 'name': 'أمومة'},
    {'id': 'other', 'name': 'أخرى'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
    _loadLeaveTypes();
    _loadBalance();
  }

  // رصيد الموظف: السنوية والمرضية لهذه السنة، والزمنيات لهذا الشهر (get_leave_balance)
  LeaveBalance? _balance;

  Future<void> _loadBalance() async {
    try {
      final data = await _repo.fetchBalance();
      if (mounted && data is Map) {
        final balance = LeaveBalance.fromMap(Map<String, dynamic>.from(data));
        setState(() => _balance = balance);
      }
    } catch (e) {
      appLog('Error loading leave balance: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  // تحميل سجل الطلبات للموظف
  Future<void> _loadHistory() async {
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      final data = await _repo.fetchMyRequests(user.id);

      if (!mounted) return;
      setState(() {
        _leaveHistory = data;
        _historyError = false;
      });
    } catch (e) {
      appLog('خطأ في تحميل تاريخ الإجازات: $e');
      if (mounted) setState(() => _historyError = true);
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  // أنواع الإجازات من إعدادات النظام (leave_policy.active_types)
  Future<void> _loadLeaveTypes() async {
    try {
      final mappedTypes = parseActiveLeaveTypes(await _repo.fetchLeavePolicy());
      if (mappedTypes.isNotEmpty && mounted) {
        setState(() {
          _leaveTypes = mappedTypes;
          if (!_leaveTypes.any((t) => t['id'] == _leaveType)) {
            _leaveType = _leaveTypes.first['id']!;
          }
        });
      }
    } catch (e) {
      appLog('خطأ في تحميل أنواع الإجازات من السيرفر: $e');
    }
  }

  // اختيار مرفق (صورة تقرير طبي أو مبرر)
  Future<void> _pickAttachment() async {
    final pickedFile = await AppImagePicker.pickOne(context, source: ImageSource.gallery, imageQuality: 85);
    if (pickedFile != null) {
      setState(() => _attachmentFile = File(pickedFile.path));
    }
  }

  DateTime get _startDay => DateTime(_startDate.year, _startDate.month, _startDate.day);
  DateTime get _endDay => _isHourly ? _startDay : DateTime(_endDate.year, _endDate.month, _endDate.day);

  /// عدد أيام الإجازة (يومية) — شامل اليومين.
  int get _dayCount => _endDay.difference(_startDay).inDays + 1;

  /// مدة الإجازة الساعية بالدقائق.
  int get _hourlyMinutes => (_endHour.hour * 60 + _endHour.minute) - (_startHour.hour * 60 + _startHour.minute);

  String get _typeName => bareLeaveTypeName(_leaveTypes.firstWhere((t) => t['id'] == _leaveType, orElse: () => {'name': _leaveType})['name']!);

  String get _durationSummary {
    if (_isHourly) {
      final m = _hourlyMinutes;
      if (m <= 0) return 'وقت النهاية قبل البداية';
      return '${Fmt.dateWithDay(_startDate)} · ${_fmtTod(_startHour)} - ${_fmtTod(_endHour)} (${formatLeaveMinutes(m)})';
    }
    if (_dayCount <= 0) return 'تاريخ النهاية قبل البداية';
    return '${Fmt.days(_dayCount)} · ${Fmt.date(_startDate)} إلى ${Fmt.date(_endDate)}';
  }

  String _fmtTod(TimeOfDay t) => Fmt.time(DateTime(2000, 1, 1, t.hour, t.minute));

  /// التحقق قبل الإرسال — يرجع رسالة الخطأ أو null.
  String? _validateDates() => validateLeaveDates(
        startDay: _startDay,
        endDay: _endDay,
        isHourly: _isHourly,
        hourlyMinutes: _hourlyMinutes,
        history: _leaveHistory,
        now: DateTime.now(),
      );

  // مراجعة ثم إرسال الطلب
  Future<void> _submitLeaveRequest() async {
    // يسكّر الكيبورد قبل نافذة التأكيد؛ بدونه يرجع التركيز لحقل السبب وينفتح الكيبورد بعد الإرسال
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;
    final dateError = _validateDates();
    if (dateError != null) {
      AppSnack.error(context, dateError);
      return;
    }

    final confirmed = await showAppConfirm(
      context,
      title: 'إرسال طلب الإجازة؟',
      message: 'إجازة $_typeName ${_isPaid ? 'مدفوعة' : 'بدون راتب'}\n$_durationSummary',
      confirmLabel: 'إرسال',
    );
    if (!confirmed || !mounted) return;

    final user = SupabaseService.currentUser;
    if (user == null) {
      AppSnack.error(context, 'انتهت الجلسة، سجّل الدخول مرة ثانية.');
      return;
    }
    setState(() => _isUploading = true);

    try {
      String? attachmentUrl;

      // 1. رفع المرفق إن وجد (مع الضغط التلقائي)
      if (_attachmentFile != null) {
        attachmentUrl = await _repo.uploadAttachment(user.id, _attachmentFile!);
      }

      // 2. أوقات الإجازة الساعية
      String? startHourStr;
      String? endHourStr;
      if (_isHourly) {
        startHourStr = leaveHourString(_startHour.hour, _startHour.minute);
        endHourStr = leaveHourString(_endHour.hour, _endHour.minute);
      }

      // 3. إدراج الطلب
      await _repo.submitRequest({
        'employee_id': user.id,
        'leave_type': _leaveType,
        'is_hourly': _isHourly,
        'start_date': _startDate.toUtc().toIso8601String(),
        'end_date': _endDate.toUtc().toIso8601String(),
        'start_hour': startHourStr,
        'end_hour': endHourStr,
        'is_paid': _isPaid,
        'reason': _reasonController.text.trim(),
        'attachment_url': attachmentUrl,
        'status': 'pending',
      });

      // إشعار المدراء يُرسل من قاعدة البيانات (trg_notify_admins_new_leave_request)

      if (mounted) {
        AppSnack.success(context, 'وصل طلبك للإدارة، وراح يوصلك إشعار بالقرار.');
        _resetForm();
        unawaited(_loadBalance());
        _tabController.animateTo(1);
        unawaited(_loadHistory());
      }
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر إرسال الطلب: ${errorText(e)}');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _resetForm() {
    _reasonController.clear();
    setState(() {
      _attachmentFile = null;
      _isHourly = false;
      _isPaid = true;
      _leaveType = _leaveTypes.any((t) => t['id'] == 'annual') ? 'annual' : _leaveTypes.first['id']!;
      _startDate = DateTime.now();
      _endDate = DateTime.now().add(const Duration(days: 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = _leaveHistory.where((r) => r.status == 'pending').length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('الإجازات'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'طلب جديد'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Flexible(child: Text('طلباتي', overflow: TextOverflow.ellipsis)),
                  if (pending > 0) ...[
                    const SizedBox(width: AppSpace.xs),
                    Badge(label: Text('$pending'), backgroundColor: AppColors.warning, textColor: AppColors.onStatus),
                  ],
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
            child: ContentWidth(maxWidth: AppBreakpoints.maxForm, child: _buildLeaveForm()),
          ),
          LeaveHistoryList(
            loading: _isLoadingHistory,
            failed: _historyError,
            history: _leaveHistory,
            filter: _historyFilter,
            onFilterChanged: (v) => setState(() => _historyFilter = v),
            onRetry: () {
              setState(() => _isLoadingHistory = true);
              _loadHistory();
            },
            onRefresh: _loadHistory,
            onNewRequest: () => _tabController.animateTo(0),
            typeLabel: (type) => leaveTypeLabel(type, _leaveTypes),
            onCancel: _cancelLeave,
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LeaveBalanceCard(balance: _balance, isHourly: _isHourly, leaveType: _leaveType),
          AppChoiceChips<String>(
            label: 'نوع الإجازة',
            value: _leaveType,
            options: [for (final t in _leaveTypes) (t['id']!, t['name']!, null)],
            onChanged: (v) => setState(() => _leaveType = v),
          ),
          const SizedBox(height: AppSpace.lg),
          Text('المدة', style: AppText.bodySm.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.sm),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('أيام'), icon: Icon(Icons.today_rounded)),
              ButtonSegment(value: true, label: Text('ساعات (زمنية)'), icon: Icon(Icons.schedule_rounded)),
            ],
            selected: {_isHourly},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              AppHaptics.select();
              setState(() => _isHourly = s.first);
            },
          ),
          const SizedBox(height: AppSpace.lg),
          if (!_isHourly)
            Row(
              children: [
                Expanded(
                  child: AppPickerField(label: 'من', value: Fmt.date(_startDate), onTap: () => _selectDate(true)),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: AppPickerField(label: 'إلى', value: Fmt.date(_endDate), onTap: () => _selectDate(false)),
                ),
              ],
            )
          else ...[
            AppPickerField(label: 'اليوم', value: Fmt.dateWithDay(_startDate), onTap: () => _selectDate(true)),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: AppPickerField(label: 'من الساعة', value: _fmtTod(_startHour), icon: Icons.schedule_rounded, onTap: () => _selectTime(true)),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: AppPickerField(label: 'إلى الساعة', value: _fmtTod(_endHour), icon: Icons.schedule_rounded, onTap: () => _selectTime(false)),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpace.md),
          AppCard(
            color: AppColors.brandContainer.withValues(alpha: 0.35),
            borderColor: AppColors.brand.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
            child: Row(
              children: [
                const Icon(Icons.event_available_rounded, color: AppColors.brand, size: 20),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    _durationSummary,
                    style: AppText.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: AppSwitchTile(
              title: _isPaid ? 'مدفوعة الراتب' : 'بدون راتب',
              subtitle: _isPaid ? 'لا يُستقطع من راتبك' : 'تُستقطع أيامها من الراتب',
              icon: Icons.payments_outlined,
              value: _isPaid,
              onChanged: (v) => setState(() => _isPaid = v),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          AppTextField(
            controller: _reasonController,
            label: 'السبب',
            hint: 'مثلاً: مراجعة طبية، ظرف عائلي...',
            maxLines: 3,
            minLines: 2,
            textInputAction: TextInputAction.newline,
            validator: (value) => value == null || value.trim().isEmpty ? 'اكتب سبب الإجازة' : null,
          ),
          const SizedBox(height: AppSpace.lg),
          Text('مرفق (اختياري)', style: AppText.bodySm.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.sm),
          LeaveAttachmentCard(file: _attachmentFile, onPick: _pickAttachment, onRemove: () => setState(() => _attachmentFile = null)),
          const SizedBox(height: AppSpace.xxl),
          AppButton(
            label: 'مراجعة وإرسال',
            icon: Icons.send_rounded,
            size: AppButtonSize.large,
            expand: true,
            loading: _isUploading,
            onPressed: _submitLeaveRequest,
          ),
        ],
      ),
    );
  }

  /// إلغاء طلب إجازة ما زال قيد المراجعة (بعد القرار يُطلب من الإدارة).
  Future<void> _cancelLeave(LeaveRequestModel req) async {
    final ok = await showAppConfirm(
      context,
      title: 'إلغاء طلب الإجازة؟',
      message: 'يُلغى الطلب ولا يصل للإدارة، وتگدر تقدّم طلب جديد بنفس الأيام.',
      confirmLabel: 'إلغاء الطلب',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await _repo.cancelPending(req.id);
      if (!mounted) return;
      AppSnack.success(context, 'أُلغي طلب الإجازة');
      unawaited(_loadHistory());
      unawaited(_loadBalance());
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر إلغاء الطلب: ${errorText(e)}');
    }
  }

  Future<void> _selectDate(bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
      helpText: isStart ? 'تاريخ البداية' : 'تاريخ النهاية',
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 1));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _selectTime(bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startHour : _endHour,
      helpText: isStart ? 'من الساعة' : 'إلى الساعة',
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startHour = picked;
        } else {
          _endHour = picked;
        }
      });
    }
  }
}
