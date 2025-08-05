import 'dart:io';
import 'package:blog_builder/src/static_site_builder.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class TestFileSystem {
  final MemoryFileSystem fs = MemoryFileSystem();
  late final String inputDir;
  late final String outputDir;

  TestFileSystem() {
    inputDir = fs.path.join('/project', 'input');
    outputDir = fs.path.join('/project', 'output');
    fs.directory(inputDir).createSync(recursive: true);
    fs.directory(p.join(inputDir, 'content')).createSync(recursive: true);
    fs
        .directory(p.join(inputDir, 'assets'))
        .createSync(recursive: true); 
  }

  void createConfigFile(String content) {
    final configFile = fs.file(p.join(inputDir, 'config.yaml'));
    configFile.parent.createSync(recursive: true);
    configFile.writeAsStringSync(content);
  }

  void createMarkdownFile(String relativePath, String content) {
    final contentDir = fs.directory(p.join(inputDir, 'content'));
    final mdFile = fs.file(p.join(contentDir.path, relativePath));
    mdFile.parent.createSync(recursive: true);
    mdFile.writeAsStringSync(content);
  }

  void createAssetFile(String relativePath, List<int> bytes) {
    final assetsDir = fs.directory(p.join(inputDir, 'assets'));
    final assetFile = fs.file(p.join(assetsDir.path, relativePath));
    assetFile.parent.createSync(recursive: true);
    assetFile.writeAsBytesSync(bytes);
  }

  bool outputFileExists(String relativePath) {
    return fs.file(p.join(outputDir, relativePath)).existsSync();
  }

  String readOutputFile(String relativePath) {
    final file = fs.file(p.join(outputDir, relativePath));
    if (!file.existsSync()) {
      throw FileSystemException('File not found', file.path);
    }
    return file.readAsStringSync();
  }

  String normalizePath(String path) => p.normalize(path);
}

