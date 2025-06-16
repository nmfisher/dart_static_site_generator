import 'dart:io';
import 'dart:async';
import 'package:blog_builder/src/static_site_builder.dart';
import 'package:path/path.dart' as pathlib;
import 'package:args/args.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('input',
        abbr: 'i',
        help:
            'Input directory containing config.yaml, content/, templates/, assets/',
        defaultsTo: 'example_blog')
    ..addOption('output',
        abbr: 'o',
        help: 'Output directory for generated site',
        defaultsTo: 'build')
    ..addFlag('watch',
        abbr: 'w',
        help: 'Watch for changes and rebuild automatically',
        negatable: false)
    ..addFlag('help',
        abbr: 'h', help: 'Show usage information', negatable: false);

  ArgResults results;
  try {
    results = parser.parse(args);

    if (results['help'] as bool) {
      print('Static Site Generator for Markdown Blogs');
      print('Usage: dart run bin/blog_builder.dart [options]');
      print(parser.usage);
      exit(0);
    }
  } catch (e) {
    print('Error parsing arguments: $e');
    print(parser.usage);
    exit(1);
  }

  final inputDir = results['input'] as String;
  final outputDir = results['output'] as String;
  final watchMode = results['watch'] as bool;

  if (!await Directory(inputDir).exists()) {
    print('Error: Input directory not found: $inputDir');
    exit(1);
  }

  final siteBuilder = StaticSiteBuilder(
    inputDir: inputDir,
    outputDir: outputDir,
  );

  // Initial build
  await buildSite(siteBuilder, outputDir);

  if (watchMode) {
    print('\n👀 Watching for changes in: $inputDir');
    print('Press Ctrl+C to stop watching...\n');
    
    await watchDirectory(inputDir, () async {
      print('📝 Changes detected, rebuilding...');
      await buildSite(siteBuilder, outputDir);
    });
  }
}

Future<void> buildSite(StaticSiteBuilder siteBuilder, String outputDir) async {
  final stopwatch = Stopwatch()..start();
  
  await siteBuilder.build();
  
  stopwatch.stop();
  print('\n✅ Build completed in ${stopwatch.elapsedMilliseconds}ms');
  print('📁 Output written to: ${pathlib.absolute(outputDir)}');
  
  if (siteBuilder.renderErrors > 0 || siteBuilder.parseErrors > 0) {
    print('---');
    print('⚠️  Build finished with warnings:');
    if (siteBuilder.parseErrors > 0) {
      print('  - ${siteBuilder.parseErrors} file(s) failed to parse.');
    }
    if (siteBuilder.renderErrors > 0) {
      print(
          '  - ${siteBuilder.renderErrors} page(s) failed to render or write.');
    }
    print('---');
  }
}

Future<void> watchDirectory(String path, Future<void> Function() onChanged) async {
  final watcher = Directory(path).watch(recursive: true);
  Timer? debounceTimer;
  
  await for (final event in watcher) {
    // Skip events for the output directory and hidden files/directories
    if (event.path.contains('build/') || 
        event.path.contains('/.') ||
        event.path.endsWith('.tmp') ||
        event.path.endsWith('~')) {
      continue;
    }
    
    // Debounce rapid file changes (common during saves)
    debounceTimer?.cancel();
    debounceTimer = Timer(Duration(milliseconds: 500), () async {
      try {
        await onChanged();
      } catch (e) {
        print('❌ Error during rebuild: $e');
      }
    });
  }
}