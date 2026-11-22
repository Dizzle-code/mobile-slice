import 'package:flutter/widgets.dart';

import 'pixel_theme.dart';

class PixelText extends StatelessWidget {
  const PixelText(this.text, {super.key, this.kind = PixelTextKind.body, this.color, this.align, this.maxLines, this.softWrap = true});

  const PixelText.small(this.text, {super.key, this.color, this.align, this.maxLines, this.softWrap = true})
      : kind = PixelTextKind.small;

  const PixelText.heading(this.text, {super.key, this.color, this.align, this.maxLines, this.softWrap = true})
      : kind = PixelTextKind.heading;

  const PixelText.title(this.text, {super.key, this.color, this.align, this.maxLines, this.softWrap = true})
      : kind = PixelTextKind.title;

  const PixelText.display(this.text, {super.key, this.color, this.align, this.maxLines, this.softWrap = true})
      : kind = PixelTextKind.display;

  final String text;
  final PixelTextKind kind;
  final Color? color;
  final TextAlign? align;
  final int? maxLines;
  final bool softWrap;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: PixelTheme.text(kind, color: color ?? PixelColors.text),
        textAlign: align,
        maxLines: maxLines,
        softWrap: softWrap,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      );
}