void main() {
  group('StaticSiteBuilder', () {
    late TestFileSystem testFs;
    late StaticSiteBuilder siteBuilder;

    setUp(() {
      testFs = TestFileSystem();

      const bundledTemplateFiles = [
        '_layouts/default.liquid',
        '_layouts/list.liquid',
        '_layouts/post.liquid',
        '_includes/header.liquid',
        '_includes/footer.liquid'
      ];

      final bundledTemplatesDir =
          testFs.fs.directory('/bundled_templates/_layouts');
      bundledTemplatesDir.createSync(recursive: true);
      testFs.fs
          .directory('/bundled_templates/_includes')
          .createSync(recursive: true);

      for (final templatePath in bundledTemplateFiles) {
        final file = testFs.fs.file('/bundled_templates/$templatePath');
        file.writeAsStringSync('Sample content for $templatePath');
      }

      siteBuilder = StaticSiteBuilder(
        inputDir: testFs.inputDir,
        outputDir: testFs.outputDir,
        fileSystem: testFs.fs,
      );

      testFs.createConfigFile('''
title: Test Site
owner: Tester
baseUrl: https://example.com
meta:
  description: "A test site"
''');
    });

    test(
        'falls back to bundled default templates when user templates are missing',
        () async {
      testFs.createMarkdownFile('page.md', '''
---
title: Fallback Test Page
published: true
---
This content should use the default bundled layout.
''');

      await siteBuilder.build();
      
      final expectedOutputPath = testFs.normalizePath('page/index.html');
      expect(testFs.outputFileExists(expectedOutputPath), isTrue,
          reason: "Output file $expectedOutputPath should exist");

      final outputContent = testFs.readOutputFile(expectedOutputPath);

      expect(outputContent, contains('<html lang="en">'),
          reason: "Should contain HTML tag from default layout");
      expect(outputContent,
          contains('<title>Fallback Test Page - Test Site</title>'),
          reason: "Should contain correct title from page and site config");
      expect(outputContent, contains('<header class="site-header">'),
          reason: "Should contain header include");
      expect(outputContent, contains('<a href="/">Test Site</a>'),
          reason: "Header should render site title");
      expect(outputContent, contains('<footer class="site-footer">'),
          reason: "Should contain footer include");
      expect(outputContent, contains('Tester. All rights reserved.'),
          reason: "Footer should render site owner");

      expect(outputContent, contains('<main class="container">'),
          reason: "Should contain main container");
      expect(outputContent, contains('<h1>Fallback Test Page</h1>'),
          reason: "Should render page title in content block");
      expect(
          outputContent,
          contains(
              '<p>This content should use the default bundled layout.</p>'), // Markdown converted to HTML
          reason: "Should render page HTML content");

      expect(outputContent,
          contains('<link rel="stylesheet" href="/assets/style.css">'),
          reason: "Should link default CSS");

      expect(siteBuilder.parseErrors, equals(0));
      expect(siteBuilder.renderErrors, equals(0));
    });

    test(
        '_cleanAndCreateOutputDir removes existing directory and creates new one',
        () async {
      final outputDirPath = testFs.outputDir;
      final existingFile = testFs.fs.file(p.join(outputDirPath, 'old.txt'));
      await existingFile.create(recursive: true);
      await existingFile.writeAsString('old content');
      expect(await existingFile.exists(), isTrue);

      await siteBuilder.build();

      expect(await existingFile.exists(), isFalse,
          reason: "Old file should be deleted");
      expect(await testFs.fs.directory(outputDirPath).exists(), isTrue,
          reason: "Output dir should exist");
    });

    test('_parseConfig loads configuration correctly', () async {
      // Arrange (config created in setUp)
      // Act - Called implicitly by build()
      await siteBuilder.build();

      // Assert
      expect(siteBuilder.siteConfig, isNotNull);
      expect(siteBuilder.siteConfig.title, equals('Test Site'));
      expect(siteBuilder.siteConfig.owner, equals('Tester'));
      expect(siteBuilder.siteConfig.baseUrl, equals('https://example.com'));
      expect(siteBuilder.siteConfig.metadata['description'],
          equals('A test site'));
    });

    test('_parseContent processes markdown files and creates page models',
        () async {
      // Arrange
      testFs.createMarkdownFile('post1.md', '''
---
title: Post 1
published: true
---
Content 1
''');
      testFs.createMarkdownFile('post2.md', '''
---
title: Post 2 Draft
published: false
---
Content 2
''');
      testFs.createMarkdownFile('subdir/post3.md', '''
---
title: Post 3
published: true
---
Content 3
''');

      // Act - Need a way to access parsed pages, perhaps make _parseContent return List<PageModel>
      // or check the results after build() based on output files.
      await siteBuilder.build(); // Trigger parsing

      // Assert (indirectly by checking output)
      expect(testFs.outputFileExists('post1/index.html'), isTrue);
      expect(testFs.outputFileExists('post2/index.html'), isFalse,
          reason: "Draft should not be generated");
      expect(testFs.outputFileExists('subdir/post3/index.html'), isTrue);
      // Could add more specific content checks here
    });

    test('_renderAllPages calls renderer and writes output', () async {
      // Arrange
      testFs.createMarkdownFile('render-test.md', '''
---
title: Render Test
published: true
---
Render this!
''');
      // No user templates -> should use default bundled template

      // Act
      await siteBuilder.build();

      // Assert
      final outputPath = testFs.normalizePath('render-test/index.html');
      expect(testFs.outputFileExists(outputPath), isTrue);
      final content = testFs.readOutputFile(outputPath);
      expect(content, contains('<h1>Render Test</h1>'));
      expect(content, contains('<p>Render this!</p>'));
      expect(
          content,
          contains(
              '<title>Render Test - Test Site</title>')); // Verify rendering happened
    });

    test('_copyAssets copies files from assets directory to output', () async {
      final assetContent = [1, 2, 3, 4];
      testFs.createAssetFile('style.css', assetContent);
      testFs.createAssetFile('images/logo.png', [5, 6]);

      await siteBuilder.build(); 

      final outputAssetPath = testFs.normalizePath('assets/style.css');
      final outputImagePath = testFs.normalizePath('assets/images/logo.png');
      expect(testFs.outputFileExists(outputAssetPath), isTrue);
      expect(
          testFs.fs
              .file(p.join(testFs.outputDir, outputAssetPath))
              .readAsBytesSync(),
          equals(assetContent));

      expect(testFs.outputFileExists(outputImagePath), isTrue);
      expect(
          testFs.fs
              .file(p.join(testFs.outputDir, outputImagePath))
              .readAsBytesSync(),
          equals([5, 6]));
    });

    test('build method executes all steps and produces expected output',
        () async {
      testFs.createConfigFile('''
title: Full Build Test
owner: Builder
baseUrl: http://build.test
''');
      testFs.createMarkdownFile('home.md', '''
---
title: Home Page
published: true
route: / # Explicit root route
---
Welcome home.
''');
      testFs.createMarkdownFile('posts/post-a.md', '''
---
title: Post A
published: true
layout: post # Requires bundled post layout
date: 2024-01-15
---
Content of Post A.
''');
      testFs.createAssetFile('main.css', [10, 20, 30]);

      // Act
      await siteBuilder.build();

      // Assert (Key outputs)
      // Index page (home.md routed to /)
      expect(testFs.outputFileExists('index.html'), isTrue);
      expect(
          testFs.readOutputFile('index.html'), contains('<h1>Home Page</h1>'));
      expect(testFs.readOutputFile('index.html'),
          contains('<title>Home Page - Full Build Test</title>'));

      // Post page (using bundled post layout)
      expect(testFs.outputFileExists('posts/post-a/index.html'), isTrue);
      expect(testFs.readOutputFile('posts/post-a/index.html'),
          contains('<h1>Post A</h1>')); // From post layout
      expect(testFs.readOutputFile('posts/post-a/index.html'),
          contains('<article class="post">')); // From post layout
      expect(testFs.readOutputFile('posts/post-a/index.html'),
          contains('January 15, 2024')); // Date formatting from post layout
      expect(testFs.readOutputFile('posts/post-a/index.html'),
          contains('<p>Content of Post A.</p>')); // Content

      // Index page for posts/ directory (auto-generated using bundled list layout)
      expect(testFs.outputFileExists('posts/index.html'), isTrue);
      expect(testFs.readOutputFile('posts/index.html'),
          contains('<h1>Posts</h1>')); // Default title for dir
      expect(
          testFs.readOutputFile('posts/index.html'),
          contains(
              '<h2><a href="/posts/post-a">Post A</a></h2>')); // Link to child
      expect(testFs.readOutputFile('posts/index.html'),
          contains('<article class="page-list">')); // From list layout

      // Asset
      expect(testFs.outputFileExists('assets/main.css'), isTrue);
      expect(
          testFs.fs
              .file(p.join(testFs.outputDir, 'assets/main.css'))
              .readAsBytesSync(),
          equals([10, 20, 30]));

      // Sitemap (since baseUrl is present)
      expect(testFs.outputFileExists('sitemap.xml'), isTrue);
      expect(testFs.readOutputFile('sitemap.xml'),
          contains('<loc>http://build.test/</loc>')); // Home page URL
      expect(
          testFs.readOutputFile('sitemap.xml'),
          contains(
              '<loc>http://build.test/posts/post-a</loc>')); // Post page URL
      expect(testFs.readOutputFile('sitemap.xml'),
          contains('<loc>http://build.test/posts</loc>')); // Index page URL
    });
  });
}
