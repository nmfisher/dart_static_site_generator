import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:blog_builder/blog_builder.dart'; // Use the main library export

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('input', abbr: 'i', help: 'Input directory containing config.yaml, content/, templates/, assets/', defaultsTo: 'example_blog')
    ..addOption('output', abbr: 'o', help: 'Output directory for generated site', defaultsTo: 'build')
    ..addFlag('help', abbr: 'h', help: 'Show usage information', negatable: false);

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

    // Validate input directory existence
    if (!await Directory(inputDir).exists()) {
       print('Error: Input directory not found: $inputDir');
       exit(1);
    }


    final siteBuilder = StaticSiteBuilder(
      inputDir: inputDir,
      outputDir: outputDir,
    );

  try {
    await siteBuilder.build();
     print('\nBuild completed successfully!');
     print('Output written to: ${p.absolute(outputDir)}');
  } catch (e, stackTrace) {
    print('\nBuild failed: $e');
    if (e is! Exception) { // Print stack trace for unexpected errors
        print(stackTrace);
    }
    exit(1);
  }
}

class StaticSiteBuilder {
  final String inputDir;
  final String outputDir;

  // Use the specific ConfigModel
  late ConfigModel siteConfig;

  // Store parsed templates by name
  final Map<String, Template> templates = {};

  // Store parsed pages
  final List<PageModel> pages = [];

  StaticSiteBuilder({
    required this.inputDir,
    required this.outputDir,
  });

  Future<void> build() async {
    print('Starting build process...');
    print('Input directory: ${p.absolute(inputDir)}');
    print('Output directory: ${p.absolute(outputDir)}');

    final outputDirectory = Directory(outputDir);
    try {
      // Clean output directory before build
      if (await outputDirectory.exists()) {
        print('Cleaning output directory: $outputDir');
        await outputDirectory.delete(recursive: true);
      }
      await outputDirectory.create(recursive: true);
      print('Created output directory: $outputDir');

      // Step 1: Parse config.yaml
      await _parseConfig();

      // Step 2 & 3: Load all templates
      await _loadTemplates();

      // Step 4 & 5 & 6: Process all markdown files
      await _processContent();

      // Step 7: Copy assets folder
      await _copyAssets();

      // Optional Step 8: Generate sitemap (can be added here if needed)
      // await _generateSitemap();

    } catch (e) {
      print('--------------------------');
      print('Build Error:');
      print(e);
      print('--------------------------');
      // Don't rethrow here, allow main to handle exit
      throw Exception('Build process failed.'); // Throw a generic exception
    }
  }

  Future<void> _parseConfig() async {
    final configFile = File(p.join(inputDir, 'config.yaml'));
    print('\nChecking for config file: ${configFile.path}');

    if (!await configFile.exists()) {
      throw Exception('Required config.yaml file not found in $inputDir');
    }

    print('Parsing config.yaml...');
    try {
       // Use the specific ConfigModel parser
      siteConfig = ConfigModel.parse(configFile);
      print('Config loaded successfully (Title: ${siteConfig.title ?? 'N/A'})');
    } catch(e) {
       throw Exception('Failed to parse config.yaml: $e');
    }
  }

  Future<void> _loadTemplates() async {
    final templatesDirPath = p.join(inputDir, 'templates');
    final templatesDir = Directory(templatesDirPath);
    print('\nChecking for templates directory: $templatesDirPath');

    if (!await templatesDir.exists()) {
      throw Exception('Templates directory not found at $templatesDirPath');
    }

    print('Loading templates...');
    final templateFiles = await templatesDir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.html'))
        .cast<File>() // Cast to File stream
        .toList();

    if (templateFiles.isEmpty) {
      print('Warning: No HTML templates found in $templatesDirPath. Using default behavior.');
      // Allow proceeding without templates if desired, or throw here:
      // throw Exception('No HTML templates found in ${templatesDir.path}');
    }

    for (final file in templateFiles) {
        final templateName = p.basenameWithoutExtension(file.path);
        final templateContent = await file.readAsString();

        // Use the placeholder template parser
        templates[templateName] = TemplateParser.parse(templateContent);
        print('Loaded template: $templateName');
    }

    // Verify default template exists if needed by logic (optional based on requirements)
    if (!templates.containsKey('default')) {
      print("Warning: 'default.html' template not found. Pages without a specified layout/template might fail to render.");
    }
  }

