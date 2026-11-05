import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ransom_calendar/data/providers.dart';

/// Google Calendar 1:1 interactions: swipe to change month,
/// header tap opens month/year picker, long-press day creates event,
/// tapping an adjacent-month day jumps to that month.
void main() {
  group('DisplayedMonth', () {
    test('jumpTo sets month and selects the 1st', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(displayedMonthProvider.notifier).jumpTo(2025, 3);
      expect(container.read(displayedMonthProvider), DateTime(2025, 3));
      expect(container.read(calendarSelectedDateProvider), '2025-03-01');
    });

    test('showMonth changes month without touching selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(calendarSelectedDateProvider.notifier)
          .select('2026-11-15');
      container.read(displayedMonthProvider.notifier).showMonth(2026, 12);
      expect(container.read(displayedMonthProvider), DateTime(2026, 12));
      expect(container.read(calendarSelectedDateProvider), '2026-11-15');
    });
  });
}