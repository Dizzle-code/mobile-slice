import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pixel_icon.dart';
import 'pixel_text.dart';
import 'pixel_theme.dart';

class PixelTabItem {
  const PixelTabItem(this.glyph, this.label);

  final PixelGlyph glyph;
  final String label;
}

/// Desktop navigation down the left edge, same look as [PixelTabBar].
class PixelSideBar extends StatelessWidget {
  const PixelSideBar({super.key, required this.items, required this.index, required this.onSelected});

  final List<PixelTabItem> items;

  /// -1 when no item is selected.
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      decoration: const BoxDecoration(
        color: PixelColors.panel,
        border: Border(right: BorderSide(color: PixelColors.shadow, width: PixelTheme.unit)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) _item(i),
        ],
      ),
    );
  }

  Widget _item(int i) {
    final selected = i == index;
    final item = items[i];
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: () => onSelected(i),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelected(i),
          child: Container(
            height: 76,
            decoration: BoxDecoration(
              color: selected ? PixelColors.background : null,
              border: Border(left: BorderSide(color: selected ? PixelColors.accent : PixelColors.panel, width: PixelTheme.unit)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PixelIcon(
                  item.glyph,
                  scale: 2,
                  color: selected ? PixelColors.text : PixelColors.muted,
                  secondColor: selected ? PixelColors.accent : PixelColors.muted,
                ),
                const SizedBox(height: 4),
                PixelText.small(item.label, color: selected ? PixelColors.accent : PixelColors.muted, maxLines: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom navigation; the selected icon hops up once when chosen.
class PixelTabBar extends StatelessWidget {
  const PixelTabBar({super.key, required this.items, required this.index, required this.onSelected});

  final List<PixelTabItem> items;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: PixelColors.panel,
        border: Border(top: BorderSide(color: PixelColors.shadow, width: PixelTheme.unit)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) Expanded(child: _tab(i)),
        ],
      ),
    );
  }

  Widget _tab(int i) {
    final selected = i == index;
    final item = items[i];
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: () => onSelected(i),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!selected) HapticFeedback.selectionClick();
          onSelected(i);
        },
        child: SizedBox(
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                key: ValueKey(selected),
                tween: Tween(begin: selected ? 1 : 0, end: 0),
                duration: const Duration(milliseconds: 240),
                builder: (context, hop, child) =>
                    Transform.translate(offset: Offset(0, -(hop * 2).round() * PixelTheme.unit), child: child),
                child: PixelIcon(
                  item.glyph,
                  scale: 2,
                  color: selected ? PixelColors.text : PixelColors.muted,
                  secondColor: selected ? PixelColors.accent : PixelColors.muted,
                ),
              ),
              PixelText.small(item.label, color: selected ? PixelColors.accent : PixelColors.muted, maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}
