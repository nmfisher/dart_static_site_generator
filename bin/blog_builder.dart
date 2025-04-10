import 'dart:io';
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

  if (!await Directory(inputDir).exists()) {
    print('Error: Input directory not found: $inputDir');
    exit(1);
  }

  final siteBuilder = StaticSiteBuilder(
    inputDir: inputDir,
    outputDir: outputDir,
  );

  await siteBuilder.build(); // Call the build method
  print('\nBuild completed successfully!');
  print('Output written to: ${pathlib.absolute(outputDir)}');
  if (siteBuilder.renderErrors > 0 || siteBuilder.parseErrors > 0) {
    print('---');
    print('Build finished with warnings:');
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
