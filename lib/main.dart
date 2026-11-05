import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/providers.dart';
import 'notifications/notification_service.dart';
import 'widgets/home_widget_service.dart';
import 'theme/app_theme.dart';
import 'theme/clumsy_paper.dart';
import 'widgets/entrances.dart';
import 'screens/calendar_screen.dart';
import 'screens/week_screen.dart';
import 'screens/sync_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Notifications: init the plugin and ask for permission up front
  // so the first event saved can schedule its reminder immediately.
  await NotificationService.init();
  await NotificationService.requestPermission();
  runApp(const ProviderScope(child: RansomCalendarApp()));
}

class RansomCalendarApp extends StatelessWidget {
  const RansomCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ransom Calendar',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      home: const HomeScaffold(),
    );
  }
}

/// Phase 0 home: 3 screens, tabs as individual clumsy scraps
/// pasted at the bottom — no default tab bar, no black bar.
class HomeScaffold extends ConsumerStatefulWidget {
  const HomeScaffold({super.key});

  @override
  ConsumerState<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends ConsumerState<HomeScaffold> {
  int _index = 0;
  static const _screens = [CalendarScreen(), WeekScreen(), SyncScreen()];
  static const _labels = ['CALENDAR', 'WEEK', 'SYNC'];

  @override
  void initState() {
    super.initState();
    // Reconcile alarms with the DB on every cold start: schedule
    // future reminders, drop stale ones (e.g. after reinstall).
    Future.microtask(() async {
      final db = ref.read(databaseProvider);
      final events = await db.allRowsForExport();
      await NotificationService.rescheduleAll(events);
      // Push today's agenda to the home screen widget.
      await HomeWidgetService.refreshFromDb(db);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion: the tab switch is instant.
    final switchDuration = motionOK(context)
        ? const Duration(milliseconds: 350)
        : Duration.zero;
    return Scaffold(
      backgroundColor: AppColors.magenta,
      body: SafeArea(
        // Tabs are a real footer row now, not an overlay: the screens
        // get the remaining space and nothing scrolls underneath.
        child: Column(
          children: [
            Expanded(
              child: DottedBackground(
                child: AnimatedSwitcher(
                  duration: switchDuration,
                  transitionBuilder: (child, animation) =>
                      _TearReveal(animation: animation, child: child),
                  child: KeyedSubtree(
                    key: ValueKey<int>(_index),
                    child: _screens[_index],
                  ),
                ),
              ),
            ),
            // Bottom tabs, individual scraps, active = yellow.
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < _labels.length; i++)
                    Semantics(
                      selected: _index == i,
                      child: ClumsyPaper(
                        color:
                            _index == i ? AppColors.yellow : AppColors.white,
                        seed: 1000 + i,
                        rotationDegrees: i == 0 ? -7 : i == 1 ? 5 : -6,
                        // 48dp+ tap target (was ~42).
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        onTap: () => setState(() => _index = i),
                        semanticLabel: '${_labels[i]} tab',
                        child: Text(
                          _labels[i],
                          style: const TextStyle(
                            fontFamily: 'Anton',
                            fontSize: 18,
                            color: AppColors.black,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen-tear transition for Calendar <-> Week <-> Sync (Phase 2):
/// a diagonal wipe with easeOutCubic plus a slight 0.98 -> 1 scale on
/// the incoming screen. NOT a fade/slide. The outgoing screen tears
/// away in reverse. Cheap: one clip path, no per-frame allocations
/// beyond the path itself.
class _TearReveal extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _TearReveal({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return ClipPath(
          clipper: _DiagonalWipeClipper(t),
          child: Transform.scale(
            scale: 0.98 + 0.02 * t,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _DiagonalWipeClipper extends CustomClipper<Path> {
  final double t;
  const _DiagonalWipeClipper(this.t);

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    // Leading edge sweeps top-left -> bottom-right; overshoots to 1.35
    // so the screen is fully revealed at t = 1.
    final lead = (t * 1.35).clamp(0.0, 1.35) * w;
    final slant = w * 0.22;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(lead, 0)
      ..lineTo((lead - slant).clamp(0.0, w), h)
      ..lineTo(0, h)
      ..close();
  }

  @override
  bool shouldReclip(covariant _DiagonalWipeClipper old) =>
      old.t != t;
}
