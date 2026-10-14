import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/theme/tokens.dart';

/// One option of a setting picker: a short label and a one-line explanation.
class Choice<T> {
  const Choice(this.value, this.label, {this.detail});
  final T value;
  final String label;
  final String? detail;
}

/// Drill-in picker, the Settings-app pattern on iOS and a full-screen list on
/// Android. Each option carries its explanation, which an action sheet can't.
/// Returns the chosen value, or null when the user backs out.
Future<T?> pushChoicePage<T>(
  BuildContext context, {
  required String title,
  required List<Choice<T>> choices,
  required T? selected,
  String? footer,
}) {
  Widget page(BuildContext _) => _ChoicePage<T>(title: title, choices: choices, selected: selected, footer: footer);
  return Navigator.of(context).push<T>(
    isCupertino(context) ? CupertinoPageRoute<T>(builder: page) : MaterialPageRoute<T>(builder: page),
  );
}

class _ChoicePage<T> extends StatelessWidget {
  const _ChoicePage({required this.title, required this.choices, required this.selected, this.footer});

  final String title;
  final List<Choice<T>> choices;
  final T? selected;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return EpPage(
      title: title,
      largeTitle: false,
      slivers: [
        SliverToBoxAdapter(
          child: EpSection(
            footer: footer,
            children: [
              for (final ch in choices)
                Semantics(
                  selected: ch.value == selected,
                  inMutuallyExclusiveGroup: true,
                  child: EpTile(
                    title: Text(ch.label),
                    subtitle: ch.detail == null ? null : Text(ch.detail!, maxLines: 3),
                    showChevron: false,
                    trailing: ch.value == selected
                        ? EpIconView(EpIcon.check, color: c.tint)
                        : const SizedBox(width: 24),
                    onTap: () => Navigator.of(context).pop(ch.value),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
