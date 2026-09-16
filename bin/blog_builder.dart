import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:blog_builder/src/static_site_builder.dart';
import 'package:blog_builder/src/preview_server.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('input',
        abbr: 'i', defaultsTo: 'example_blog', help: 'Site source directory')
    ..addOption('output',
        abbr: 'o', defaultsTo: 'build', help: 'Generated site directory')
    ..addFlag('watch',
        abbr: 'w',
        negatable: false,
        help: 'Rebuild on edits without announcing posts')
    ..addFlag('serve',
        negatable: false,
        help: 'Serve and watch with live reload; disables announcements')
    ..addFlag('drafts',
        negatable: false, help: 'Include drafts; disables announcements')
    ..addFlag('incremental',
        defaultsTo: true,
        help: 'Reuse the persistent content/template/image cache')
    ..addFlag('announce',
        defaultsTo: true,
        help: 'Create missing Bluesky anchor posts on production builds')
    ..addOption('host', defaultsTo: '127.0.0.1')
    ..addOption('port', defaultsTo: '8080')
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final options = parser.parse(args);
    if (options['help'] as bool) {
      print(
          'Usage: dart run bin/blog_builder.dart [build|check] [options]\n${parser.usage}');
      return;
    }
    final command = options.rest.isEmpty ? 'build' : options.rest.single;
    if (!['build', 'check'].contains(command))
      throw ArgumentError('Unknown command: $command');
    final input = options['input'] as String;
    final output = options['output'] as String;
    if (!await Directory(input).exists())
      throw ArgumentError('Input directory not found: $input');
    final serve = options['serve'] as bool;
    final watch = serve || options['watch'] as bool;
    final drafts = options['drafts'] as bool;
    if (command == 'check' && watch)
      throw ArgumentError('check cannot be combined with --serve or --watch');
    final port = int.tryParse(options['port'] as String);
    if (port == null || port < 0 || port > 65535)
      throw ArgumentError('port must be between 0 and 65535');
    final builder = StaticSiteBuilder(
        inputDir: input,
        outputDir: output,
        preview: watch || drafts,
        includeDrafts: drafts,
        incremental: options['incremental'] as bool,
        announce: options['announce'] as bool);
    if (command == 'check') {
      final issues = await builder.check();
      for (final issue in issues) {
        stderr.writeln(issue);
      }
      print(issues.isEmpty
          ? 'Check passed.'
          : 'Check failed: ${issues.length} issue(s).');
      if (issues.isNotEmpty) exitCode = 1;
      return;
    }
    PreviewServer? server;
    Future<void> rebuild() async {
      final timer = Stopwatch()..start();
      await builder.build();
      server?.basePath = builder.siteConfig.basePath;
      server?.changed();
      print(
          'Build completed in ${timer.elapsedMilliseconds}ms → ${p.absolute(output)}');
      final cache = builder.cache;
      print(
          'Cache hits: ${cache.parsedHits} parsed pages, ${cache.contentHits} content, ${cache.layoutHits} layouts, ${cache.assetHits} assets');
    }

    try {
      await rebuild();
    } catch (error) {
      stderr.writeln('Build failed: $error');
      if (!watch) {
        exitCode = 1;
        return;
      }
    }
    if (!watch) return;
    if (serve) {
      var basePath = '';
      try {
        basePath = builder.siteConfig.basePath;
      } catch (_) {}
      server = PreviewServer(p.absolute(output), basePath: basePath);
      await server.start(host: options['host'] as String, port: port);
      print('Preview: http://${options['host']}:${server.port}$basePath/');
    }
    print('Watching ${p.absolute(input)}. Press Ctrl+C to stop.');
    final queue = RebuildQueue(rebuild, onError: (error) {
      stderr.writeln('Build failed: $error');
      server?.failed(error);
    });
    Timer? debounce;
    final root = p.absolute(input);
    final destination = p.absolute(output);
    final watcher = Directory(input).watch(recursive: true).listen((event) {
      final absolute = p.absolute(event.path);
      final relative = p.relative(absolute, from: root);
      if (p.equals(absolute, destination) ||
          p.isWithin(destination, absolute) ||
          p.split(relative).any((part) => part.startsWith('.')) ||
          relative.endsWith('.tmp') ||
          relative.endsWith('~')) return;
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 200), () {
        unawaited(queue.request());
      });
    });
    final stopped = Completer<void>();
    final signal = ProcessSignal.sigint.watch().listen((_) {
      if (!stopped.isCompleted) stopped.complete();
    });
    await stopped.future;
    debounce?.cancel();
    await watcher.cancel();
    await queue.idle;
    await signal.cancel();
    await server?.close();
  } catch (error) {
    stderr.writeln('Build failed: $error');
    exitCode = 1;
  }
}
