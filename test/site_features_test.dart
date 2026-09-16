import 'dart:convert';
import 'package:blog_builder/blog_builder.dart';
import 'package:file/memory.dart';
import 'package:html/parser.dart' as html;
import 'package:test/test.dart';

void main() {
  late MemoryFileSystem fs;
  late StaticSiteBuilder builder;
  void write(String path, String text) => fs.file(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
  void page(String path,
          {String meta = '', String body = 'Content', bool published = true}) =>
      write('/site/content/$path.md',
          '---\ntitle: $path\npublished: $published\n$meta---\n$body');
  String output(String route) => fs.file('/out/$route').readAsStringSync();
  setUp(() {
    fs = MemoryFileSystem();
    write('/site/config.yaml',
        'title: Test\nbaseUrl: https://example.com/docs/\nimage_optimization:\n  enabled: false\n');
    builder = StaticSiteBuilder(
        inputDir: '/site', outputDir: '/out', fileSystem: fs, announce: false);
  });

  test(
      'failed render preserves the last build; successful build removes stale output',
      () async {
    page('one');
    await builder.build();
    final previous = output('one/index.html');
    page('one', meta: 'layout: missing\n');
    await expectLater(builder.build(), throwsStateError);
    expect(output('one/index.html'), previous);
    expect(
        fs.directory('/').listSync().where((e) => e.path.contains('-stage-')),
        isEmpty);
    fs.file('/site/content/one.md').deleteSync();
    page('two');
    await builder.build();
    expect(fs.file('/out/one/index.html').existsSync(), isFalse);
    expect(output('two/index.html'), contains('Content'));
  });

  test(
      'check validates URLs, anchors and images without writing output or cache',
      () async {
    page('one',
        body:
            '# Present\n\n[Good](#present) [Bad](#absent) [Gone](/gone/) ![Missing](/assets/missing.png)');
    write('/out/keep', 'old');
    final issues = await builder.check();
    expect(issues.map((i) => i.message).join('\n'),
        contains('Missing anchor: #absent'));
    expect(issues.map((i) => i.message).join('\n'),
        contains('Missing internal link: /docs/gone/'));
    expect(issues.map((i) => i.message).join('\n'),
        contains('Missing asset: /docs/assets/missing.png'));
    expect(issues, hasLength(3));
    expect(output('keep'), 'old');
    expect(fs.directory('/site/.blog-cache').existsSync(), isFalse);
    expect(fs.file('/out/one/index.html').existsSync(), isFalse);
  });

  test('check reports duplicate routes and output file/directory conflicts',
      () async {
    page('one', meta: 'route: /same\n');
    page('two', meta: 'route: /same\n');
    expect((await builder.check()).join('\n'), contains('Duplicate route'));
    fs.file('/site/content/two.md').deleteSync();
    page('one', meta: 'route: /search-index.json\n');
    expect((await builder.check()).join('\n'),
        contains('Output directory conflicts'));
  });

  test('check reports missing layouts and invalid typed frontmatter', () async {
    page('one', meta: 'layout: missing\n');
    expect((await builder.check()).join('\n'), contains('missing.liquid'));
    page('one', meta: 'date: not-a-date\n');
    expect((await builder.check()).join('\n'), contains('Invalid date'));
    write('/site/content/one.md',
        '---\ntitle: Bad\npublished: "true"\n---\nText');
    expect((await builder.check()).join('\n'),
        contains('published must be a boolean'));
  });

  test(
      'collections paginate, order by priority, expose navigation and generate taxonomies',
      () async {
    write('/site/config.yaml', '''title: Test
baseUrl: https://example.com/docs/
pagination:
  page_size: 2
collections:
  projects:
    title: My projects
    layout: post
    page_size: 2
''');
    page('projects/a',
        meta:
            'date: 2025-01-01\npriority: 1\ntags: [Dart]\ncategories: [Engineering]\n');
    page('projects/b', meta: 'date: 2026-01-01\npriority: 2\ntags: [Dart]\n');
    page('projects/c', meta: 'date: 2024-01-01\ntags: [Dart]\n');
    page('projects/draft', published: false, meta: 'tags: [Secret]\n');
    await builder.build();
    final archive = output('projects/index.html');
    expect(archive, contains('My projects'));
    expect(archive.indexOf('href="/docs/projects/a"'),
        lessThan(archive.indexOf('href="/docs/projects/b"')));
    expect(archive, contains('/docs/projects/page/2'));
    expect(output('projects/page/2/index.html'), contains('projects/c'));
    expect(output('tags/dart/page/2/index.html'), contains('projects/c'));
    expect(output('categories/engineering/index.html'), contains('projects/a'));
    expect(fs.file('/out/tags/secret/index.html').existsSync(), isFalse);
    final data = builder.siteData.toLiquidMap()['collections']['projects'];
    expect(data['count'], 3);
    expect(data['all'][0]['next']['route'], '/projects/b');
    expect(data['all'][1]['previous']['route'], '/projects/a');
    expect(data['all'][0]['layoutId'], 'post');
    expect(await builder.check(), isEmpty);
  });

  test('manual collection indexes retain content and get paginated children',
      () async {
    write('/site/config.yaml',
        'title: Test\ncollections:\n  posts:\n    page_size: 1\n');
    page('posts/index', meta: 'layout: list\n', body: 'Intro');
    page('posts/a');
    page('posts/b');
    await builder.build();
    expect(output('posts/index.html'), contains('Intro'));
    expect(output('posts/page/2/index.html'), contains('posts/b'));
  });

  test('conflicting taxonomy slugs fail without replacing output', () async {
    page('one', meta: 'tags: ["C++", "C#"]\n');
    write('/out/keep', 'old');
    await expectLater(builder.build(), throwsFormatException);
    expect(output('keep'), 'old');
  });

  test(
      'URL filters work inside partials and mount SEO, HTML, feed and sitemap URLs',
      () async {
    write('/site/config.yaml',
        'title: Test\nbaseUrl: https://example.com/docs/\nrss:\n  enabled: true\n');
    write('/site/templates/_includes/header.liquid',
        "<a href=\"{{ '/one/' | relative_url }}\">Link</a><b>{{ '/one/' | absolute_url }}</b>");
    page('one',
        meta: 'date: 2026-01-01\nmeta:\n  og:image: /assets/pic.png\n',
        body:
            '<img src="/assets/pic.png" srcset="/assets/pic.png 1x, /assets/pic.png 2x">');
    write('/site/assets/pic.png', 'placeholder');
    await builder.build();
    final doc = html.parse(output('one/index.html'));
    expect(doc.querySelector('link[rel=canonical]')!.attributes['href'],
        'https://example.com/docs/one/');
    expect(
        doc.querySelector('meta[property="og:image"]')!.attributes['content'],
        'https://example.com/docs/assets/pic.png');
    expect(doc.querySelector('img')!.attributes['srcset'],
        '/docs/assets/pic.png 1x, /docs/assets/pic.png 2x');
    expect(doc.querySelector('b')!.text, 'https://example.com/docs/one/');
    expect(output('feed.xml'), contains('https://example.com/docs/one/'));
    expect(output('sitemap.xml'), contains('https://example.com/docs/one'));
    expect(output('one/index.html'), isNot(contains('/docs/docs/')));
    expect(await builder.check(), isEmpty);
  });

  test(
      'markdown provides unique headings, TOC, escaped highlighting and search text',
      () async {
    page('one',
        meta: 'layout: post\n',
        body:
            '# Repeat\n\n## Repeat\n\n```dart\nfinal x = "<script>";\n```\n\n```unknown-language\n<script>evil()</script>\n```\n\n<script>hiddenSecret()</script>');
    page('draft', published: false, body: 'secretDraft');
    await builder.build();
    final doc = html.parse(output('one/index.html'));
    expect(doc.querySelector('#repeat'), isNotNull);
    expect(doc.querySelector('#repeat-2'), isNotNull);
    expect(doc.querySelectorAll('.table-of-contents a'), hasLength(2));
    expect(doc.querySelector('code.hljs .hljs-keyword'), isNotNull);
    expect(doc.querySelector('code script'), isNull);
    final records = jsonDecode(output('search-index.json')) as List;
    expect(records, hasLength(1));
    expect(records.single['url'], '/docs/one/');
    expect(records.single['text'], isNot(contains('hiddenSecret')));
    expect(output('search/index.html'), contains('/docs/search-index.json'));
    final draftBuilder = StaticSiteBuilder(
        inputDir: '/site',
        outputDir: '/preview',
        fileSystem: fs,
        includeDrafts: true);
    await draftBuilder.build();
    expect(fs.file('/preview/draft/index.html').existsSync(), isTrue);
    expect(jsonDecode(fs.file('/preview/search-index.json').readAsStringSync()),
        hasLength(2));
  });

  test(
      'persistent cache hits survive new builders and invalidate template dependencies',
      () async {
    write('/site/templates/_layouts/custom.liquid',
        "{% render '_includes/part.liquid', page: page, site: site %}{{ content }}");
    write('/site/templates/_includes/part.liquid', 'First {{ site.title }}');
    write('/site/templates/_layouts/other.liquid', 'Unrelated {{ content }}');
    page('one', meta: 'layout: custom\n');
    page('two', meta: 'layout: other\n');
    write('/site/assets/note.txt', 'asset');
    await builder.build();
    final second = StaticSiteBuilder(
        inputDir: '/site', outputDir: '/out', fileSystem: fs, announce: false);
    await second.build();
    expect(second.cache.parsedHits, 2);
    expect(second.cache.contentHits, greaterThanOrEqualTo(2));
    expect(second.cache.layoutHits, greaterThanOrEqualTo(2));
    expect(second.cache.assetHits, 1);
    write('/site/templates/_includes/part.liquid', 'Changed {{ site.title }}');
    await second.build();
    expect(output('one/index.html'), contains('Changed Test'));
    expect(second.cache.layoutHits, greaterThanOrEqualTo(1));
    page('one', meta: 'layout: custom\n', body: 'Updated body');
    await second.build();
    expect(output('one/index.html'), contains('Updated body'));
    expect(second.cache.parsedHits, 1);
    expect(second.cache.layoutHits, greaterThanOrEqualTo(1));
    fs.file('/site/assets/note.txt').deleteSync();
    await second.build();
    expect(fs.file('/out/assets/note.txt').existsSync(), isFalse);
  });

  test('collection list reads invalidate when another page changes', () async {
    write('/site/templates/_layouts/catalog.liquid',
        '{% for item in site.collections.posts.all %}{{ item.title }} {{ item.rendered_content }}{% endfor %}');
    page('index', meta: 'layout: catalog\n');
    page('posts/a', body: 'First');
    await builder.build();
    page('posts/a', body: 'Second');
    await builder.build();
    expect(output('index.html'), contains('Second'));
    expect(output('index.html'), isNot(contains('First')));
  });

  test(
      'reserved feed files and non-index collection collisions fail validation',
      () async {
    page('one');
    write('/site/config.yaml',
        'title: Test\nbaseUrl: https://example.com\nrss:\n  enabled: true\n  file_name: search-index.json\n');
    expect(
        (await builder.check()).join('\n'), contains('RSS output conflicts'));
    write('/site/config.yaml', 'title: Test\ncollections:\n  posts: {}\n');
    page('one', meta: 'route: /posts\n');
    expect((await builder.check()).join('\n'), contains('Duplicate route'));
  });

  test('check validates srcset-only images', () async {
    page('one',
        body: '<picture><source srcset="/assets/missing.png 2x"></picture>');
    expect((await builder.check()).join('\n'),
        contains('Missing asset: /docs/assets/missing.png'));
  });

  test('malformed cache entries are rebuilt instead of breaking publication',
      () async {
    page('one', body: '# Heading');
    await builder.build();
    final previous = output('one/index.html');
    for (final entry
        in fs.directory('/site/.blog-cache/v1').listSync(recursive: true)) {
      if (entry.path.endsWith('.json'))
        fs.file(entry.path).writeAsStringSync('{}');
    }
    await builder.build();
    expect(output('one/index.html'), previous);
    expect(builder.cache.contentHits, 0);
  });

  test('feature switches and no-incremental leave cache absent', () async {
    write('/site/config.yaml',
        'title: Test\nsearch:\n  enabled: false\nmarkdown:\n  highlight: false\n  heading_anchors: false\n  toc: false\n');
    page('one', body: '# Plain');
    await StaticSiteBuilder(
            inputDir: '/site',
            outputDir: '/out',
            fileSystem: fs,
            incremental: false,
            announce: false)
        .build();
    expect(output('one/index.html'), contains('<h1>Plain</h1>'));
    expect(fs.file('/out/search-index.json').existsSync(), isFalse);
    expect(fs.file('/out/search/index.html').existsSync(), isFalse);
    expect(fs.directory('/site/.blog-cache').existsSync(), isFalse);
  });
}
