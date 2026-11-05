import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'app_database.dart';

final _dateKeyFmt = DateFormat('yyyy-MM-dd');

/// Local date -> "2026-10-29".
String dateKeyOf(DateTime d) => _dateKeyFmt.format(d);

DateTime dateOfKey(String key) => _dateKeyFmt.parse(key);

/// Monday of the week containing [d] (plan §3: Monday–Sunday weeks).
DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

/// Mixed-case weekday scraps, locked from the Persona 5 screenshot style.
String weekdayScrap(int weekday) {
  // DateTime.weekday: 1 = Monday … 7 = Sunday.
  const names = [
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRiDay',
    'SATURDaY',
    'SUNDAY',
  ];
  return names[weekday - 1];
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Selected date on the Calendar screen, as a dateKey.
class CalendarSelectedDate extends Notifier<String> {
  @override
  String build() => dateKeyOf(DateTime.now());
  void select(String key) => state = key;
}

final calendarSelectedDateProvider =
    NotifierProvider<CalendarSelectedDate, String>(CalendarSelectedDate.new);

/// Displayed month on the Calendar screen (first-of-month).
class DisplayedMonth extends Notifier<DateTime> {
  @override
  DateTime build() {
    final n = DateTime.now();
    return DateTime(n.year, n.month);
  }

  void prev() {
    final m = state;
    state = DateTime(m.year, m.month - 1);
  }

  void next() {
    final m = state;
    state = DateTime(m.year, m.month + 1);
  }

  void goToday() {
    final n = DateTime.now();
    state = DateTime(n.year, n.month);
    // Keep the selected date in sync when jumping to today.
    ref.read(calendarSelectedDateProvider.notifier).select(dateKeyOf(n));
  }

  /// Jump to an arbitrary month (Google Calendar header picker).
  /// Also selects the 1st so the day list below stays in this month.
  void jumpTo(int year, int month) {
    state = DateTime(year, month);
    ref
        .read(calendarSelectedDateProvider.notifier)
        .select(dateKeyOf(DateTime(year, month, 1)));
  }

  /// Show a month without touching the selected date
  /// (tapping a dimmed adjacent-month day, like Google Calendar).
  void showMonth(int year, int month) {
    state = DateTime(year, month);
  }
}

final displayedMonthProvider =
    NotifierProvider<DisplayedMonth, DateTime>(DisplayedMonth.new);

/// Monday of the week shown on the Week screen.
class WeekStart extends Notifier<DateTime> {
  @override
  DateTime build() => mondayOf(DateTime.now());

  void prevWeek() => state = state.subtract(const Duration(days: 7));
  void nextWeek() => state = state.add(const Duration(days: 7));
  void goThisWeek() => state = mondayOf(DateTime.now());
}

final weekStartProvider = NotifierProvider<WeekStart, DateTime>(WeekStart.new);

/// Selected date on the Week screen, as a dateKey.
class WeekSelectedDate extends Notifier<String> {
  @override
  String build() => dateKeyOf(DateTime.now());
  void select(String key) => state = key;
}

final weekSelectedDateProvider =
    NotifierProvider<WeekSelectedDate, String>(WeekSelectedDate.new);

final eventsForDateProvider =
    StreamProvider.family<List<Event>, String>((ref, dateKey) {
  return ref.watch(databaseProvider).watchEventsForDate(dateKey);
});

/// Inclusive range, used for the Calendar grid markers and the
/// Week picker day counts.
final eventsInRangeProvider =
    StreamProvider.family<List<Event>, ({String start, String end})>(
        (ref, range) {
  return ref
      .watch(databaseProvider)
      .watchEventsInRange(range.start, range.end);
});
