import 'package:test/test.dart';
import 'package:file/memory.dart';
import 'package:blog_builder/src/webp_html_processor.dart';

void main() {
  group('WebPHtmlProcessor', () {
    late MemoryFileSystem fileSystem;
    late WebPHtmlProcessor processor;

    setUp(() {
      fileSystem = MemoryFileSystem();
      processor = WebPHtmlProcessor(fileSystem: fileSystem);
    });

    test('replaces single img tag with picture element', () {
      processor.registerWebPConversion('assets/image.png', 'assets/image.webp');

      final html = '<img src="/assets/image.png" alt="Test">';
      final result = processor.processHtml(html);

      expect(result, contains('<picture>'));
      expect(result, contains('<source srcset="/assets/image.webp" type="image/webp">'));
      expect(result, contains('<img src="/assets/image.png" alt="Test">'));
      expect(result, contains('</picture>'));
    });

    test('replaces multiple instances of the same image', () {
      processor.registerWebPConversion('assets/image.png', 'assets/image.webp');

      final html = '''
<div><img src="/assets/image.png" alt="First"></div>
<div><img src="/assets/image.png" alt="Second"></div>
<div><img src="/assets/image.png" alt="Third"></div>
''';
      final result = processor.processHtml(html);

      // Count picture elements
      final pictureCount = '<picture>'.allMatches(result).length;
      expect(pictureCount, equals(3));

      expect(result, contains('alt="First"'));
      expect(result, contains('alt="Second"'));
      expect(result, contains('alt="Third"'));
    });

    test('preserves all attributes from original img tag', () {
      processor.registerWebPConversion('assets/hero.png', 'assets/hero.webp');

      final html = '<img src="/assets/hero.png" alt="Hero" class="hero-image" id="main-hero" loading="lazy">';
      final result = processor.processHtml(html);

      expect(result, contains('alt="Hero"'));
      expect(result, contains('class="hero-image"'));
      expect(result, contains('id="main-hero"'));
      expect(result, contains('loading="lazy"'));
    });

    test('handles img tags without leading slash in src', () {
      processor.registerWebPConversion('assets/image.png', 'assets/image.webp');

      final html = '<img src="assets/image.png" alt="Test">';
      final result = processor.processHtml(html);

      expect(result, contains('<picture>'));
      expect(result, contains('<source srcset="/assets/image.webp" type="image/webp">'));
    });

    test('handles single-quoted attributes', () {
      processor.registerWebPConversion('assets/image.png', 'assets/image.webp');

      final html = "<img src='/assets/image.png' alt='Test'>";
      final result = processor.processHtml(html);

      expect(result, contains('<picture>'));
      expect(result, contains('alt="Test"'));
    });

    test('does not modify img tags without registered WebP', () {
      processor.registerWebPConversion('assets/other.png', 'assets/other.webp');

      final html = '<img src="/assets/unregistered.png" alt="Test">';
      final result = processor.processHtml(html);

      expect(result, equals(html));
      expect(result, isNot(contains('<picture>')));
    });

    test('handles self-closing img tags', () {
      processor.registerWebPConversion('assets/image.png', 'assets/image.webp');

      final html = '<img src="/assets/image.png" alt="Test" />';
      final result = processor.processHtml(html);

      expect(result, contains('<picture>'));
      expect(result, contains('</picture>'));
    });

    test('handles multiple different images', () {
      processor.registerWebPConversion('assets/a.png', 'assets/a.webp');
      processor.registerWebPConversion('assets/b.png', 'assets/b.webp');

      final html = '''
<img src="/assets/a.png" alt="A">
<img src="/assets/b.png" alt="B">
''';
      final result = processor.processHtml(html);

      expect(result, contains('srcset="/assets/a.webp"'));
      expect(result, contains('srcset="/assets/b.webp"'));
      expect('<picture>'.allMatches(result).length, equals(2));
    });

    test('hasWebPVersion returns correct value', () {
      processor.registerWebPConversion('assets/image.png', 'assets/image.webp');

      expect(processor.hasWebPVersion('assets/image.png'), isTrue);
      expect(processor.hasWebPVersion('/assets/image.png'), isTrue);
      expect(processor.hasWebPVersion('assets/other.png'), isFalse);
    });

    test('getWebPPath returns correct path', () {
      processor.registerWebPConversion('assets/image.png', 'assets/image.webp');

      expect(processor.getWebPPath('assets/image.png'), equals('assets/image.webp'));
      expect(processor.getWebPPath('/assets/image.png'), equals('assets/image.webp'));
      expect(processor.getWebPPath('assets/other.png'), isNull);
    });
  });
}
