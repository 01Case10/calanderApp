import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../data/app_database.dart';
import '../data/event.dart';
import '../data/providers.dart';
import '../location/location_service.dart';
import '../notifications/notification_service.dart';
import 'home_widget_service.dart';
import '../sync/sync_providers.dart';
import '../theme/app_theme.dart';
import '../theme/clumsy_paper.dart';
import '../theme/ransom_text.dart';
import 'entrances.dart';

/// Shows the shared add/edit sheet as a bottom sheet.
/// Returns true when an event was saved or deleted.
/// Phase 2: the paper rips up ~300ms on open (slide + easeOutBack).
Future<bool?> showEventSheet(
  BuildContext context, {
  Event? event,
  required String initialDateKey,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: TearIn(
        duration: const Duration(milliseconds: 300),
        direction: TearDirection.up,
        child: AddEventSheet(event: event, initialDateKey: initialDateKey),
      ),
    ),
  );
}

/// Add / edit sheet (plan §4) — one shared component, not a duplicate.
/// Torn white paper that rips up from the bottom.
/// Fields: title*, date, all-day toggle, start/end, location, category,
/// notes. Validation errors are magenta scraps, not generic dialogs.
/// Delete (edit only) asks for confirm on the sheet itself.
class AddEventSheet extends ConsumerStatefulWidget {
  final Event? event;
  final String initialDateKey;
  const AddEventSheet({
    super.key,
    this.event,
    required this.initialDateKey,
  });

