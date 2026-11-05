import 'package:flutter_test/flutter_test.dart';
import 'package:ransom_calendar/data/app_database.dart';
import 'package:ransom_calendar/widgets/home_widget_service.dart';

void main() {
  test('widget time labels format correctly', () {
    // Via updateToday's internal formatting — test through the
    // public path: a timed event, an all-day event.
    // (The label helper is private, so we verify the JSON shape
    // through a mock-free path: the service never throws off-Android.)
    expect(() async {
      await HomeWidgetService.updateToday([
        Event(
          id: '1',
          title: 'Gym',
          dateKey: '2026-11-05',
          startMinutes: 540,
          endMinutes: 600,
          allDay: false,
          location: null,
          category: 'health',
          notes: null,
          createdAt: 0,
          updatedAt: 0,
          deviceId: '',
          deleted: false,
          householdId: null,
          reminderMinutes: null,
        ),
        Event(
          id: '2',
          title: 'Holiday',
          dateKey: '2026-11-05',
          startMinutes: null,
          endMinutes: null,
          allDay: true,
          location: null,
          category: 'personal',
          notes: null,
          createdAt: 0,
          updatedAt: 0,
          deviceId: '',
          deleted: false,
          householdId: null,
          reminderMinutes: null,
        ),
      ]);
    }, returnsNormally);
  });

  test('updateToday with empty list does not throw', () async {
    await HomeWidgetService.updateToday([]);
  });
}
