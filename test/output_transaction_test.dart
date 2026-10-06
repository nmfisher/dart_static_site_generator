import 'dart:io' as io;
import 'package:blog_builder/src/output_transaction.dart';
import 'package:blog_builder/src/overwrite_consent.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  group('OutputTransaction', () {
    late MemoryFileSystem fs;
    late String destination;

    setUp(() {
      fs = MemoryFileSystem();
      destination = '/project/output';
      fs.directory('/project').createSync(recursive: true);
    });

    Future<OutputTransaction> staged({bool keepBackup = false}) async {
      final transaction =
          OutputTransaction(fs, destination, keepBackup: keepBackup);
      final staging = await transaction.begin();
      fs.file(fs.path.join(staging, 'index.html'))
          .writeAsStringSync('<html>new</html>');
      return transaction;
    }

    void seedOutput(String name, String content) {
      fs.file('/project/output/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    test('default commit deletes the previous output', () async {
      seedOutput('old.txt', 'old');
      final transaction = await staged();
      await transaction.commit();
      expect(fs.file('/project/output/index.html').readAsStringSync(),
          '<html>new</html>');
      expect(fs.file('/project/output/old.txt').existsSync(), isFalse);
      expect(fs.directory('/project').listSync().where((e) =>
          fs.path.basename(e.path).contains('backup')), isEmpty);
    });

    test('keepBackup preserves the previous output as a sibling', () async {
      seedOutput('old.txt', 'old');
      final transaction = await staged(keepBackup: true);
      await transaction.commit();
      expect(fs.file('/project/output/index.html').existsSync(), isTrue);
      final backups = fs
          .directory('/project')
          .listSync()
          .whereType<Directory>()
          .where((e) => fs.path.basename(e.path).startsWith('output-backup-'))
          .toList();
      expect(backups, hasLength(1));
      expect(
          fs.file(fs.path.join(backups.single.path, 'old.txt'))
              .readAsStringSync(),
          'old');
    });

    test('keepBackup stamps are unique across successive commits', () async {
      seedOutput('a.txt', 'a');
      final first = await staged(keepBackup: true);
      await first.commit();
      fs.directory('/project/output').createSync(recursive: true);
      fs.file('/project/output/b.txt').writeAsStringSync('b');
      final second = await staged(keepBackup: true);
      await second.commit();
      final backups = fs
          .directory('/project')
          .listSync()
          .whereType<Directory>()
          .where((e) => fs.path.basename(e.path).startsWith('output-backup-'))
          .toList();
      expect(backups, hasLength(2));
      final names = backups.map((d) => fs.path.basename(d.path)).toSet();
      expect(names, hasLength(2));
    });

    test('commit with no prior output needs no backup', () async {
      final transaction = await staged(keepBackup: true);
      await transaction.commit();
      expect(fs.file('/project/output/index.html').existsSync(), isTrue);
      expect(fs.directory('/project').listSync().where((e) =>
          fs.path.basename(e.path).startsWith('output-backup-')), isEmpty);
    });

    test('staging failure leaves prior output untouched', () async {
      seedOutput('old.txt', 'old');
      final transaction = OutputTransaction(fs, destination);
      await transaction.begin();
      // Simulate a build crash by discarding instead of committing.
      await transaction.discard();
      expect(fs.file('/project/output/old.txt').readAsStringSync(), 'old');
    });
  });

  group('confirmOutputOverwrite', () {
    late List<String> printed;

    void write(String message) => printed.add(message);

    setUp(() => printed = []);

    test('force proceeds without needing input', () async {
      final decision = await confirmOutputOverwrite(
          outputDir: '/site/build',
          force: true,
          lines: const Stream.empty(),
          write: write);
      expect(decision, OverwriteDecision.proceed);
      expect(printed.join('\n'), contains('--force'));
    });

    test('yes variants proceed', () async {
      for (final answer in ['y', 'Y', 'yes', 'YES', ' yes ']) {
        printed = [];
        final decision = await confirmOutputOverwrite(
            outputDir: '/site/build',
            force: false,
            lines: Stream.value(answer),
            write: write);
        expect(decision, OverwriteDecision.proceed, reason: 'answer: $answer');
      }
    });

    test('non-affirmative answers abort', () async {
      for (final answer in ['n', 'no', '', 'overwrite', '0']) {
        final decision = await confirmOutputOverwrite(
            outputDir: '/site/build',
            force: false,
            lines: Stream.value(answer),
            write: write);
        expect(decision, OverwriteDecision.abort, reason: 'answer: $answer');
        expect(printed.join('\n'), contains('aborted'));
      }
    });

    test('EOF aborts with a --force hint', () async {
      final decision = await confirmOutputOverwrite(
          outputDir: '/site/build',
          force: false,
          lines: const Stream<String>.empty(),
          write: write);
      expect(decision, OverwriteDecision.abort);
      expect(printed.join('\n'), contains('--force'));
    });

    test('stdin error aborts instead of crashing', () async {
      final decision = await confirmOutputOverwrite(
          outputDir: '/site/build',
          force: false,
          lines: Stream<String>.error(
              const io.StdinException('closed', io.OSError('no handle', 9))),
          write: write);
      expect(decision, OverwriteDecision.abort);
    });

    test('prompt names the output directory', () async {
      await confirmOutputOverwrite(
          outputDir: '/site/build',
          force: false,
          lines: Stream.value('y'),
          write: write);
      expect(printed.join('\n'), contains('/site/build'));
    });
  });
}
