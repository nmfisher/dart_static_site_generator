import 'dart:convert';
import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// End-to-end coverage for the CLI overwrite guard (--force) and the
/// --backup flag. Each case spawns the real CLI in a fresh temp directory.
class CliRun {
  final int exitCode;
  final String stdout;
  final String stderr;
  const CliRun(this.exitCode, this.stdout, this.stderr);
}

void main() {
  late io.Directory temp;
  late String input;
  late String output;

  setUp(() async {
    temp = await io.Directory.systemTemp.createTemp('blog-overwrite-test-');
    input = path.join(temp.path, 'input');
    output = path.join(temp.path, 'output');
    io.Directory(path.join(input, 'content')).createSync(recursive: true);
    io.File(path.join(input, 'config.yaml')).writeAsStringSync(
        'title: Test\nowner: Owner\nbaseUrl: https://example.com/\n');
    io.File(path.join(input, 'content', 'index.md')).writeAsStringSync(
        '---\ntitle: Home\npublished: true\n---\nHello');
  });

  tearDown(() => temp.delete(recursive: true));

  Future<CliRun> runCli(List<String> extra, {String? stdinText}) async {
    final process = await io.Process.start(io.Platform.resolvedExecutable, [
      '--packages=${path.absolute('.dart_tool/package_config.json')}',
      path.absolute('bin/blog_builder.dart'),
      '--input',
      input,
      '--output',
      output,
      '--no-announce',
      ...extra
    ]);
    if (stdinText != null) process.stdin.writeln(stdinText);
    await process.stdin.close();
    final stdoutText =
        await process.stdout.transform(utf8.decoder).join();
    final stderrText =
        await process.stderr.transform(utf8.decoder).join();
    return CliRun(await process.exitCode, stdoutText, stderrText);
  }

  test('first build into a fresh directory needs no consent', () async {
    final run = await runCli([]);
    expect(run.exitCode, 0, reason: 'stderr: ${run.stderr}');
    expect(io.File(path.join(output, 'index.html')).existsSync(), isTrue);
  });

  test('declined prompt aborts and preserves existing output', () async {
    await runCli([]);
    final marker = io.File(path.join(output, 'sentinel.txt'))
      ..writeAsStringSync('keep me');
    final run = await runCli([]);
    expect(run.exitCode, 0, reason: 'stderr: ${run.stderr}');
    expect(run.stdout, contains('Output directory exists'));
    expect(run.stdout, contains('aborted'));
    expect(marker.readAsStringSync(), 'keep me');
  });

  test('answering yes proceeds', () async {
    await runCli([]);
    final run = await runCli([], stdinText: 'y');
    expect(run.exitCode, 0, reason: 'stderr: ${run.stderr}');
    expect(io.File(path.join(output, 'index.html')).existsSync(), isTrue);
  });

  test('--force skips the prompt and overwrites', () async {
    await runCli([]);
    io.File(path.join(output, 'sentinel.txt')).writeAsStringSync('stale');
    final run = await runCli(['--force']);
    expect(run.exitCode, 0, reason: 'stderr: ${run.stderr}');
    expect(run.stdout, contains('--force'));
    expect(io.File(path.join(output, 'sentinel.txt')).existsSync(), isFalse);
  });

  test('--backup keeps the replaced output as a sibling', () async {
    await runCli([]);
    io.File(path.join(output, 'sentinel.txt')).writeAsStringSync('previous');
    final run = await runCli(['--force', '--backup']);
    expect(run.exitCode, 0, reason: 'stderr: ${run.stderr}');
    expect(run.stdout, contains('Kept backup of previous output'));
    final siblings = io.Directory(temp.path)
        .listSync()
        .whereType<io.Directory>()
        .where((d) => path.basename(d.path).startsWith('output-backup-'))
        .toList();
    expect(siblings, hasLength(1));
    expect(
        io.File(path.join(siblings.single.path, 'sentinel.txt'))
            .readAsStringSync(),
        'previous');
  });

  test('check does not prompt even with existing output', () async {
    await runCli([]);
    final run = await runCli(['check']);
    expect(run.exitCode, 0, reason: 'stderr: ${run.stderr}');
    expect(run.stdout, isNot(contains('Output directory exists')));
  });
}
