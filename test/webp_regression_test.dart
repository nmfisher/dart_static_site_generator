import 'dart:io' as io;
import 'package:blog_builder/src/static_site_builder.dart';
import 'package:blog_builder/src/webp_html_processor.dart';
import 'package:file/memory.dart';
import 'package:html/parser.dart' as html;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  test('preserves quoted, hyphenated and boolean attributes', () {
    final processor = WebPHtmlProcessor(fileSystem: MemoryFileSystem())
      ..registerWebPConversion('assets/a.png', 'assets/a.webp');
    final result = processor.processHtml(
        '''<IMG src="/assets/a.png" data-id="42" aria-label="Label" alt='a "quote" > &amp; text' hidden>''');
    final image = html.parseFragment(result).querySelector('img')!;
    expect(image.attributes['data-id'], '42');
    expect(image.attributes['aria-label'], 'Label');
    expect(image.attributes['alt'], 'a "quote" > & text');
    expect(image.attributes.containsKey('hidden'), isTrue);
    expect(image.attributes.containsKey('id'), isFalse);
    expect(processor.processHtml(result), result,
        reason: 'processing should be idempotent');
  });
  test('ignores image-like text in scripts and comments', () {
    final processor = WebPHtmlProcessor(fileSystem: MemoryFileSystem())
      ..registerWebPConversion('assets/a.png', 'assets/a.webp');
    const source =
        '''<script>const image = '<img src="/assets/a.png">';</script><!-- <img src="/assets/a.png"> -->''';
    expect(processor.processHtml(source), source);
  });
  test('resolves relative image URLs from each generated page', () async {
    final fs = MemoryFileSystem();
    final processor = WebPHtmlProcessor(fileSystem: fs)
      ..registerWebPConversion('assets/photos/a.png', 'assets/photos/a.webp');
    final file = fs.file('/output/posts/hello/index.html')
      ..createSync(recursive: true)
      ..writeAsStringSync(
          '<!doctype html><html><head><title>Title</title></head><body><img src="../../assets/photos/a.png?v=1"></body></html>');
    await processor.processHtmlDirectory(fs.directory('/output'));
    final result = html.parse(file.readAsStringSync());
    expect(result.querySelector('title')!.text, 'Title');
    expect(result.querySelector('source')!.attributes['srcset'],
        '/assets/photos/a.webp?v=1');
    expect(result.querySelector('img')!.attributes['src'],
        '../../assets/photos/a.png?v=1');
  });
  test('builder preserves existing WebP assets when conversion is enabled',
      () async {
    final fs = MemoryFileSystem();
    fs.file('/site/config.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync(
          'title: Test\nimage_optimization:\n  enabled: true\n  webp:\n    enabled: true\n');
    fs.file('/site/assets/photos/image.webp')
      ..createSync(recursive: true)
      ..writeAsBytesSync([82, 73, 70, 70]);
    await StaticSiteBuilder(
            inputDir: '/site', outputDir: '/output', fileSystem: fs)
        .build();
    expect(fs.file('/output/assets/photos/image.webp').readAsBytesSync(),
        [82, 73, 70, 70]);
  });
  test('nested WebP conversion points HTML at an existing output file',
      () async {
    final temp =
        await io.Directory.systemTemp.createTemp('blog-webp-integration-');
    addTearDown(() => temp.delete(recursive: true));
    final input = path.join(temp.path, 'input');
    void write(String name, String content) {
      io.File(path.join(input, name))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    write('config.yaml',
        'title: Test\nbase_path: /docs\nimage_optimization:\n  enabled: true\n  webp:\n    enabled: true\n');
    write('content/page.md',
        '---\ntitle: Test\npublished: true\n---\n![Photo](/assets/photos/image.png)');
    final original = io.File(path.join(input, 'assets/photos/image.png'))
      ..createSync(recursive: true);
    original.writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    final output = path.join(temp.path, 'output');
    final builder =
        StaticSiteBuilder(inputDir: input, outputDir: output, announce: false);
    await builder.build();
    final doc = html.parse(
        io.File(path.join(output, 'page/index.html')).readAsStringSync());
    final source = doc.querySelector('source')!.attributes['srcset']!;
    expect(source, '/docs/assets/photos/image.webp');
    expect(
        io.File(path.join(output, source.substring('/docs/'.length)))
            .existsSync(),
        isTrue);
    await builder.build();
    expect(builder.cache.assetHits, 1);
    expect(io.File(path.join(output, 'page/index.html')).readAsStringSync(),
        contains('/docs/assets/photos/image.webp'));
    final config = io.File(path.join(input, 'config.yaml'));
    config.writeAsStringSync('${config.readAsStringSync()}    quality: 50\n');
    await builder.build();
    expect(builder.cache.assetHits, 0);
    final previous =
        io.File(path.join(output, 'page/index.html')).readAsStringSync();
    original.writeAsStringSync('not an image');
    await expectLater(builder.build(), throwsA(anything));
    expect(io.File(path.join(output, 'page/index.html')).readAsStringSync(),
        previous);
  });
}
