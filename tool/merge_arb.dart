// Merges per-feature ARB fragments (l10n/fragments/*_en.arb) into the single
// template lib/l10n/app_en.arb that gen-l10n reads. Run before `flutter gen-l10n`:
//   dart run tool/merge_arb.dart && flutter gen-l10n
import 'dart:convert';
import 'dart:io';

void main() {
  final dir = Directory('l10n/fragments');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('_en.arb')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final merged = <String, dynamic>{'@@locale': 'en'};
  final owner = <String, String>{};
  for (final f in files) {
    final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    for (final e in map.entries) {
      if (e.key == '@@locale') continue;
      if (merged.containsKey(e.key) && !e.key.startsWith('@')) {
        stderr.writeln('Duplicate key "${e.key}" in ${f.path} (already in ${owner[e.key]})');
        exitCode = 1;
        return;
      }
      merged[e.key] = e.value;
      owner[e.key] = f.path;
    }
  }
  const encoder = JsonEncoder.withIndent('  ');
  File('lib/l10n/app_en.arb').writeAsStringSync('${encoder.convert(merged)}\n');
  stdout.writeln('Merged ${files.length} fragments, ${merged.length - 1} entries.');
}
