import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../data/app_database.dart';
import '../data/providers.dart';

/// Feeds the Android home screen widget (today's agenda).
/// Dart writes today's events as JSON to shared prefs; the native
/// CalendarWidgetProvider renders them. Called whenever events change
/// (save, delete, sync) and on app start.
class HomeWidgetService {
  static const _androidWidgetName = 'CalendarWidgetProvider';

  static final _dateFmt = DateFormat('EEEE, MMM d');

  /// Push [todayEvents] (already filtered to today, time-ordered)
  /// to the widget. Safe to call on any platform — no-op off Android.
  static Future<void> updateToday(List<Event> todayEvents) async {
    try {
      final now = DateTime.now();
      final dateLabel = _dateFmt.format(now).toUpperCase();
      final eventsJson = jsonEncode([
        for (final e in todayEvents)
          {
            'time': _timeLabel(e),
            'title': e.title,
          },
      ]);
      await HomeWidget.saveWidgetData<String>('widget_date', dateLabel);
      await HomeWidget.saveWidgetData<String>('widget_events', eventsJson);
      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
      );
    } catch (_) {
      // Widget not placed, or platform doesn't support it — the app
      // itself is unaffected.
    }
  }

  static String _timeLabel(Event e) {
    if (e.allDay || e.startMinutes == null) return 'ALL DAY';
    final h = e.startMinutes! ~/ 60;
    final m = e.startMinutes! % 60;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} $ampm';
  }

  /// Convenience: load today's events from the DB and push them.
  static Future<void> refreshFromDb(AppDatabase db) async {
    final today = dateKeyOf(DateTime.now());
    final events = await db.watchEventsForDate(today).first;
    await updateToday(events);
  }
}