  Future<void> _processContent() async {
     final contentDirPath = p.join(inputDir, 'content');
     final contentDir = Directory(contentDirPath);
      print('\nChecking for content directory: $contentDirPath');

    if (!await contentDir.exists()) {
      throw Exception('Content directory not found at $contentDirPath');
    }

    print('Processing markdown files...');
    final markdownFiles = await _findMarkdownFiles(contentDir);

    if (markdownFiles.isEmpty) {
       print('Warning: No markdown files (.md, .markdown) found in ${contentDir.path} or subdirectories.');
      return; // Nothing to process
    }

     // First Pass: Parse all markdown files into PageModels
    for (final file in markdownFiles) {
       try {
          print('Parsing: ${p.relative(file.path, from: inputDir)}');
          final pageModel = PageModel.from(file, contentDir); // Use PageModel parser
          if (pageModel.draft) {
             print('  -> Skipping draft page: ${pageModel.route}');
          } else {
             pages.add(pageModel);
          }
       } catch (e) {
          print('  -> Error parsing ${file.path}: $e');
          // Decide whether to skip the file or fail the build
          // throw Exception('Failed to parse markdown file: ${file.path}. Error: $e');
          print('  -> Skipping file due to error.');
       }
    }

    if (pages.isEmpty) {
       print('No non-draft pages found to build.');
       return;
    }

    print('\nGenerating HTML pages...');
    // Second Pass: Render and write files
    for (final page in pages) {
       await _renderAndWritePage(page);
    }
  }

