import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/friends/friends_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../shared/widgets/app_bottom_navigation.dart';
import '../state/app_view_model.dart';

/// Three tabs with a fixed bottom navigation, plus the foreground polling that
/// keeps friends, matches and knocks fresh.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
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
      1 => const FriendsScreen(),
      2 => const ProfileScreen(),
      _ => const HomeScreen(),
    };
    return Scaffold(
      body: SafeArea(bottom: false, child: page),
      bottomNavigationBar: AppBottomNavigation(
        selectedIndex: _selectedIndex,
        onSelected: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}
