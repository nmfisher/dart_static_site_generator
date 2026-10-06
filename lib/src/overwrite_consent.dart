import 'dart:async';
import 'dart:io' show StdinException, stdin;

/// Result of the overwrite-consent flow.
enum OverwriteDecision { proceed, abort }

/// Interactive guard for builds that would replace an existing output
/// directory. Skips the prompt entirely when [force] is set (the same flag
/// also signals "don't ask, don't check" downstream).
///
/// Returns [OverwriteDecision.abort] when the user declines, when stdin is
/// unavailable (CI), or when EOF is hit, so an unattended run never destroys
/// data. [lines] and [write] are injectable for tests.
Future<OverwriteDecision> confirmOutputOverwrite({
  required String outputDir,
  required bool force,
  Stream<String>? lines,
  void Function(String)? write,
}) async {
  final emit = write ?? (m) => print(m);
  if (force) {
    emit('--force: overwriting $outputDir without asking');
    return OverwriteDecision.proceed;
  }
  emit('Output directory exists: $outputDir');
  emit('The build will replace its contents.');
  emit('Proceed and overwrite? [y/N]');
  final answer = await _readAnswer(lines: lines);
  if (answer == null) {
    emit('No interactive input; build aborted. Re-run with --force to overwrite.');
    return OverwriteDecision.abort;
  }
  final normalized = answer.trim().toLowerCase();
  if (normalized == 'y' || normalized == 'yes') return OverwriteDecision.proceed;
  emit('Build aborted; existing output left untouched.');
  return OverwriteDecision.abort;
}

Future<String?> _readAnswer({Stream<String>? lines}) async {
  if (lines != null) {
    try {
      await for (final line in lines) {
        return line;
      }
    } on StdinException {
      return null;
    }
    return null; // EOF without an answer
  }
  try {
    return stdin.readLineSync();
  } on StdinException {
    return null; // stdin unavailable (e.g. CI)
  }
}