  Future<List<File>> _findMarkdownFiles(Directory dir) async {
    final List<File> results = [];
    try {
       await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File && (entity.path.endsWith('.md') || entity.path.endsWith('.markdown'))) {
             results.add(entity);
          }
       }
    } catch (e) {
       throw Exception("Error reading content directory ${dir.path}: $e");
    }
    return results;
  }


  Future<void> _renderAndWritePage(PageModel page) async {
    // Determine the template to use
    // Prioritize 'layout' from frontmatter, then 'template', fallback to 'default'
    final templateName = page.layoutId ?? page.templateId ?? 'default';

    if (!templates.containsKey(templateName)) {
      // If even 'default' is missing, we have a problem
      if (templateName == 'default' && !templates.containsKey('default')) {
          print('Error: Template "$templateName" (and default) not found for page: ${page.source}');
          print('Skipping this page.');
          return; // Skip rendering this page
      }
      // If a specific template is missing, fall back to default IF it exists
      else if (templates.containsKey('default')){
           print('Warning: Template "$templateName" not found for page ${page.source}. Falling back to "default" template.');
           final template = templates['default']!;
           await _renderWithTemplate(page, template, 'default');
      }
      // If specific template is missing AND default is missing
      else {
           print('Error: Template "$templateName" not found and no "default" template exists for page: ${page.source}');
           print('Skipping this page.');
           return; // Skip rendering this page
      }
    } else {
       // Found the specified or default template
       final template = templates[templateName]!;
       await _renderWithTemplate(page, template, templateName);
    }
  }

  Future<void> _renderWithTemplate(PageModel page, Template template, String templateNameUsed) async {
      print('Rendering: ${page.route} using template "$templateNameUsed"');

      // Prepare data for the template
      // Include site-wide config and page-specific data
      final Map<String, dynamic> renderData = {
         // Expose site config under 'site' namespace
         'site': siteConfig.toMap(), // Use the toMap method if available
         // Expose page data under 'page' namespace
         'page': page.toMap(), // Use the PageModel's toMap helper
         // Keep top-level 'content' for convenience with simple templates
         'content': page.html,
         // You could add other global data here, like a list of all pages
         // 'all_pages': pages.map((p) => p.toMap()).toList(),
      };

       // Render content with template
      final String renderedContent = template.render(renderData);

       // Write the output file
      await _writeOutputFile(page, renderedContent);
  }


  Future<void> _writeOutputFile(PageModel page, String renderedContent) async {
    // Calculate output path based on the PageModel's route
    // Route examples: "/", "/about", "/posts/my-post"
    String relativePath = page.route.substring(1); // Remove leading '/'

    String outputPath;
    if (page.route == '/') {
       outputPath = p.join(outputDir, 'index.html');
    } else {
       // Create paths like build/about/index.html or build/posts/my-post/index.html
       // This is common practice for cleaner URLs without extensions
       outputPath = p.join(outputDir, relativePath, 'index.html');

       // Alternative: build/about.html or build/posts/my-post.html
       // outputPath = p.join(outputDir, '$relativePath.html');
    }


    // Ensure the directory for the output file exists
    final outputDirectoryPath = p.dirname(outputPath);
    final outputDirectory = Directory(outputDirectoryPath);

    try {
       if (!await outputDirectory.exists()) {
          await outputDirectory.create(recursive: true);
       }

       // Write the file
       final outputFile = File(outputPath);
       await outputFile.writeAsString(renderedContent);

       print('  -> Generated: ${p.relative(outputPath, from: Directory.current.path)}');
    } catch (e) {
       print('  -> Error writing output file $outputPath: $e');
       // Decide whether to stop the build or just log the error
    }
  }

  Future<void> _copyAssets() async {
     final assetsDirPath = p.join(inputDir, 'assets');
    final assetsDir = Directory(assetsDirPath);
     print('\nChecking for assets directory: $assetsDirPath');

    if (!await assetsDir.exists()) {
      print('Assets directory not found at ${assetsDir.path}, skipping asset copy.');
      return;
    }

    final outputAssetsDirPath = p.join(outputDir, 'assets');
    final outputAssetsDir = Directory(outputAssetsDirPath);

    print('Copying assets from $assetsDirPath to $outputAssetsDirPath...');

    try {
       // Create the output assets directory (might already exist if cleaned)
       if (!await outputAssetsDir.exists()) {
          await outputAssetsDir.create();
       }

       // Copy all assets recursively
       await _copyDirectory(assetsDir, outputAssetsDir);
       print('Assets copied successfully.');
    } catch (e) {
       throw Exception('Failed to copy assets: $e');
    }
  }

  // Recursive directory copy helper
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list(recursive: false, followLinks: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is File) {
        try {
            await entity.copy(newPath);
            // print('  Copied file: ${p.relative(newPath, from: outputDir)}');
        } catch (e) {
           print('  Warning: Failed to copy file ${entity.path} to $newPath: $e');
        }
      } else if (entity is Directory) {
        final newDir = Directory(newPath);
         try {
            await newDir.create();
            // print('  Created dir: ${p.relative(newPath, from: outputDir)}');
            await _copyDirectory(entity, newDir); // Recurse
         } catch (e) {
            print('  Warning: Failed to create/copy directory ${entity.path} to $newPath: $e');
         }
      }
    }
  }

  // Optional: Method to generate sitemap using the utility
  // Future<void> _generateSitemap() async {
  //   print('\nGenerating sitemap...');
  //   if (siteConfig.baseUrl == null) { // Assuming baseUrl is added to ConfigModel
  //     print('Warning: Cannot generate sitemap. Add `baseUrl` to your config.yaml');
  //     return;
  //   }
  //   try {
  //     SitemapGenerator.generateFromPageModels(
  //       pages,
  //       siteConfig.baseUrl!,
  //       outFile: p.join(outputDir, 'sitemap.xml'),
  //     );
  //   } catch (e) {
  //     print('Error generating sitemap: $e');
  //   }
  // }
}
