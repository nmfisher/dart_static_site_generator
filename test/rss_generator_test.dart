import 'package:blog_builder/blog_builder.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  group('RssConfig', () {
    test('creates default config with disabled state', () {
      final config = RssConfig();
      expect(config.enabled, false);
      expect(config.fileName, 'feed.xml');
      expect(config.layouts, isEmpty);
      expect(config.itemLimit, isNull);
    });

    test('parses config from map', () {
      final config = RssConfig.parse({
        'enabled': true,
        'title': 'My RSS Feed',
        'description': 'My feed description',
        'file_name': 'rss.xml',
        'layouts': ['post', 'article'],
        'item_limit': 50,
      });

      expect(config.enabled, true);
      expect(config.title, 'My RSS Feed');
      expect(config.description, 'My feed description');
      expect(config.fileName, 'rss.xml');
      expect(config.layouts, ['post', 'article']);
      expect(config.itemLimit, 50);
    });

    test('parses layouts from string', () {
      final config = RssConfig.parse({
        'enabled': true,
        'layouts': 'post',
      });

      expect(config.layouts, ['post']);
    });

    test('handles null config map', () {
      final config = RssConfig.parse(null);
      expect(config.enabled, false);
      expect(config.fileName, 'feed.xml');
    });

    test('converts to map', () {
      final config = RssConfig(
        enabled: true,
        title: 'Test Feed',
        fileName: 'test.xml',
        layouts: ['post'],
        itemLimit: 100,
      );

      final map = config.toMap();
      expect(map['enabled'], true);
      expect(map['title'], 'Test Feed');
      expect(map['file_name'], 'test.xml');
      expect(map['layouts'], ['post']);
      expect(map['item_limit'], 100);
    });
  });

  group('RSSGenerator', () {
    late MemoryFileSystem fs;

    setUp(() {
      fs = MemoryFileSystem();
    });

    test('generates RSS feed from page models', () async {
      // Create test pages
      final pages = [
        PageModel(
          title: 'First Post',
          route: '/posts/first',
          rawMarkdown: 'Content of first post',
          source: '/content/first.md',
          blurb: 'A blurb for first post',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 1, 15, 10, 30),
        )..renderedContent = '<p>Content of first post</p>',
        PageModel(
          title: 'Second Post',
          route: '/posts/second',
          rawMarkdown: 'Content of second post',
          source: '/content/second.md',
          blurb: 'A blurb for second post',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 2, 20, 14, 45),
        )..renderedContent = '<p>Content of second post</p>',
      ];

      final config = ConfigModel(
        title: 'Test Blog',
        metadata: {'og:description': 'Test description'},
        baseUrl: 'https://example.com',
        rss: RssConfig(enabled: true),
      );

      final outFile = '/output/feed.xml';

      await RSSGenerator.generateFromPageModels(
        pages,
        config,
        outFile: outFile,
        fileSystem: fs,
      );

      // Verify file was created
      final file = fs.file(outFile);
      expect(await file.exists(), true);

      final content = await file.readAsString();
      expect(content, contains('<rss version="2.0"'));
      expect(content, contains('<title>Test Blog</title>'));
      expect(content, contains('<description>Test description</description>'));
      expect(content, contains('<link>https://example.com/</link>'));
      expect(content, contains('<item>'));
      expect(content, contains('<title>First Post</title>'));
      expect(content, contains('<title>Second Post</title>'));
      expect(content, contains('<content:encoded>&lt;p>Content of first post&lt;/p></content:encoded>'));
    });

    test('filters out draft pages', () async {
      final pages = [
        PageModel(
          title: 'Published Post',
          route: '/posts/published',
          rawMarkdown: 'Published content',
          source: '/content/published.md',
          blurb: 'Published blurb',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 1, 1),
        )..renderedContent = '<p>Published</p>',
        PageModel(
          title: 'Draft Post',
          route: '/posts/draft',
          rawMarkdown: 'Draft content',
          source: '/content/draft.md',
          blurb: 'Draft blurb',
          metadata: {},
          draft: true, // This is a draft
          layoutId: 'post',
          date: DateTime(2024, 1, 2),
        )..renderedContent = '<p>Draft</p>',
      ];

      final config = ConfigModel(
        title: 'Test Blog',
        metadata: {},
        baseUrl: 'https://example.com',
        rss: RssConfig(enabled: true),
      );

      final outFile = '/output/feed.xml';

      await RSSGenerator.generateFromPageModels(
        pages,
        config,
        outFile: outFile,
        fileSystem: fs,
      );

      final content = await fs.file(outFile).readAsString();
      expect(content, contains('<title>Published Post</title>'));
      expect(content, isNot(contains('<title>Draft Post</title>')));
    });

    test('filters by layout when configured', () async {
      final pages = [
        PageModel(
          title: 'Blog Post',
          route: '/posts/blog',
          rawMarkdown: 'Blog content',
          source: '/content/blog.md',
          blurb: 'Blog blurb',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 1, 1),
        )..renderedContent = '<p>Blog</p>',
        PageModel(
          title: 'About Page',
          route: '/about',
          rawMarkdown: 'About content',
          source: '/content/about.md',
          blurb: 'About blurb',
          metadata: {},
          draft: false,
          layoutId: 'page',
          date: DateTime(2024, 1, 2),
        )..renderedContent = '<p>About</p>',
      ];

      final config = ConfigModel(
        title: 'Test Blog',
        metadata: {},
        baseUrl: 'https://example.com',
        rss: RssConfig(enabled: true, layouts: ['post']),
      );

      final outFile = '/output/feed.xml';

      await RSSGenerator.generateFromPageModels(
        pages,
        config,
        outFile: outFile,
        fileSystem: fs,
      );

      final content = await fs.file(outFile).readAsString();
      expect(content, contains('<title>Blog Post</title>'));
      expect(content, isNot(contains('<title>About Page</title>')));
    });

    test('respects item limit', () async {
      final pages = List.generate(
        10,
        (i) => PageModel(
          title: 'Post $i',
          route: '/posts/$i',
          rawMarkdown: 'Content $i',
          source: '/content/$i.md',
          blurb: 'Blurb $i',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 1, i + 1),
        )..renderedContent = '<p>Content $i</p>',
      );

      final config = ConfigModel(
        title: 'Test Blog',
        metadata: {},
        baseUrl: 'https://example.com',
        rss: RssConfig(enabled: true, itemLimit: 5),
      );

      final outFile = '/output/feed.xml';

      await RSSGenerator.generateFromPageModels(
        pages,
        config,
        outFile: outFile,
        fileSystem: fs,
      );

      final content = await fs.file(outFile).readAsString();
      // Should have 5 items
      expect('<item>'.allMatches(content).length, 5);
    });

    test('uses custom title and description from config', () async {
      final pages = [
        PageModel(
          title: 'Test Post',
          route: '/post',
          rawMarkdown: 'Content',
          source: '/content/post.md',
          blurb: 'Blurb',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 1, 1),
        )..renderedContent = '<p>Content</p>',
      ];

      final config = ConfigModel(
        title: 'Site Title',
        metadata: {},
        baseUrl: 'https://example.com',
        rss: RssConfig(
          enabled: true,
          title: 'Custom Feed Title',
          description: 'Custom feed description',
        ),
      );

      final outFile = '/output/feed.xml';

      await RSSGenerator.generateFromPageModels(
        pages,
        config,
        outFile: outFile,
        fileSystem: fs,
      );

      final content = await fs.file(outFile).readAsString();
      expect(content, contains('<title>Custom Feed Title</title>'));
      expect(content, contains('<description>Custom feed description</description>'));
    });

    test('excludes pages without dates', () async {
      final pages = [
        PageModel(
          title: 'Dated Post',
          route: '/posts/dated',
          rawMarkdown: 'Content',
          source: '/content/dated.md',
          blurb: 'Blurb',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 1, 1),
        )..renderedContent = '<p>Dated</p>',
        PageModel(
          title: 'Undated Page',
          route: '/about',
          rawMarkdown: 'Content',
          source: '/content/about.md',
          blurb: 'Blurb',
          metadata: {},
          draft: false,
          layoutId: 'page',
          date: null, // No date
        )..renderedContent = '<p>Undated</p>',
      ];

      final config = ConfigModel(
        title: 'Test Blog',
        metadata: {},
        baseUrl: 'https://example.com',
        rss: RssConfig(enabled: true),
      );

      final outFile = '/output/feed.xml';

      await RSSGenerator.generateFromPageModels(
        pages,
        config,
        outFile: outFile,
        fileSystem: fs,
      );

      final content = await fs.file(outFile).readAsString();
      expect(content, contains('<title>Dated Post</title>'));
      expect(content, isNot(contains('<title>Undated Page</title>')));
    });

    test('sorts items by date descending', () async {
      final pages = [
        PageModel(
          title: 'Old Post',
          route: '/posts/old',
          rawMarkdown: 'Old content',
          source: '/content/old.md',
          blurb: 'Old blurb',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 1, 1),
        )..renderedContent = '<p>Old</p>',
        PageModel(
          title: 'New Post',
          route: '/posts/new',
          rawMarkdown: 'New content',
          source: '/content/new.md',
          blurb: 'New blurb',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 6, 1),
        )..renderedContent = '<p>New</p>',
        PageModel(
          title: 'Middle Post',
          route: '/posts/middle',
          rawMarkdown: 'Middle content',
          source: '/content/middle.md',
          blurb: 'Middle blurb',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 3, 1),
        )..renderedContent = '<p>Middle</p>',
      ];

      final config = ConfigModel(
        title: 'Test Blog',
        metadata: {},
        baseUrl: 'https://example.com',
        rss: RssConfig(enabled: true),
      );

      final outFile = '/output/feed.xml';

      await RSSGenerator.generateFromPageModels(
        pages,
        config,
        outFile: outFile,
        fileSystem: fs,
      );

      final content = await fs.file(outFile).readAsString();

      // Find position of each item title
      final newPostPos = content.indexOf('<title>New Post</title>');
      final middlePostPos = content.indexOf('<title>Middle Post</title>');
      final oldPostPos = content.indexOf('<title>Old Post</title>');

      // Verify descending order (newest first)
      expect(newPostPos, lessThan(middlePostPos));
      expect(middlePostPos, lessThan(oldPostPos));
    });

    test('throws when baseUrl is missing', () async {
      final pages = [
        PageModel(
          title: 'Test Post',
          route: '/post',
          rawMarkdown: 'Content',
          source: '/content/post.md',
          blurb: 'Blurb',
          metadata: {},
          draft: false,
          layoutId: 'post',
          date: DateTime(2024, 1, 1),
        )..renderedContent = '<p>Content</p>',
      ];

      final config = ConfigModel(
        title: 'Test Blog',
        metadata: {},
        baseUrl: null, // No base URL
        rss: RssConfig(enabled: true),
      );

      final outFile = '/output/feed.xml';

      expect(
        () => RSSGenerator.generateFromPageModels(
          pages,
          config,
          outFile: outFile,
          fileSystem: fs,
        ),
        throwsArgumentError,
      );
    });
  });
}
