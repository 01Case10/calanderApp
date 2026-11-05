import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/app_database.dart';
import '../data/providers.dart';
import '../theme/app_theme.dart';
import '../theme/clumsy_paper.dart';
import '../theme/ransom_text.dart';
import '../widgets/add_event_button.dart';
import '../widgets/add_event_sheet.dart';
import '../widgets/entrances.dart';
import '../widgets/event_card.dart';
import '../widgets/markers.dart';

/// Calendar screen — Phase 1: real Drift-backed month grid.
/// Header (light-blue paper, month as letter scraps), prev/next/TODAY,
/// Monday-first grid, diamond markers per event, selected-day list below.
/// Phase 2: entrances (header, weekday row, grid toss on month change,
/// day-list cards rip in alternating sides), cell semantics, 48dp targets.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  static final _monthFmt = DateFormat('MMMM');
  static final _dayFmt = DateFormat('MMMM d');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(displayedMonthProvider);
    final selectedKey = ref.watch(calendarSelectedDateProvider);
    final todayKey = dateKeyOf(DateTime.now());

    // 6 x 7 grid, Monday-first, starting on the Monday of the week
    // that contains the 1st.
    final first = DateTime(month.year, month.month, 1);
    final gridStart =
        first.subtract(Duration(days: (first.weekday - 1) % 7));
    final cells =
        List.generate(42, (i) => gridStart.add(Duration(days: i)));
    final rangeStart = dateKeyOf(cells.first);
    final rangeEnd = dateKeyOf(cells.last);

    final rangeAsync =
        ref.watch(eventsInRangeProvider((start: rangeStart, end: rangeEnd)));
    final dayAsync = ref.watch(eventsForDateProvider(selectedKey));

    final monthName = _monthFmt.format(month).toUpperCase();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        // Header: light-blue clumsy paper, month as letter scraps + year.
        TearIn(
          direction: TearDirection.up,
          child: ClumsyPaper(
            color: AppColors.lightBlue,
            seed: 55,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _showMonthPicker(context, ref, month),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var i = 0; i < monthName.length; i++)
                        RansomScrap(
                          text: monthName[i],
                          index: i,
                          fontSize: 34,
                          paperColor: [
                            AppColors.black,
                            AppColors.magenta,
                            AppColors.white,
                            AppColors.black,
                            AppColors.yellow,
                          ][i % 5],
                        ),
                      const SizedBox(width: 8),
                      RansomScrap(
                        text: '${month.year}',
                        index: 9,
                        fontSize: 24,
                        paperColor: AppColors.white,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _navScrap('◀', () => ref
                        .read(displayedMonthProvider.notifier)
                        .prev()),
                    const SizedBox(width: 8),
                    _navScrap('TODAY', () => ref
                        .read(displayedMonthProvider.notifier)
                        .goToday()),
                    const SizedBox(width: 8),
                    _navScrap('▶', () => ref
                        .read(displayedMonthProvider.notifier)
                        .next()),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'CALENDAR  —  TAP A DATE, THEN + ADD EVENT',
          style: TextStyle(
            fontFamily: 'CourierPrime',
            fontSize: 14,
            color: AppColors.white,
          ),
        ),
        const SizedBox(height: 16),
        // Weekday header, Monday-first (plan §3).
        TearIn(
          delay: const Duration(milliseconds: 40),
          direction: TearDirection.up,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: RansomScrap(
                      text: const [
                        'MON',
                        'TUE',
                        'WED',
                        'THU',
                        'FRI',
                        'SAT',
                        'SUN'
                      ][i],
                      index: i,
                      fontSize: 13,
                      paperColor: const [
                        AppColors.black,
                        AppColors.magenta,
                        AppColors.white,
                        AppColors.black,
                        AppColors.yellow,
                        AppColors.lightBlue,
                        AppColors.black,
                      ][i],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Date grid with markers.
        rangeAsync.when(
          loading: () => const SizedBox(
            height: 300,
            child: Center(
              child: Text(
                'LOADING…',
                style: TextStyle(
                    fontFamily: 'Anton', color: AppColors.white),
              ),
            ),
          ),
          error: (e, _) => _errorScrap('DB ERROR: $e'),
          data: (events) {
            final byDay = <String, List<String>>{};
            for (final ev in events) {
              byDay.putIfAbsent(ev.dateKey, () => []).add(ev.category);
            }
            // Toss in again whenever the month changes (key swap).
            return TearIn(
              key: ValueKey('${month.year}-${month.month}'),
              delay: const Duration(milliseconds: 50),
              direction: TearDirection.up,
              child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: cells.length,
                  itemBuilder: (context, i) {
                    final day = cells[i];
                    final key = dateKeyOf(day);
                    final isToday = key == todayKey;
                    final isSelected = key == selectedKey;
                    final inMonth = day.month == month.month;
                    final cats = byDay[key] ?? const <String>[];
                    return ClumsyPaper(
                      color: isToday
                          ? AppColors.yellow
                          : isSelected
                              ? AppColors.lightBlue
                              : AppColors.white.withValues(
                                  alpha: inMonth ? 1.0 : 0.45),
                      seed: 300 + i,
                      rotationDegrees: 0,
                      padding: EdgeInsets.zero,
                      onTap: () {
                        ref
                            .read(calendarSelectedDateProvider.notifier)
                            .select(key);
                        // Google Calendar: tapping a dimmed
                        // adjacent-month day jumps to that month.
                        if (!inMonth) {
                          ref
                              .read(displayedMonthProvider.notifier)
                              .showMonth(day.year, day.month);
                        }
                      },
                      // Google Calendar: long-press a day to create
                      // an event on that date.
                      onLongPress: () {
                        ref
                            .read(calendarSelectedDateProvider.notifier)
                            .select(key);
                        showEventSheet(context, initialDateKey: key);
                      },
                      semanticLabel:
                          '${_dayFmt.format(day)}, ${cats.length} '
                          '${cats.length == 1 ? 'event' : 'events'}',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontFamily: i % 3 == 0
                                ? 'Anton'
                                : i % 3 == 1
                                    ? 'DMSerif'
                                    : 'CourierPrime',
                            fontSize: isToday || isSelected ? 30 : 26,
                            color: isToday
                                ? AppColors.magenta
                                : AppColors.black.withValues(
                                    alpha: inMonth ? 1.0 : 0.4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        DayMarkers(categories: cats),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        AddEventButton(onTap: () {
          showEventSheet(context, initialDateKey: selectedKey);
        }),
        const SizedBox(height: 20),
        dayAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => _errorScrap('DB ERROR: $e'),
          data: (events) => _dayList(context, selectedKey, events),
        ),
      ],
    );
  }

  Widget _dayList(
      BuildContext context, String selectedKey, List<Event> events) {
    final date = dateOfKey(selectedKey);
    final header =
        '${weekdayScrap(date.weekday)} ${date.day} — ${events.length} '
        '${events.length == 1 ? 'EVENT' : 'EVENTS'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RansomScrap(
          text: header,
          index: selectedKey.hashCode,
          fontSize: 16,
          paperColor: AppColors.black,
        ),
        const SizedBox(height: 16),
        if (events.isEmpty)
          const RansomScrap(
            text: 'NO EVENTS — STEAL SOME TIME BACK',
            index: 4242,
            fontSize: 16,
            paperColor: AppColors.white,
          )
        else
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            // Cards rip in from alternating sides, 80ms stagger.
            TearIn(
              key: ValueKey(events[i].id),
              delay: Duration(milliseconds: i * 80),
              direction:
                  i.isEven ? TearDirection.left : TearDirection.right,
              child: EventCard(
                event: events[i],
                index: i,
                onTap: () {
                  showEventSheet(context,
                      event: events[i], initialDateKey: selectedKey);
                },
              ),
            ),
          ],
      ],
    );
  }

  /// Google Calendar: tapping the month/year header opens a
  /// month/year picker. Ransom-styled: year stepper + 12-month grid.
  void _showMonthPicker(
      BuildContext context, WidgetRef ref, DateTime month) {
    var year = month.year;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ClumsyPaper(
            color: AppColors.white,
            seed: 777,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RansomScrap(
                  text: 'PICK A MONTH',
                  index: 1,
                  fontSize: 20,
                  paperColor: AppColors.black,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClumsyPaper(
                      color: AppColors.lightBlue,
                      seed: 778,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      onTap: () => setState(() => year--),
                      child: const Text('◀',
                          style: TextStyle(
                              fontFamily: 'Anton',
                              fontSize: 18,
                              color: AppColors.black)),
                    ),
                    const SizedBox(width: 12),
                    RansomScrap(
                      text: '$year',
                      index: year,
                      fontSize: 28,
                      paperColor: AppColors.yellow,
                    ),
                    const SizedBox(width: 12),
                    ClumsyPaper(
                      color: AppColors.lightBlue,
                      seed: 779,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      onTap: () => setState(() => year++),
                      child: const Text('▶',
                          style: TextStyle(
                              fontFamily: 'Anton',
                              fontSize: 18,
                              color: AppColors.black)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.2,
                  ),
                  itemCount: 12,
                  itemBuilder: (ctx, i) {
                    final m = i + 1;
                    final isCurrent =
                        m == month.month && year == month.year;
                    return ClumsyPaper(
                      color: isCurrent
                          ? AppColors.magenta
                          : AppColors.white,
                      seed: 800 + i,
                      padding: EdgeInsets.zero,
                      onTap: () {
                        ref
                            .read(displayedMonthProvider.notifier)
                            .jumpTo(year, m);
                        Navigator.of(ctx).pop();
                      },
                      child: Center(
                        child: Text(
                          DateFormat('MMM')
                              .format(DateTime(year, m))
                              .toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Anton',
                            fontSize: 16,
                            color: isCurrent
                                ? AppColors.white
                                : AppColors.black,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navScrap(String text, VoidCallback onTap) {
    return ClumsyPaper(
      color: AppColors.white,
      seed: text.hashCode,
      // 48dp+ tap target (was ~38).
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: onTap,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Anton',
          fontSize: 18,
          color: AppColors.black,
        ),
      ),
    );
  }

  Widget _errorScrap(String text) {
    return RansomScrap(
      text: text,
      index: text.hashCode,
      fontSize: 14,
      paperColor: AppColors.magenta,
    );
  }
}
