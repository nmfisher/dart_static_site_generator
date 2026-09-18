import 'dart:convert';
import 'dart:io';

import 'package:blog_builder/blog_builder.dart';
import 'package:test/test.dart';

void main() {
  late Directory site;

  setUp(() async {
    site = await Directory.systemTemp.createTemp('blog-i18n-');
    await Directory('${site.path}/content/posts').create(recursive: true);
    await Directory('${site.path}/content/de/posts').create(recursive: true);
    await File('${site.path}/config.yaml').writeAsString('''
title: I18n Site
baseUrl: https://example.com
rss:
  enabled: true
default_locale: en
locales:
  en: { name: English }
  de: { name: Deutsch }
''');
    await File('${site.path}/content/index.md').writeAsString('''
---
published: true
title: Home
---
English home
''');
    await File('${site.path}/content/posts/hello.md').writeAsString('''
---
published: true
title: Hello
date: 2024-01-01
tags: [x]
---
Hello world
''');
    await File('${site.path}/content/de/index.md').writeAsString('''
---
published: true
title: Startseite
locale: de
---
Deutsche Startseite
''');
    await File('${site.path}/content/de/posts/hello.md').writeAsString('''
---
published: true
title: Hallo
date: 2024-01-01
locale: de
---
Hallo Welt
''');
    await File('${site.path}/content/de/posts/only-de.md').writeAsString('''
---
published: true
title: Nur Deutsch
date: 2024-02-01
locale: de
---
Deutschland
''');
  });

  tearDown(() async {
    if (await site.exists()) await site.delete(recursive: true);
  });

  Future<StaticSiteBuilder> build({String? locale}) async {
    final out = '${site.path}/.out-${locale ?? 'all'}';
    final builder = StaticSiteBuilder(
        inputDir: site.path, outputDir: out, localeFilter: locale);
    await builder.build();
    return builder;
  }

  test('config parses locales and exposes them to templates', () async {
    final config = ConfigModel.parse(File('${site.path}/config.yaml'));
    expect(config.i18n.enabled, isTrue);
    expect(config.i18n.defaultLocale.code, 'en');
    expect(config.i18n.locales.map((l) => l.code), ['en', 'de']);
    expect(config.toMap()['i18n'], containsPair('enabled', true));
  });

  test('builds rooted locale trees and keeps default locale at root', () async {
    await build();
    final output = Directory('${site.path}/.out-all');
    expect(File('${output.path}/index.html').existsSync(), isTrue);
    expect(File('${output.path}/posts/hello/index.html').existsSync(), isTrue);
    expect(File('${output.path}/de/index.html').existsSync(), isTrue);
    expect(
        File('${output.path}/de/posts/hello/index.html').existsSync(), isTrue);
    expect(File('${output.path}/de/posts/only-de/index.html').existsSync(),
        isTrue);
    // No /en/ mirror of the default locale.
    expect(Directory('${output.path}/en').existsSync(), isFalse);
  });

  test('html lang and hreflang links are rendered for translations', () async {
    await build();
    final deHello = File('${site.path}/.out-all/de/posts/hello/index.html')
        .readAsStringSync();
    expect(deHello, contains('<html lang="de">'));
    expect(deHello, contains('hreflang="en"'));
    expect(deHello, contains('hreflang="de"'));
    expect(deHello, contains('hreflang="x-default"'));
    expect(deHello.contains('https://example.com/de/posts/hello/'), isTrue);
    final enHello =
        File('${site.path}/.out-all/posts/hello/index.html').readAsStringSync();
    expect(enHello, contains('hreflang="de"'));
    expect(enHello.contains('https://example.com/posts/hello/'), isTrue);
  });

  test('sitemap carries hreflang alternates', () async {
    await build();
    final sitemap =
        File('${site.path}/.out-all/sitemap.xml').readAsStringSync();
    expect(sitemap, contains('xmlns:xhtml'));
    expect(sitemap, contains('hreflang="de"'));
    expect(sitemap, contains('https://example.com/de/posts/hello/'));
  });

  test('rss is localized: language, items and translated routes', () async {
    await build();
    final deFeed = File('${site.path}/.out-all/de/feed.xml').readAsStringSync();
    expect(deFeed, contains('<language>de</language>'));
    expect(deFeed, contains('https://example.com/de/posts/hello/'));
    expect(deFeed, contains('Nur Deutsch'));
    expect(deFeed, contains('Hallo'));
    // Default-locale-only posts fall back to the de feed untranslated.
    expect(deFeed, contains('<title>Hello</title>'));
    final enFeed = File('${site.path}/.out-all/feed.xml').readAsStringSync();
    expect(enFeed, contains('<language>en</language>'));
    expect(enFeed, contains('<title>Hello</title>'));
    // de-only posts are not in the default feed.
    expect(enFeed.contains('Nur Deutsch'), isFalse);
  });

  test('search indexes are localized', () async {
    await build();
    final enIndex = jsonDecode(
            File('${site.path}/.out-all/search-index.json').readAsStringSync())
        as List;
    final deIndex = jsonDecode(
        File('${site.path}/.out-all/de/search-index.json')
            .readAsStringSync()) as List;
    final enTitles = enIndex.map((e) => e['title']).toList();
    final deTitles = deIndex.map((e) => e['title']).toList();
    expect(enTitles, contains('Hello'));
    expect(enTitles, isNot(contains('Hallo')));
    expect(enTitles, isNot(contains('Nur Deutsch')));
    expect(deTitles, contains('Hallo'));
    expect(deTitles, contains('Nur Deutsch'));
    // Untranslated default-locale posts fall back into the de index.
    expect(deTitles, contains('Hello'));
    final deSearch =
        File('${site.path}/.out-all/de/search/index.html').readAsStringSync();
    expect(deSearch, contains('/de/search-index.json'));
  });

  test('per-locale homes are generated and localized index files win',
      () async {
    await build();
    final deHome =
        File('${site.path}/.out-all/de/index.html').readAsStringSync();
    expect(deHome, contains('Deutsche Startseite'));
    expect(deHome.contains('English home'), isFalse);
  });

  test('--locale filters the build to a single locale', () async {
    final builder = await build(locale: 'de');
    expect(builder.i18n.enabled, isTrue);
    final output = Directory('${site.path}/.out-de');
    expect(File('${output.path}/de/index.html').existsSync(), isTrue);
    expect(File('${output.path}/de/posts/only-de/index.html').existsSync(),
        isTrue);
    // Default-locale pages are omitted in a de-only build.
    expect(File('${output.path}/index.html').existsSync(), isFalse);
    expect(File('${output.path}/posts').existsSync(), isFalse);
  });

  test('unknown locale filter fails fast', () async {
    final builder = StaticSiteBuilder(
        inputDir: site.path,
        outputDir: '${site.path}/.out-xx',
        localeFilter: 'xx');
    await expectLater(builder.build(), throwsArgumentError);
  });

  test('sites without locales are unchanged (disabled i18n)', () async {
    final plain = await Directory.systemTemp.createTemp('blog-plain-');
    addTearDown(() => plain.delete(recursive: true));
    await File('${plain.path}/config.yaml')
        .writeAsString('title: Plain\nbaseUrl: https://example.com\n');
    await Directory('${plain.path}/content').create(recursive: true);
    await File('${plain.path}/content/one.md')
        .writeAsString('---\npublished: true\ntitle: One\n---\nOne');
    final builder = StaticSiteBuilder(
        inputDir: plain.path, outputDir: '${plain.path}/.out');
    await builder.build();
    expect(builder.siteConfig.i18n.enabled, isFalse);
    expect(File('${plain.path}/.out/one/index.html').existsSync(), isTrue);
    expect(Directory('${plain.path}/.out/de').existsSync(), isFalse);
  });
}
