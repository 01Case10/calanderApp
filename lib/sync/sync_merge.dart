import 'package:drift/drift.dart';
import '../data/app_database.dart';
import '../notifications/notification_service.dart';
import '../widgets/home_widget_service.dart';

/// Merge rule (plan QR amendment, both modes, same code):
/// - No local event with that UUID -> insert.
/// - Incoming updatedAt > local updatedAt -> replace (including
///   deleted=true, which deletes locally — a delete syncs as a delete).
/// - Incoming updatedAt <= local -> keep local, ignore incoming.
/// - Incoming householdId differs from mine -> reject outright.
/// Tombstones are honoured, never resurrected.
class MergeResult {
  final int applied;
  final int skipped;
  final int rejected;
  const MergeResult({
    required this.applied,
    required this.skipped,
    required this.rejected,
  });
  int get received => applied + skipped + rejected;
}

Future<MergeResult> mergeDelta(
  AppDatabase db,
  String myHouseholdId,
  List<Map<String, Object?>> remoteEvents,
) async {
  var applied = 0, skipped = 0, rejected = 0;
  for (final m in remoteEvents) {
    final hid = m['hid'] as String?;
    if (hid != null && hid != myHouseholdId) {
      rejected++;
      continue;
    }
    final id = m['id'] as String;
    final incomingTs = (m['updatedAt'] as num).toInt();
    final local = await db.getEvent(id);
    if (local == null || incomingTs > local.updatedAt) {
      await db.upsertEvent(_companionFromSyncMap(m));
      applied++;
      // Keep reminders in sync: schedule for live events, cancel for
      // tombstones (the other phone deleted it).
      final saved = await db.getEvent(id);
      if (saved != null) {
        if (saved.deleted) {
          await NotificationService.cancelFor(id);
        } else {
          await NotificationService.scheduleFor(saved);
        }
      }
    } else {
      skipped++;
    }
  }
  // A merge may have changed today's agenda — refresh the widget.
  if (applied > 0) {
    await HomeWidgetService.refreshFromDb(db);
  }
  return MergeResult(
      applied: applied, skipped: skipped, rejected: rejected);
}

/// One event -> plain JSON-safe map for the wire.
Map<String, Object?> eventToSyncMap(Event e) => {
      'id': e.id,
      'title': e.title,
      'date': e.dateKey,
      'start': e.startMinutes,
      'end': e.endMinutes,
      'allDay': e.allDay,
      'location': e.location,
      'category': e.category,
      'notes': e.notes,
      'createdAt': e.createdAt,
      'updatedAt': e.updatedAt,
      'deviceId': e.deviceId,
      'deleted': e.deleted,
      'hid': e.householdId,
      'reminderMinutes': e.reminderMinutes,
    };

EventsCompanion _companionFromSyncMap(Map<String, Object?> m) {
  return EventsCompanion.insert(
    id: m['id'] as String,
    title: m['title'] as String,
    dateKey: m['date'] as String,
    startMinutes: Value(m['start'] as int?),
    endMinutes: Value(m['end'] as int?),
    allDay: Value(m['allDay'] as bool? ?? false),
    location: Value(m['location'] as String?),
    category: Value(m['category'] as String? ?? 'personal'),
    notes: Value(m['notes'] as String?),
    createdAt: (m['createdAt'] as num).toInt(),
    updatedAt: (m['updatedAt'] as num).toInt(),
    deviceId: Value(m['deviceId'] as String? ?? ''),
    deleted: Value(m['deleted'] as bool? ?? false),
    householdId: Value(m['hid'] as String?),
    reminderMinutes: Value(m['reminderMinutes'] as int?),
  );
}

/// Builds the delta envelope both modes share:
/// { syncId, fromDeviceId, sinceTs, hid, events: [...] }.
/// Includes tombstones (deleted=true) so deletes propagate.
Future<Map<String, Object?>> buildDelta(
  AppDatabase db, {
  required String syncId,
  required String fromDeviceId,
  required String householdId,
  required int sinceTs,
}) async {
  final rows = await db.changesSince(sinceTs);
  return {
    'syncId': syncId,
    'fromDeviceId': fromDeviceId,
    'sinceTs': sinceTs,
    'hid': householdId,
    'events': [for (final e in rows) eventToSyncMap(e)],
  };
}

/// Full export (Mode 2 backup): every row, tombstones included.
Future<Map<String, Object?>> buildFullExport(
  AppDatabase db, {
  required String syncId,
  required String fromDeviceId,
  required String householdId,
}) async {
  final rows = await db.allRowsForExport();
  return {
    'syncId': syncId,
    'fromDeviceId': fromDeviceId,
    'sinceTs': 0,
    'hid': householdId,
    'events': [for (final e in rows) eventToSyncMap(e)],
  };
}

/// Reads the envelope every encrypted payload carries.
class DeltaEnvelope {
  final String syncId;
  final String fromDeviceId;
  final int sinceTs;
  final String householdId;
  final List<Map<String, Object?>> events;
  const DeltaEnvelope({
    required this.syncId,
    required this.fromDeviceId,
    required this.sinceTs,
    required this.householdId,
    required this.events,
  });

  factory DeltaEnvelope.fromJson(Map<String, Object?> json) {
    final hid = json['hid'] as String?;
    if (hid == null || hid.isEmpty) {
      throw const FormatException('delta has no household id');
    }
    return DeltaEnvelope(
      syncId: json['syncId'] as String? ?? '',
      fromDeviceId: json['fromDeviceId'] as String? ?? '',
      sinceTs: (json['sinceTs'] as num?)?.toInt() ?? 0,
      householdId: hid,
      events: [
        for (final e in (json['events'] as List? ?? []))
          (e as Map).cast<String, Object?>(),
      ],
    );
  }
}

/// Sets householdId on rows created before pairing (null householdId).
/// Rows already tagged keep their tag.
Future<void> backfillHousehold(AppDatabase db, String householdId) async {
  await (db.update(db.events)..where((e) => e.householdId.isNull()))
      .write(EventsCompanion(householdId: Value(householdId)));
}
