import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_shapes.dart';

/// The passenger app's frame: the current tab above a bottom navigation bar.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const List<_Tab> _tabs = [
    _Tab('Home', Icons.map_outlined, Icons.map_rounded),
    _Tab('Routes', Icons.route_outlined, Icons.route_rounded),
    _Tab('Stops', Icons.location_on_outlined, Icons.location_on_rounded),
    _Tab('Profile', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      // Tapping the current tab again returns it to its first screen.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        // A hairline, not a shadow, separates the bar from the page.
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: current,
          onDestinationSelected: _onDestinationSelected,
          destinations: [
            for (final (index, tab) in _tabs.indexed)
              NavigationDestination(
                // One widget for both states, so the icon can change with
                // a small animation instead of being swapped.
                icon: _TabIcon(tab: tab, isSelected: index == current),
                selectedIcon: _TabIcon(tab: tab, isSelected: index == current),
                label: tab.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon);

  final String label;

  /// Outlined while the tab is not the current one, filled when it is.
  final IconData icon;
  final IconData selectedIcon;
}

/// A tab's icon: the filled one pops in as the tab is chosen, and the
/// outlined one eases back as it is left.
class _TabIcon extends StatelessWidget {
  const _TabIcon({required this.tab, required this.isSelected});

  final _Tab tab;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.quick,
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: AppMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.7, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Icon(
        isSelected ? tab.selectedIcon : tab.icon,
        key: ValueKey(isSelected),
      ),
    );
  }
}
