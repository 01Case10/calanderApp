import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/app_database.dart';
import '../data/providers.dart';

/// Local event reminders. No server, no account — the phone's own
/// alarm scheduler fires them.
///
/// Reminder options (minutes before start; assistant default):
/// null = OFF, 5, 15 (default for new events), 30, 60, 1440 (1 day).
/// For all-day events the "start" is 09:00 local on the event date.
///
/// Lifecycle:
/// - [scheduleFor] after an event is saved (create or edit)
/// - [cancelFor] when an event is deleted (tombstoned)
/// - [rescheduleAll] on app start (alarms don't survive reinstall;
///   Android re-fires them after reboot via the plugin's receiver)
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;
  static bool _available = true;

  /// Must be called once at app start, before any schedule/cancel.
  /// If the platform plugin isn't available (e.g. unit tests),
  /// the service degrades to a no-op instead of throwing.
  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      tzdata.initializeTimeZones();
      // Pin tz.local to the device's real timezone (events are stored
      // as local dateKey + startMinutes, per plan §5).
      try {
        final name = await FlutterNativeTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        // Fall back to UTC if the platform timezone can't be read;
        // reminders still fire, just possibly offset.
      }
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );
    } catch (_) {
      // Platform channels unavailable (unit tests, etc.).
      _available = false;
    }
  }

  /// Ask the OS for permission. Android 13+ needs POST_NOTIFICATIONS;
  /// Android 12+ needs exact-alarm permission for on-time reminders.
  /// Returns true if alerts are allowed.
  static Future<bool> requestPermission() async {
    await init();
    if (!_available) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // POST_NOTIFICATIONS (Android 13+). No-op on older.
    final granted = await android?.requestNotificationsPermission() ?? true;
    // Exact alarms (Android 12+). If denied, reminders may drift.
    await android?.requestExactAlarmsPermission();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await ios?.requestPermissions(
          alert: true, badge: true, sound: true,
        ) ??
        true;
    return granted && iosGranted;
  }

  /// The wall-clock moment a reminder should fire, or null if the
  /// event has no reminder or the moment is already past.
  static DateTime? reminderTimeFor(Event event, DateTime now) {
    final mins = event.reminderMinutes;
    if (mins == null) return null;
    final date = dateOfKey(event.dateKey);
    final startMinutes = event.allDay ? 9 * 60 : (event.startMinutes ?? 0);
    final start = DateTime(
        date.year, date.month, date.day, startMinutes ~/ 60, startMinutes % 60);
    final fireAt = start.subtract(Duration(minutes: mins));
    return fireAt.isAfter(now) ? fireAt : null;
  }

  /// Notification id derived from the event id (stable across edits,
  /// fits in 32 bits for the Android alarm manager).
  static int notificationIdFor(String eventId) =>
      eventId.hashCode & 0x7fffffff;

  /// Schedule (or re-schedule) the reminder for [event].
  /// Past or reminder-less events cancel any existing alarm.
  /// No-op if the platform plugin isn't available.
  static Future<void> scheduleFor(Event event) async {
    await init();
    if (!_available) return;
    final id = notificationIdFor(event.id);
    final fireAt = reminderTimeFor(event, DateTime.now());
    if (fireAt == null) {
      await _plugin.cancel(id);
      return;
    }
    final when = _formatWhen(event);
    await _plugin.zonedSchedule(
      id,
      event.title,
      when.isEmpty ? 'Event starting soon' : when,
      tz.TZDateTime.from(fireAt, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'event_reminders',
          'Event reminders',
          channelDescription: 'Reminders for your calendar events',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// Cancel the reminder for [eventId] (event deleted/tombstoned).
  /// No-op if the platform plugin isn't available.
  static Future<void> cancelFor(String eventId) async {
    await init();
    if (!_available) return;
    await _plugin.cancel(notificationIdFor(eventId));
  }

  /// Reconcile alarms with the DB: schedule every future reminder,
  /// cancel anything not in [events]. Call on app start.
  /// No-op if the platform plugin isn't available.
  static Future<void> rescheduleAll(List<Event> events) async {
    await init();
    if (!_available) return;
    final wanted = <int>{};
    final now = DateTime.now();
    for (final e in events) {
      if (e.deleted) continue;
      final fireAt = reminderTimeFor(e, now);
      if (fireAt == null) continue;
      wanted.add(notificationIdFor(e.id));
      await scheduleFor(e);
    }
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (!wanted.contains(p.id)) await _plugin.cancel(p.id);
    }
  }

  static String _formatWhen(Event event) {
    final bits = <String>[];
    if (!event.allDay && event.startMinutes != null) {
      final h = event.startMinutes! ~/ 60;
      final m = event.startMinutes! % 60;
      final ampm = h >= 12 ? 'PM' : 'AM';
      final h12 = h % 12 == 0 ? 12 : h % 12;
      bits.add('$h12:${m.toString().padLeft(2, '0')} $ampm');
    } else {
      bits.add('All day');
    }
    if (event.location != null && event.location!.isNotEmpty) {
      bits.add(event.location!);
    }
    return bits.join(' • ');
  }
}

/// Reminder choices shown in the event sheet (minutes before start).
/// Null = no reminder.
const List<(int?, String)> reminderOptions = [
  (null, 'OFF'),
  (5, '5 MIN'),
  (15, '15 MIN'),
  (30, '30 MIN'),
  (60, '1 HR'),
  (1440, '1 DAY'),
];

/// Default for new events (assistant default — Joey hasn't chosen).
const int defaultReminderMinutes = 15;
