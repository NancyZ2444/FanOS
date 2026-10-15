import 'package:fan_os/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  const MainShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: navigationShell.currentIndex == 2
          ? null
          : DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: FanColors.line)),
              ),
              child: NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _goBranch,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: '首页',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_stories_outlined),
                    selectedIcon: Icon(Icons.auto_stories_rounded),
                    label: '图鉴',
                  ),
                  NavigationDestination(
                    icon: _ScanNavIcon(selected: false),
                    selectedIcon: _ScanNavIcon(selected: true),
                    label: '扫描',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.favorite_border_rounded),
                    selectedIcon: Icon(Icons.favorite_rounded),
                    label: '收藏',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: '我的',
                  ),
                ],
              ),
            ),
    );
  }
}

class _ScanNavIcon extends StatelessWidget {
  const _ScanNavIcon({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 30,
      decoration: BoxDecoration(
        color: selected ? FanColors.ink : const Color(0xFFEEF0F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.document_scanner_outlined,
        color: selected ? Colors.white : FanColors.ink,
        size: 20,
      ),
    );
  }
}
