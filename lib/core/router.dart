import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/role_selection_screen.dart';
import '../screens/provider/provider_dashboard.dart';
import '../screens/provider/provider_appointments.dart';
import '../screens/provider/provider_profile.dart';
import '../screens/receiver/receiver_dashboard.dart';
import '../screens/receiver/receiver_appointments.dart';
import '../screens/receiver/receiver_profile.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../models/user_model.dart';

// Shell routes for navigation bars
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({
    required this.navigationShell,
    Key? key,
  }) : super(key: key ?? const ValueKey<String>('ScaffoldWithNavBar'));

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final userRole = context.watch<AuthProvider>().currentUser?.role ?? UserRole.receiver;
    
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        destinations: userRole == UserRole.provider
            ? const [
                NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
                NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'Appointments'),
                NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
              ]
            : const [
                NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search), label: 'Find Service'),
                NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'My Bookings'),
                NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
              ],
        onDestinationSelected: (int index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}

final goRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/role-selection',
      builder: (context, state) => const RoleSelectionScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ScaffoldWithNavBar(navigationShell: navigationShell);
      },
      branches: [
        // Branch 0: Dashboard (Provider or Receiver)
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) {
                final role = context.watch<AuthProvider>().currentUser?.role;
                if (role == UserRole.provider) {
                  return const ProviderDashboard();
                } else {
                  return const ReceiverDashboard();
                }
              },
            ),
          ],
        ),
        // Branch 1: Appointments
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/appointments',
              builder: (context, state) {
                final role = context.watch<AuthProvider>().currentUser?.role;
                if (role == UserRole.provider) {
                  return const ProviderAppointmentsScreen();
                } else {
                  return const ReceiverAppointmentsScreen();
                }
              },
            ),
          ],
        ),
        // Branch 2: Profile
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) {
                final role = context.watch<AuthProvider>().currentUser?.role;
                if (role == UserRole.provider) {
                  return const ProviderProfileScreen();
                } else {
                  return const ReceiverProfileScreen();
                }
              },
            ),
          ],
        ),
      ],
    ),
  ],
  redirect: (context, state) {
    final authProvider = context.read<AuthProvider>();
    final isLoggedIn = authProvider.isAuthenticated;
    final isGoingToLogin = state.uri.toString() == '/login';
    
    if (!isLoggedIn && !isGoingToLogin) {
      return '/login';
    }
    
    if (isLoggedIn && isGoingToLogin) {
      return '/role-selection';
    }
    
    return null;
  },
);
