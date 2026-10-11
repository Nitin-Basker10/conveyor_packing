import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';

/// Telemet / States / Config shell (spec bottom navigation).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({
    super.key,
    required this.telemet,
    required this.states,
    required this.config,
  });

  final Widget telemet;
  final Widget states;
  final Widget config;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [widget.telemet, widget.states, widget.config],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: BorderSide(color: p.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _navItem(p, 0, Icons.tune, 'Telemet'),
                _navItem(p, 1, Icons.sensors, 'States'),
                _navItem(p, 2, Icons.settings_input_component, 'Config'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(Palette p, int index, IconData icon, String label) {
    final selected = _index == index;
    final color = selected ? p.accent : p.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _index = index),
      child: Container(
        width: 72,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? p.raised : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(label.toUpperCase(),
                style: AppText.labelMicro.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}