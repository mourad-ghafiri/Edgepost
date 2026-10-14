import 'package:flutter/material.dart';

import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';

/// One headline figure: a small label over a tabular value.
class BoardField {
  const BoardField(this.label, this.value, {this.semanticValue});
  final String label;
  final String value;

  /// Unabbreviated value for screen readers ("1,234,567" for "1.2M").
  final String? semanticValue;
}

/// The domain's card with its headline traffic figures.
///
/// Same anatomy as a [Strip] (domain glyph, title, values), but the figures
/// sit in a hairline grid that wraps onto a second row on narrow screens and
/// at large text sizes instead of shrinking, so no figure is ever truncated.
class TrafficBoard extends StatelessWidget {
  const TrafficBoard({super.key, required this.title, required this.caption, required this.fields});

  final String title;
  final String caption;
  final List<BoardField> fields;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, box) {
        final perRow = scale > 1.6
            ? 2
            : (box.maxWidth / fields.length >= 84 * scale ? fields.length : 3);
        final rows = [
          for (var i = 0; i < fields.length; i += perRow)
            fields.sublist(i, i + perRow > fields.length ? fields.length : i + perRow),
        ];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(EpRadius.md),
            border: Border.all(color: c.hairline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(EpRadius.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Padding(
                    padding: const EdgeInsets.all(EpSpace.md),
                    child: Row(
                      children: [
                        const FamilyGlyph(family: Family.domains),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: EpType.title(context)),
                              const SizedBox(height: 2),
                              Text(caption, style: EpType.numbers(TextStyle(fontSize: 13, color: c.inkMuted))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final row in rows) ...[
                  Divider(height: 1, thickness: 1, color: c.hairline),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < perRow; i++) ...[
                          if (i > 0) VerticalDivider(width: 1, thickness: 1, color: c.hairline),
                          Expanded(child: i < row.length ? _Cell(field: row[i]) : const SizedBox.shrink()),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.field});
  final BoardField field;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: field.label,
        value: field.semanticValue ?? field.value,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: EpSpace.md, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  field.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: EpType.fieldLabel(context),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(field.value, maxLines: 1, style: EpType.fieldValue(context).copyWith(fontSize: 17)),
                ),
              ],
            ),
          ),
        ),
      );
}