  @override
  ConsumerState<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<AddEventSheet> {
  late final TextEditingController _title;
  late final TextEditingController _location;
  late final TextEditingController _notes;
  late String _dateKey;
  late bool _allDay;
  late int _startMinutes;
  late int _endMinutes;
  late String _category;
  late int? _reminderMinutes;
  String? _titleError;
  String? _timeError;
  bool _confirmingDelete = false;
  bool _saving = false;

  static final _dateLabelFmt = DateFormat('EEE d MMM');

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _title = TextEditingController(text: e?.title ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _dateKey = e?.dateKey ?? widget.initialDateKey;
    _allDay = e?.allDay ?? false;
    _startMinutes = e?.startMinutes ?? 540; // 09:00 default
    _endMinutes = e?.endMinutes ?? 600; // 10:00 default
    _category = e?.category ?? EventCategory.personal;
    // New events default to a 15-min reminder (assistant default);
    // edits keep the stored value (null = OFF).
    _reminderMinutes = e?.reminderMinutes ?? defaultReminderMinutes;
    // Auto-fill location for new events: if the field is empty,
    // ask LocationManager for the current address (permission prompt
    // on first use; a denial just leaves the field empty).
    if (e == null && _location.text.isEmpty) {
      _autoFillLocation();
    }
  }

  Future<void> _autoFillLocation() async {
    final address = await LocationService.getCurrentAddress();
    if (address != null && mounted && _location.text.isEmpty) {
      setState(() => _location.text = address);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  String get _dateLabel =>
      _dateLabelFmt.format(dateOfKey(_dateKey)).toUpperCase();

  void _stepDate(int days) {
    setState(() {
      _dateKey = dateKeyOf(dateOfKey(_dateKey).add(Duration(days: days)));
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _startMinutes : _endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    setState(() {
      final mins = picked.hour * 60 + picked.minute;
      if (isStart) {
        _startMinutes = mins;
        // Keep end after start automatically.
        if (_endMinutes <= _startMinutes) {
          _endMinutes = _startMinutes + 60;
        }
      } else {
        _endMinutes = mins;
      }
      _timeError = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final titleError = validateTitle(_title.text);
    final timeError = validateTimes(
      allDay: _allDay,
      startMinutes: _startMinutes,
      endMinutes: _endMinutes,
    );
    setState(() {
      _titleError = titleError;
      _timeError = timeError;
    });
    if (titleError != null || timeError != null) return;

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final store = ref.read(syncStoreProvider);
      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = widget.event;
      // Sync identity: who made it, which household it belongs to.
      // Pre-pairing events get a null householdId; pairing backfills it.
      final deviceId = await store.deviceId();
      final householdId =
          (await store.household())?.householdId ?? existing?.householdId;
      final entry = EventsCompanion.insert(
        id: existing?.id ?? const Uuid().v4(),
        title: _title.text.trim(),
        dateKey: _dateKey,
        startMinutes: Value(_allDay ? null : _startMinutes),
        endMinutes: Value(_allDay ? null : _endMinutes),
        allDay: Value(_allDay),
        location: Value(_location.text.trim().isEmpty
            ? null
            : _location.text.trim()),
        category: Value(_category),
        notes: Value(
            _notes.text.trim().isEmpty ? null : _notes.text.trim()),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        deviceId: Value(existing?.deviceId.isNotEmpty == true
            ? existing!.deviceId
            : deviceId),
        householdId: Value(householdId),
        reminderMinutes: Value(_reminderMinutes),
      );
      await db.upsertEvent(entry);
      // Schedule (or cancel) the local reminder for the saved event.
      final saved = await db.getEvent(entry.id.value);
      if (saved != null) {
        await NotificationService.scheduleFor(saved);
      }
      // Refresh the home widget (today's agenda may have changed).
      await HomeWidgetService.refreshFromDb(db);
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.event;
    if (existing == null) return;
    // Tombstone, not a hard delete: the delete must sync to the other
    // phone instead of resurrecting on the next merge.
    await ref.read(databaseProvider).upsertEvent(
          existing
              .copyWithCompanion(
                EventsCompanion(
                  deleted: const Value(true),
                  updatedAt:
                      Value(DateTime.now().millisecondsSinceEpoch),
                ),
              )
              .toCompanion(true),
        );
    // Drop the reminder — a deleted event must not notify.
    await NotificationService.cancelFor(existing.id);
    // Refresh the home widget.
    await HomeWidgetService.refreshFromDb(ref.read(databaseProvider));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.event != null;
    final maxH = MediaQuery.of(context).size.height * 0.88;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        child: ClumsyPaper(
          color: AppColors.white,
          seed: widget.event?.id.hashCode ?? 4242,
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(child: _form(isEdit)),
          ),
        ),
      ),
    );
  }

  Widget _form(bool isEdit) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RansomTitle(
          words: isEdit ? ['EDIT', 'Event'] : ['NEW', 'Event'],
          fontSize: 32,
        ),
        const SizedBox(height: 20),
        _label('TITLE *'),
        const SizedBox(height: 8),
        _textField(_title, hint: 'STEAL SOME TIME…'),
        if (_titleError != null) ...[
          const SizedBox(height: 8),
          _errorScrap(_titleError!),
        ],
        const SizedBox(height: 16),
        _label('DATE'),
        const SizedBox(height: 8),
        Row(
          children: [
            _miniTap('◀', () => _stepDate(-1)),
            const SizedBox(width: 8),
            Expanded(
              child: RansomScrap(
                text: _dateLabel,
                index: 5,
                fontSize: 18,
                paperColor: AppColors.lightBlue,
              ),
            ),
            const SizedBox(width: 8),
            _miniTap('▶', () => _stepDate(1)),
            const SizedBox(width: 8),
            _miniTap('TODAY', () {
              setState(() => _dateKey = dateKeyOf(DateTime.now()));
            }),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _label('ALL-DAY'),
            const SizedBox(width: 12),
            ClumsyPaper(
              color: _allDay ? AppColors.yellow : AppColors.white,
              seed: 9001,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              onTap: () => setState(() => _allDay = !_allDay),
              child: Text(
                _allDay ? 'ON' : 'OFF',
                style: const TextStyle(
                  fontFamily: 'Anton',
                  fontSize: 18,
                  color: AppColors.black,
                ),
              ),
            ),
          ],
        ),
        if (!_allDay) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _timeField(
                    'START', formatMinutes(_startMinutes),
                    () => _pickTime(isStart: true)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timeField('END', formatMinutes(_endMinutes),
                    () => _pickTime(isStart: false)),
              ),
            ],
          ),
        ],
        if (_timeError != null) ...[
          const SizedBox(height: 8),
          _errorScrap(_timeError!),
        ],
        const SizedBox(height: 16),
        _label('CATEGORY'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in EventCategory.all)
              ClumsyPaper(
                color: _category == c ? categoryColor(c) : AppColors.white,
                seed: c.hashCode,
                rotationDegrees: _category == c ? 0 : -3,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                onTap: () => setState(() => _category = c),
                child: Text(
                  categoryLabel(c),
                  style: TextStyle(
                    fontFamily: 'Anton',
                    fontSize: 16,
                    color: _category == c &&
                            (c == EventCategory.work ||
                                c == EventCategory.health)
                        ? AppColors.white
                        : AppColors.black,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _label('LOCATION'),
            const Spacer(),
            ClumsyPaper(
              color: AppColors.lightBlue,
              seed: 999,
              rotationDegrees: -2,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              onTap: () async {
                final address =
                    await LocationService.getCurrentAddress();
                if (address != null && mounted) {
                  setState(() => _location.text = address);
                }
              },
              child: const Text(
                'USE MY LOCATION',
                style: TextStyle(
                  fontFamily: 'Anton',
                  fontSize: 13,
                  color: AppColors.black,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _textField(_location, hint: 'WHERE?'),
        const SizedBox(height: 16),
        _label('REMINDER'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (mins, label) in reminderOptions)
              ClumsyPaper(
                color: _reminderMinutes == mins
                    ? AppColors.yellow
                    : AppColors.white,
                seed: (mins ?? -1).hashCode,
                rotationDegrees: _reminderMinutes == mins ? 0 : 3,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                onTap: () => setState(() => _reminderMinutes = mins),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Anton',
                    fontSize: 16,
                    color: AppColors.black,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _label('NOTES'),
        const SizedBox(height: 8),
        _textField(_notes, hint: 'ANYTHING ELSE…', maxLines: 2),
        const SizedBox(height: 24),
        if (_confirmingDelete) ...[
          _errorScrap('DELETE THIS EVENT?'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _actionButton('DELETE', AppColors.black,
                  AppColors.white, _delete)),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton('KEEP', AppColors.white,
                    AppColors.black, () {
                  setState(() => _confirmingDelete = false);
                }),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  _saving ? 'SAVING…' : 'SAVE',
                  AppColors.black,
                  AppColors.yellow,
                  _saving ? null : _save,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                    'CANCEL', AppColors.white, AppColors.black, () {
                  Navigator.of(context).pop(false);
                }),
              ),
            ],
          ),
          if (isEdit) ...[
            const SizedBox(height: 12),
            _actionButton('DELETE', AppColors.magenta, AppColors.white, () {
              setState(() => _confirmingDelete = true);
            }),
          ],
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _label(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: RansomScrap(
        text: text,
        index: text.hashCode,
        fontSize: 14,
        paperColor: AppColors.black,
      ),
    );
  }

  Widget _textField(TextEditingController controller,
      {required String hint, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(
        fontFamily: 'CourierPrime',
        fontSize: 18,
        color: AppColors.black,
      ),
      cursorColor: AppColors.magenta,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontFamily: 'CourierPrime',
          color: Colors.black38,
        ),
        filled: true,
        fillColor: AppColors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.black, width: 2),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.black, width: 2),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.magenta, width: 3),
        ),
      ),
    );
  }

  Widget _miniTap(String text, VoidCallback onTap) {
    return ClumsyPaper(
      color: AppColors.white,
      seed: text.hashCode,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: onTap,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Anton',
          fontSize: 16,
          color: AppColors.black,
        ),
      ),
    );
  }

  Widget _timeField(String label, String value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 8),
        ClumsyPaper(
          color: AppColors.lightBlue,
          seed: label.hashCode,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          onTap: onTap,
          child: Center(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'Anton',
                fontSize: 24,
                color: AppColors.black,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorScrap(String text) {
    return RansomScrap(
      text: text,
      index: text.hashCode,
      fontSize: 16,
      paperColor: AppColors.magenta,
    );
  }

  Widget _actionButton(
      String text, Color paper, Color textPaper, VoidCallback? onTap) {
    return ClumsyPaper(
      color: paper,
      seed: text.hashCode,
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: onTap,
      child: Center(
        child: RansomScrap(
          text: text,
          index: text.hashCode + 1,
          fontSize: 22,
          paperColor: textPaper,
        ),
      ),
    );
  }
}
