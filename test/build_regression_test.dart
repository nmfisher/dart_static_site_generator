import 'dart:io' as io;
import 'package:blog_builder/blog_builder.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

void main() {
  late MemoryFileSystem fs;
  late StaticSiteBuilder builder;
  void write(String name, String content) {
    fs.file(name)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  void page(String name, {String extra = '', String body = 'Body'}) {
    write('/site/content/$name',
        '---\ntitle: Example\npublished: true\n$extra---\n$body');
  }

  setUp(() {
    fs = MemoryFileSystem();
    write('/site/config.yaml',
        'title: Site\nowner: Owner\nbaseUrl: https://example.com/\n');
    builder = StaticSiteBuilder(
        inputDir: '/site', outputDir: '/output', fileSystem: fs);
  });

  for (final output in [
    '/site',
    '/site/../site',
    '/',
    '/site/content',
    '/site/content/generated',
    '/site/templates',
    '/site/assets'
  ]) {
    test('rejects destructive output $output before deleting source', () async {
      page('post.md');
      final unsafe = StaticSiteBuilder(
          inputDir: '/site', outputDir: output, fileSystem: fs);
      await expectLater(unsafe.build(), throwsArgumentError);
      expect(fs.file('/site/config.yaml').existsSync(), isTrue);
      expect(fs.file('/site/content/post.md').existsSync(), isTrue);
    });
  }

  test('checks output symlinks and nonexistent descendants of symlinks',
      () async {
    page('post.md');
    fs.link('/alias').createSync('/site/content');
    for (final output in ['/alias', '/alias/generated']) {
      await expectLater(
          StaticSiteBuilder(
                  inputDir: '/site', outputDir: output, fileSystem: fs)
              .build(),
          throwsArgumentError);
    }
    expect(fs.file('/site/content/post.md').existsSync(), isTrue);
  });

  test('allows a separate build directory under input', () async {
    page('post.md');
    await StaticSiteBuilder(
            inputDir: '/site', outputDir: '/site/build', fileSystem: fs)
        .build();
    expect(fs.file('/site/build/post/index.html').existsSync(), isTrue);
  });

  test('invalid config preserves existing output', () async {
    write('/output/keep.txt', 'keep');
    write('/site/config.yaml', '[');
    await expectLater(builder.build(), throwsException);
    expect(fs.file('/output/keep.txt').readAsStringSync(), 'keep');
  });

  test('rejects RSS output traversal before clearing output', () async {
    write('/output/keep.txt', 'keep');
    write('/site/config.yaml',
        'rss:\n  enabled: true\n  file_name: ../escaped.xml\n');
    await expectLater(builder.build(), throwsFormatException);
    expect(fs.file('/output/keep.txt').readAsStringSync(), 'keep');
    expect(fs.file('/escaped.xml').existsSync(), isFalse);
  });

  test('frontmatter must start at the beginning of the file', () {
    write('/site/content/post.md', 'intro\n---\ntitle: Test\n---\nBody');
    expect(
        () => PageModel.from(
            fs.file('/site/content/post.md'), fs.directory('/site/content')),
        throwsFormatException);
  });

  for (final route in [
    '/../escaped',
    '//escaped',
    '/nested/../../escaped',
    r'/..\escaped'
  ]) {
    test('rejects route $route and fails the build', () async {
      page('post.md', extra: 'route: $route\n');
      await expectLater(builder.build(), throwsStateError);
      expect(builder.parseErrors, 1);
      expect(fs.file('/escaped/index.html').existsSync(), isFalse);
    });
  }

  test('valid frontmatter values and body can contain delimiter text', () {
    for (final newline in ['\n', '\r\n']) {
      write(
          '/site/content/post.md',
          '---\ntitle: "Before---After"\npublished: true\nsummary: |\n  --- inside a scalar\n---\nBody\n---\nMore'
              .replaceAll('\n', newline));
      final parsed = PageModel.from(
          fs.file('/site/content/post.md'), fs.directory('/site/content'));
      expect(parsed.title, 'Before---After');
      expect(parsed.rawMarkdown, 'Body${newline}---${newline}More');
      expect(parsed.extras['summary'], contains('--- inside a scalar'));
    }
  });

  test('direct page lookup and directory indexes share the correct nodes',
      () async {
    page('index.md', extra: 'layout: home\n');
    page('posts/hello.md', extra: 'priority: 2\ndate: 2024-01-15\n');
    page('posts/first.md', extra: 'priority: 1\ndate: 2023-01-15\n');
    page('posts/index.md', extra: 'layout: default\n');
    page('articles/child.md');
    await builder.build();
    final data = builder.siteData.toLiquidMap();
    expect(data['posts']['hello']['title'], 'Example');
    expect(data['posts'].containsKey('hello_1'), isFalse);
    expect(data['posts']['route'], '/posts');
    expect(data['posts']['title'], 'Example');
    expect(data['articles']['title'], 'Articles');
    expect(data['posts']['all'].map((p) => p['route']).toList(),
        ['/posts/first', '/posts/hello']);
    expect(data['posts']['hello']['rendered_content'], contains('<p>Body</p>'));
    final output = fs.file('/output/index.html').readAsStringSync();
    expect(output, contains('<title>Example - Site</title>'));
    expect(output, contains('January 15, 2024'));
    expect(output, contains('<p>Body</p>'));
  });

  test(
      'manual templates can fall back to bundled layouts and empty partials override defaults',
      () async {
    page('post.md', extra: 'layout: post\n');
    write('/site/templates/_includes/header.liquid', 'Custom {{ site.title }}');
    write('/site/templates/_includes/footer.liquid', '');
    await builder.build();
    final output = fs.file('/output/post/index.html').readAsStringSync();
    expect(output, contains('Custom Site'));
    expect(output, contains('<p>Body</p>'));
    expect(output, isNot(contains('All rights reserved')));
  });

  test('failed renders fail the build and a corrected rebuild succeeds',
      () async {
    page('post.md', extra: 'layout: missing\n');
    await expectLater(builder.build(), throwsStateError);
    expect(builder.renderErrors, greaterThan(0));
    write('/site/templates/_layouts/missing.liquid', '{{ content }}');
    await builder.build();
    expect(builder.renderErrors, 0);
    expect(fs.file('/output/post/index.html').readAsStringSync(),
        contains('<p>Body</p>'));
  });

  test('sitemap is readable when generation completes and failures propagate',
      () async {
    final page = PageModel.fromMap(
        {'route': '/post', 'date': DateTime.utc(2024, 1, 15)});
    await SitemapGenerator.generateFromPageModels(
        [page], 'https://example.com/',
        outFile: '/deep/sitemap.xml', fileSystem: fs);
    expect(
        XmlDocument.parse(fs.file('/deep/sitemap.xml').readAsStringSync())
            .findAllElements('loc')
            .single
            .innerText,
        'https://example.com/post');
    fs.directory('/bad.xml').createSync();
    await expectLater(
        SitemapGenerator.generateFromPageModels([page], 'https://example.com',
            outFile: '/bad.xml', fileSystem: fs),
        throwsA(isA<io.FileSystemException>()));
  });

  test('RSS dates include GMT and URLs have no double slash', () async {
    await RSSGenerator.generateFromPageModels([
      PageModel.fromMap(
          {'route': '/post', 'date': DateTime.utc(2024, 1, 15, 10, 30)})
    ], ConfigModel(metadata: {}, baseUrl: 'https://example.com/'),
        outFile: '/feed.xml', fileSystem: fs);
    final feed = XmlDocument.parse(fs.file('/feed.xml').readAsStringSync());
    expect(feed.findAllElements('pubDate').single.innerText,
        'Mon, 15 Jan 2024 10:30:00 GMT');
    expect(feed.findAllElements('lastBuildDate').single.innerText,
        endsWith(' GMT'));
    expect(
        feed
            .findAllElements('item')
            .single
            .findElements('link')
            .single
            .innerText,
        'https://example.com/post/');
  });

  test('CLI returns failure for malformed content', () async {
    final temp = await io.Directory.systemTemp.createTemp('blog-cli-test-');
    addTearDown(() => temp.delete(recursive: true));
    final input = io.Directory(path.join(temp.path, 'input'))..createSync();
    io.File(path.join(input.path, 'config.yaml'))
        .writeAsStringSync('title: Test\n');
    io.Directory(path.join(input.path, 'content')).createSync();
    io.File(path.join(input.path, 'content', 'bad.md'))
        .writeAsStringSync('missing frontmatter');
    final result = await io.Process.run(io.Platform.resolvedExecutable, [
      '--packages=${path.absolute('.dart_tool/package_config.json')}',
      path.absolute('bin/blog_builder.dart'),
      '--input',
      input.path,
      '--output',
      path.join(temp.path, 'output')
    ]);
    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('Build failed'));
    expect(result.stdout, isNot(contains('✅ Build completed')));
  });
}
