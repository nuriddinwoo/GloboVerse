import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_background.dart';
import '../../l10n/l10n_state.dart';
import '../connect/connect_screen.dart';
import '../profile/profile_screen.dart';
import '../translate/translate_screen.dart';
import 'home_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  void _select(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_selectedIndex != value) setState(() => _selectedIndex = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<L10nState>();
    final screens = [
      HomeScreen(
        onConnect: () => _select(2),
        onTranslate: () => _select(1),
      ),
      const TranslateScreen(),
      const ConnectScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      extendBody: true,
      body: AppBackground(
        child: IndexedStack(index: _selectedIndex, children: screens),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: const Border(top: BorderSide(color: AppColors.divider)),
          boxShadow: [
            BoxShadow(
              color: AppColors.background.withValues(alpha: 0.72),
              blurRadius: 22,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _select,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded, color: AppColors.primaryBright),
              label: l10n.t('home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.translate_outlined),
              selectedIcon: const Icon(Icons.translate_rounded, color: AppColors.primaryBright),
              label: l10n.t('translate'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.travel_explore_outlined),
              selectedIcon: const Icon(Icons.travel_explore_rounded, color: AppColors.primaryBright),
              label: l10n.t('connect'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded, color: AppColors.primaryBright),
              label: l10n.t('profile'),
            ),
          ],
        ),
      ),
    );
  }
}
