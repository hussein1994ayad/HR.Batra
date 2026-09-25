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
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/file_upload_service.dart';
import '../../core/services/supabase_service.dart';
import '../shared/ui/ui.dart';

class LeaveRequestScreen extends StatefulWidget {
  const LeaveRequestScreen({super.key});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
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

  List<Map<String, dynamic>> _leaveHistory = [];

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
      final data = await SupabaseService.client
          .from('leave_requests')
          .select()
          .eq('employee_id', user.id)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _leaveHistory = List<Map<String, dynamic>>.from(data);
        _historyError = false;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل تاريخ الإجازات: $e');
      if (mounted) setState(() => _historyError = true);
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  // أنواع الإجازات من إعدادات النظام (leave_policy.active_types)
  Future<void> _loadLeaveTypes() async {
    try {
      final data = await SupabaseService.client.from('system_settings').select('value').eq('key', 'leave_policy').maybeSingle();

      if (data != null && data['value'] != null) {
        final policy = data['value'] as Map<String, dynamic>;
        if (policy['active_types'] != null) {
          final typesList = policy['active_types'] as List<dynamic>;
          final List<Map<String, String>> mappedTypes = [];
          for (final t in typesList) {
            final typeMap = t as Map<String, dynamic>;
            mappedTypes.add({
              'id': typeMap['id']?.toString() ?? '',
              'name': typeMap['name']?.toString() ?? '',
            });
          }
          if (mappedTypes.isNotEmpty && mounted) {
            setState(() {
              _leaveTypes = mappedTypes;
              if (!_leaveTypes.any((t) => t['id'] == _leaveType)) {
                _leaveType = _leaveTypes.first['id']!;
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('خطأ في تحميل أنواع الإجازات من السيرفر: $e');
    }
  }

  // اختيار مرفق (صورة تقرير طبي أو مبرر)
  Future<void> _pickAttachment() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
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

  String get _typeName => _leaveTypes.firstWhere((t) => t['id'] == _leaveType, orElse: () => {'name': _leaveType})['name']!;

  String get _durationSummary {
    if (_isHourly) {
      final m = _hourlyMinutes;
      if (m <= 0) return 'وقت النهاية قبل البداية';
      return '${Fmt.dateWithDay(_startDate)} · ${_fmtTod(_startHour)} - ${_fmtTod(_endHour)} (${formatMinutes(m)})';
    }
    if (_dayCount <= 0) return 'تاريخ النهاية قبل البداية';
    return '${Fmt.days(_dayCount)} · ${Fmt.date(_startDate)} إلى ${Fmt.date(_endDate)}';
  }

  static String formatMinutes(int m) {
    final h = m ~/ 60;
    final r = m % 60;
    if (h == 0) return '$r د';
    return r == 0 ? '$h س' : '$h س $r د';
  }

  String _fmtTod(TimeOfDay t) => Fmt.time(DateTime(2000, 1, 1, t.hour, t.minute));

  /// التحقق قبل الإرسال — يرجع رسالة الخطأ أو null.
  String? _validateDates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_startDay.isBefore(today)) return 'لا يمكن طلب إجازة لتاريخ مضى';
    if (!_isHourly && _endDay.isBefore(_startDay)) return 'تاريخ النهاية يجب أن يكون بعد تاريخ البداية أو مساوياً له';
    if (_isHourly && _hourlyMinutes <= 0) return 'وقت النهاية يجب أن يكون بعد وقت البداية';

    for (final req in _leaveHistory) {
      if (req['status'] == 'rejected' || req['status'] == 'cancelled') continue;
      if (req['start_date'] == null || req['end_date'] == null) continue;
      final reqStart = DateTime.parse(req['start_date'] as String).toLocal();
      final reqEnd = DateTime.parse(req['end_date'] as String).toLocal();
      final rStartDay = DateTime(reqStart.year, reqStart.month, reqStart.day);
      final rEndDay = DateTime(reqEnd.year, reqEnd.month, reqEnd.day);
      if (!(_endDay.isBefore(rStartDay) || _startDay.isAfter(rEndDay))) {
        return 'توجد إجازة سابقة تتعارض مع التواريخ المحددة';
      }
    }
    return null;
  }

  // مراجعة ثم إرسال الطلب
  Future<void> _submitLeaveRequest() async {
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

    setState(() => _isUploading = true);
    final user = SupabaseService.currentUser;
    if (user == null) return;

    try {
      String? attachmentUrl;

      // 1. رفع المرفق إن وجد (مع الضغط التلقائي)
      if (_attachmentFile != null) {
        final uniqueId = const Uuid().v4();
        final fileExtension = _attachmentFile!.path.split('.').last;
        final remotePath = 'leaves/${user.id}/$uniqueId.$fileExtension';

        attachmentUrl = await FileUploadService.uploadFile(
          file: _attachmentFile!,
          bucketName: 'employee-documents',
          remotePath: remotePath,
        );
      }

      // 2. أوقات الإجازة الساعية
      String? startHourStr;
      String? endHourStr;
      if (_isHourly) {
        startHourStr = '${_startHour.hour.toString().padLeft(2, '0')}:${_startHour.minute.toString().padLeft(2, '0')}:00';
        endHourStr = '${_endHour.hour.toString().padLeft(2, '0')}:${_endHour.minute.toString().padLeft(2, '0')}:00';
      }

      // 3. إدراج الطلب
      await SupabaseService.client.from('leave_requests').insert({
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

      // 4. إشعار للموظف نفسه بأن الطلب وصل
      await SupabaseService.client.from('notifications').insert({
        'employee_id': user.id,
        'title': 'تقديم طلب إجازة جديد 📝',
        'body': 'تم إرسال طلب إجازتك الجديد بنجاح للإدارة وجاري مراجعته والرد قريباً.',
        'type': 'leave',
      });

      // إشعار المدراء يُرسل من قاعدة البيانات (trg_notify_admins_new_leave_request)

      if (mounted) {
        AppSnack.success(context, 'وصل طلبك للإدارة، وراح يوصلك إشعار بالقرار.');
        _resetForm();
        _tabController.animateTo(1);
        unawaited(_loadHistory());
      }
    } catch (e) {
      if (mounted) AppSnack.error(context, 'تعذّر إرسال الطلب: $e');
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
    final pending = _leaveHistory.where((r) => r['status'] == 'pending').length;
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
                  const Text('طلباتي'),
                  if (pending > 0) ...[const SizedBox(width: AppSpace.xs), Badge(label: Text('$pending'), backgroundColor: AppColors.warning, textColor: AppColors.onStatus)],
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
          _buildLeaveHistoryTab(),
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
                Expanded(child: AppPickerField(label: 'من', value: Fmt.date(_startDate), onTap: () => _selectDate(true))),
                const SizedBox(width: AppSpace.md),
                Expanded(child: AppPickerField(label: 'إلى', value: Fmt.date(_endDate), onTap: () => _selectDate(false))),
              ],
            )
          else ...[
            AppPickerField(label: 'اليوم', value: Fmt.dateWithDay(_startDate), onTap: () => _selectDate(true)),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(child: AppPickerField(label: 'من الساعة', value: _fmtTod(_startHour), icon: Icons.schedule_rounded, onTap: () => _selectTime(true))),
                const SizedBox(width: AppSpace.md),
                Expanded(child: AppPickerField(label: 'إلى الساعة', value: _fmtTod(_endHour), icon: Icons.schedule_rounded, onTap: () => _selectTime(false))),
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
                Expanded(child: Text(_durationSummary, style: AppText.bodySm.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
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
          AppCard(
            onTap: _pickAttachment,
            tone: _attachmentFile != null ? AppTone.success : null,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
            child: Row(
              children: [
                Icon(_attachmentFile != null ? Icons.task_alt_rounded : Icons.add_photo_alternate_outlined, color: _attachmentFile != null ? AppColors.success : AppColors.brand),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    _attachmentFile != null ? 'أُرفقت صورة ${_attachmentFile!.path.split(Platform.pathSeparator).last}' : 'أضف صورة تقرير طبي أو مستند',
                    style: AppText.bodySm.copyWith(color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_attachmentFile != null)
                  IconButton(
                    tooltip: 'إزالة المرفق',
                    onPressed: () => setState(() => _attachmentFile = null),
                    icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
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

  Widget _buildLeaveHistoryTab() {
    if (_isLoadingHistory) {
      return const Padding(padding: EdgeInsets.all(AppSpace.page), child: SkeletonList(count: 4));
    }
    if (_historyError && _leaveHistory.isEmpty) {
      return ErrorView(onRetry: () {
        setState(() => _isLoadingHistory = true);
        _loadHistory();
      });
    }
    final items = _historyFilter == 'all' ? _leaveHistory : _leaveHistory.where((r) => r['status'] == _historyFilter).toList();

    return RefreshIndicator.adaptive(
      onRefresh: _loadHistory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpace.page, AppSpace.md, AppSpace.page, AppSpace.x4),
        children: [
          AppChoiceChips<String>(
            scrollable: true,
            value: _historyFilter,
            onChanged: (v) => setState(() => _historyFilter = v),
            options: const [
              ('all', 'الكل', null),
              ('pending', 'قيد المراجعة', null),
              ('approved', 'مقبولة', null),
              ('rejected', 'مرفوضة', null),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (items.isEmpty)
            EmptyView(
              title: _leaveHistory.isEmpty ? 'ما عندك طلبات إجازة بعد' : 'لا توجد طلبات بهذه الحالة',
              message: _leaveHistory.isEmpty ? 'طلباتك وقرارات الإدارة تظهر هنا.' : null,
              icon: Icons.event_note_rounded,
              actionLabel: _leaveHistory.isEmpty ? 'قدّم طلب' : null,
              onAction: () => _tabController.animateTo(0),
            )
          else
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: FadeSlideIn(index: i, child: ContentWidth(child: _LeaveCard(req: items[i], typeName: _typeLabel(items[i]['leave_type'])))),
              ),
        ],
      ),
    );
  }

  String _typeLabel(Object? type) {
    final id = (type ?? 'other').toString();
    final fromPolicy = _leaveTypes.where((t) => t['id'] == id);
    if (fromPolicy.isNotEmpty) return fromPolicy.first['name']!;
    return switch (id) {
      'annual' => 'اعتيادية',
      'sick' => 'مرضية',
      'emergency' => 'طارئة',
      'maternity' => 'أمومة',
      'other' => 'أخرى',
      _ => id,
    };
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

class _LeaveCard extends StatelessWidget {
  const _LeaveCard({required this.req, required this.typeName});

  final Map<String, dynamic> req;
  final String typeName;

  @override
  Widget build(BuildContext context) {
    final isHourly = req['is_hourly'] == true;
    final start = DateTime.tryParse(req['start_date']?.toString() ?? '');
    final end = DateTime.tryParse(req['end_date']?.toString() ?? '');
    final reason = req['reason']?.toString();
    final rejection = req['rejection_reason']?.toString();
    final url = req['attachment_url']?.toString();
    final period = isHourly
        ? '${Fmt.date(start)} · ${Fmt.timeOfDay(req['start_hour']?.toString())} - ${Fmt.timeOfDay(req['end_hour']?.toString())}'
        : (start != null && end != null && Fmt.date(start) == Fmt.date(end))
            ? Fmt.dateWithDay(start)
            : '${Fmt.date(start)} إلى ${Fmt.date(end)}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ToneIcon(isHourly ? Icons.schedule_rounded : Icons.event_rounded, tone: AppTone.accent),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إجازة $typeName${isHourly ? ' زمنية' : ''}', style: AppText.subtitle),
                    Text(period, style: AppText.caption),
                  ],
                ),
              ),
              StatusBadge.request(req['status']?.toString()),
            ],
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(reason, style: AppText.bodySm, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          if (rejection != null && rejection.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text('سبب الرفض: $rejection', style: AppText.bodySm.copyWith(color: AppColors.danger)),
          ],
          if (url != null && url.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            AppButton.ghost(
              label: 'عرض المرفق',
              icon: Icons.attach_file_rounded,
              size: AppButtonSize.small,
              onPressed: () async {
                final uri = Uri.tryParse(url);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
          const SizedBox(height: AppSpace.xs),
          Text('قُدّم ${Fmt.relative(DateTime.tryParse(req['created_at']?.toString() ?? ''))}', style: AppText.overline),
        ],
      ),
    );
  }
}
