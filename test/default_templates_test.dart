import 'dart:io';
import 'dart:isolate';
import 'package:file/local.dart';
import 'package:liquify/liquify.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Default Template Parsing Tests', () {
    late Root defaultTemplateRoot;
    late String defaultTemplatesPath;

    setUpAll(() async {
      // Find the bundled default templates directory
      final packageUri = Uri.parse('package:blog_builder/src/defaults/');
      final resolvedUri = await Isolate.resolvePackageUri(packageUri);

      if (resolvedUri == null) {
        fail(
            'Could not resolve package URI for bundled templates: $packageUri. '
            'Ensure the blog_builder package structure is correct.');
      }

      defaultTemplatesPath = p.fromUri(resolvedUri);
      final templatesDir = Directory(defaultTemplatesPath);
      if (!await templatesDir.exists()) {
        fail(
            'Bundled templates directory not found at resolved path: $defaultTemplatesPath');
      }

      print(
          'Resolved default templates path for testing: $defaultTemplatesPath');
      defaultTemplateRoot =
          FileSystemRoot(defaultTemplatesPath, fileSystem: LocalFileSystem());
    });

    // Helper function to read template content
    Future<String> readTemplate(String relativePath) async {
      final file = File(p.join(defaultTemplatesPath, relativePath));
      if (!await file.exists()) {
        fail('Template file not found for testing: ${file.path}');
      }
      return file.readAsString();
    }

    test('Parses _layouts/default.liquid successfully', () async {
      final content = await readTemplate('_layouts/default.liquid');
      final template = Template.parse(
        content,
        root: defaultTemplateRoot, // Root needed for {% render %}
      );
      final rendered = template.render();
      print(rendered);
      expect(true,true);
    });

    test('Parses _layouts/post.liquid successfully', () async {
      final content = await readTemplate('_layouts/post.liquid');
      expect(
        () => Template.parse(
          content,
          root:
              defaultTemplateRoot, // Root needed for {% layout %} and potentially {% render %}
        ),
        returnsNormally,
        reason: 'Parsing _layouts/post.liquid should succeed.',
      );
    });

    test('Parses _layouts/list.liquid successfully', () async {
      final content = await readTemplate('_layouts/list.liquid');
      expect(
        () => Template.parse(
          content,
          root:
              defaultTemplateRoot, // Root needed for {% layout %} and potentially {% render %}
        ),
        returnsNormally,
        reason: 'Parsing _layouts/list.liquid should succeed.',
      );
    });

    test('Parses _includes/header.liquid successfully', () async {
      final content = await readTemplate('_includes/header.liquid');
      // Includes often don't *need* a root just for parsing unless they contain {% render %} themselves
      // But providing it is safer and consistent.
      expect(
        () => Template.parse(
          content,
          root: defaultTemplateRoot,
        ),
        returnsNormally,
        reason: 'Parsing _includes/header.liquid should succeed.',
      );
    });

    test('Parses _includes/footer.liquid successfully', () async {
      final content = await readTemplate('_includes/footer.liquid');
      expect(
        () => Template.parse(
          content,
          root: defaultTemplateRoot,
        ),
        returnsNormally,
        reason: 'Parsing _includes/footer.liquid should succeed.',
      );
    });

    // Add test for home.liquid if it has unique content, otherwise it's covered by default.liquid parsing
    // test('Parses _layouts/home.liquid successfully', () async { ... });
  });
}
