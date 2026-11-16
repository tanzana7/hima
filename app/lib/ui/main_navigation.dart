import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_view_model.dart';
import 'screens/home_screen.dart';
import 'screens/knocks_screen.dart';
import 'screens/people_screen.dart';
import 'screens/settings_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  AppViewModel? _viewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = context.read<AppViewModel>();
    if (_viewModel != current) {
      _viewModel?.stopPolling();
      _viewModel = current;
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        current.startPolling();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final viewModel = _viewModel;
    if (viewModel == null) return;
    if (state == AppLifecycleState.resumed) {
      viewModel.startPolling();
    } else {
      viewModel.stopPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel?.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = switch (_selectedIndex) {
      0 => const HomeScreen(),
      1 => const PeopleScreen(),
      2 => const KnocksScreen(),
      _ => const SettingsScreen(),
    };
    return Scaffold(
      body: SafeArea(child: page),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'ホーム',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'みんな',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none_rounded),
            selectedIcon: Icon(Icons.notifications_rounded),
            label: 'ノック',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
