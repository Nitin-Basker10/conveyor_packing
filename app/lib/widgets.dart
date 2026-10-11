import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

const double kRadius = 4;
const double kRadiusSm = 2;

/// 1px structural hairline (DESIGN.md "Hairline Division").
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = false});
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final c = context.palette.hairline;
    return vertical
        ? SizedBox(width: 1, child: ColoredBox(color: c))
        : SizedBox(height: 1, child: ColoredBox(color: c));
  }
}

/// Instrument card / sub-rack: surface fill with a 1px perimeter border.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(0),
    this.radius = 8,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: border ? Border.all(color: p.hairline, width: 1) : null,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Flush sub-rack header strip (spec: `bg-surface-container border-b` strip at
/// the top of a card). Title micro-label on variant, trailing micro on outline.
class SubHeaderStrip extends StatelessWidget {
  const SubHeaderStrip({
    super.key,
    required this.title,
    this.trailing,
    this.icon,
    this.tint,
  });

  final String title;
  final String? trailing;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: tint ?? p.textSecondary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: AppText.labelCaps.copyWith(color: p.textSecondary),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: AppText.readoutMicro.copyWith(color: p.textFaint),
            ),
        ],
      ),
    );
  }
}

/// Small bordered tag (spec chips: "NOMINAL SYNC", "SAVED", "STATE 00 // IDLE").
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, this.color, this.border = true});

  final String label;
  final Color? color;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: p.inset,
        border: border ? Border.all(color: color ?? p.hairline) : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppText.labelMicro.copyWith(color: color ?? p.textFaint),
      ),
    );
  }
}

/// Recessed input well (spec: `bg-surface-container-lowest border`).
class InputWell extends StatelessWidget {
  const InputWell({
    super.key,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.suffix,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final outline = OutlineInputBorder(
      borderSide: BorderSide(color: p.hairline),
      borderRadius: BorderRadius.circular(8),
    );
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      style: AppText.readoutSecondary.copyWith(color: p.text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.readoutSecondary.copyWith(color: p.textFaint),
        filled: true,
        fillColor: p.inset,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: suffix,
        enabledBorder: outline,
        focusedBorder: outline.copyWith(
            borderSide: BorderSide(color: p.accent, width: 1)),
      ),
    );
  }
}

/// Recessed segmented selector (spec interval/theme pickers).
class SegmentedSelector<T> extends StatelessWidget {
  const SegmentedSelector({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String, IconData?)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: p.inset,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 1),
                child: _Segment(
                  label: options[i].$2,
                  icon: options[i].$3,
                  selected: value == options[i].$1,
                  onTap: () => onChanged(options[i].$1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? p.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15,
                  color: selected ? p.onAccent : p.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label.toUpperCase(),
              style: AppText.buttonText.copyWith(
                color: selected ? p.onAccent : p.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Module header bar (uppercase title + index tag), separated by a hairline.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    this.tag,
    this.icon,
    this.tint,
  });

  final String title;
  final String? tag;
  final IconData? icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: tint ?? p.textSecondary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: AppText.labelCaps.copyWith(color: p.textSecondary),
            ),
          ),
          if (tag != null)
            Text(
              tag!,
              style: AppText.labelMicro.copyWith(color: p.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// A single label/value readout row, monospace + tabular figures.
class ReadoutRow extends StatelessWidget {
  const ReadoutRow({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.valueColor,
    this.large = false,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? valueColor;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = large
        ? AppText.dispNumeric.copyWith(fontSize: 34)
        : AppText.readoutSecondary.copyWith(fontSize: 14);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: AppText.labelCaps.copyWith(color: p.textSecondary),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: style.copyWith(color: valueColor ?? p.text)),
              if (unit != null)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Text(
                    unit!,
                    style: AppText.labelMicro.copyWith(color: p.textSecondary),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Recessed table of readouts divided by hairlines.
class ReadoutTable extends StatelessWidget {
  const ReadoutTable({super.key, required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(Hairline());
      children.add(rows[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border.all(color: p.hairline),
        borderRadius: BorderRadius.circular(kRadiusSm),
      ),
      child: Column(children: children),
    );
  }
}

/// State row, framed between two hairlines (dashboard).
class StateRow extends StatelessWidget {
  const StateRow({super.key, required this.state});

  final ConveyorState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = state.color(p);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.hairline), bottom: BorderSide(color: p.hairline)),
      ),
      child: Row(
        children: [
          Container(width: 8, height: 8, color: color),
          const SizedBox(width: 8),
          Text(
            state.label,
            style: AppText.panelTitle.copyWith(fontSize: 15, color: p.text),
          ),
        ],
      ),
    );
  }
}

/// 10-cell segmented large-box gauge.
class LargeBoxBar extends StatelessWidget {
  const LargeBoxBar({super.key, required this.filled});

  final int filled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final count = filled.clamp(0, ConveyorStatus.boxesPerLargeBox);
    return Row(
      children: List.generate(ConveyorStatus.boxesPerLargeBox, (i) {
        final on = i < count;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == ConveyorStatus.boxesPerLargeBox - 1 ? 0 : 4),
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: on ? p.text : Colors.transparent,
                border: on ? null : Border.all(color: p.hairline),
                borderRadius: BorderRadius.circular(kRadiusSm),
              ),
            ),
          ),
        );
      }),
    );
  }
}

enum _BtnKind { primary, secondary, emergency }

/// Actuator button (PRD design "Actuator Buttons").
class ActionButton extends StatelessWidget {
  const ActionButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.subLabel,
    this.height = 44,
  }) : _kind = _BtnKind.primary;

  const ActionButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.subLabel,
    this.height = 44,
  }) : _kind = _BtnKind.secondary;

  const ActionButton.emergency({
    super.key,
    required this.label,
    this.onPressed,
    this.subLabel,
    this.height = 48,
  }) : _kind = _BtnKind.emergency;

  final String label;
  final String? subLabel;
  final VoidCallback? onPressed;
  final double height;
  final _BtnKind _kind;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final disabled = onPressed == null;

    late Color bg;
    late Color fg;
    late Color border;
    switch (_kind) {
      case _BtnKind.primary:
        bg = p.accent;
        fg = p.onAccent;
        border = p.accent;
        break;
      case _BtnKind.secondary:
        bg = Colors.transparent;
        fg = p.text;
        border = p.hairline;
        break;
      case _BtnKind.emergency:
        bg = p.fault;
        fg = p.text;
        border = p.fault;
        break;
    }

    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(kRadius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(kRadius),
          child: Container(
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(kRadius),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppText.buttonText.copyWith(color: fg),
                ),
                if (subLabel != null)
                  Text(
                    subLabel!,
                    style: AppText.labelMicro.copyWith(
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Industrial toggle switch (settings "AUTOMATIC REFRESH").
class IndustrialSwitch extends StatelessWidget {
  const IndustrialSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Container(
        width: 48,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: p.inset,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: p.hairline),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: value ? p.accent : p.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// A label/value tile used in grid readouts.
class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, this.unit, this.valueColor});
  final String label;
  final String value;
  final String? unit;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: AppText.labelMicro.copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    style: AppText.readoutSecondary
                        .copyWith(color: valueColor ?? p.text)),
              ),
              if (unit != null)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Text(unit!,
                      style: AppText.labelMicro.copyWith(color: p.textSecondary)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
