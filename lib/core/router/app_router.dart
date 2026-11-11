import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_announcements_screen.dart';
import '../../features/app_update/presentation/app_update_section.dart';
import '../../features/admin/presentation/admin_buses_screen.dart';
import '../../features/admin/presentation/admin_people_screen.dart';
import '../../features/admin/presentation/admin_schedule_screen.dart';
import '../../features/admin/presentation/bus_editor_screen.dart';
import '../../features/admin/presentation/admin_stops_screen.dart';
import '../../features/admin/presentation/stop_editor_screen.dart';
import '../../features/admin/presentation/timetable_editor_screen.dart';
import '../../features/about/presentation/about_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/routes/presentation/routes_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/stops/presentation/stops_screen.dart';
import '../../features/test_drive/presentation/test_drive_screen.dart';
import 'app_routes.dart';

/// The app's navigation graph.
///
/// The four passenger tabs are branches of one stateful shell, so each tab
/// keeps its own state (the map is not rebuilt when the user switches tabs).
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      // Full-screen pages shown over the tabs.
      GoRoute(
        path: AppRoutes.testDrive,
        builder: (context, state) => const TestDriveScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminStops,
        builder: (context, state) => const AdminStopsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminStopEditor,
        builder: (context, state) => StopEditorScreen(
          draft: state.extra is StopDraft ? state.extra! as StopDraft : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.adminAnnouncements,
        builder: (context, state) => const AdminAnnouncementsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminBuses,
        builder: (context, state) => const AdminBusesScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminBusEditor,
        builder: (context, state) => BusEditorScreen(
          draft: state.extra is BusDraft ? state.extra! as BusDraft : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.adminPeople,
        builder: (context, state) => const AdminPeopleScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminSchedule,
        builder: (context, state) => const AdminScheduleScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminTimetableEditor,
        builder: (context, state) => TimetableEditorScreen(
          draft: state.extra is TimetableDraft
              ? state.extra! as TimetableDraft
              : null,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            UpdateLauncher(child: AppShell(navigationShell: navigationShell)),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.routes,
                builder: (context, state) => const RoutesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.stops,
                builder: (context, state) => const StopsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
