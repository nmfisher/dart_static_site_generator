import 'dart:isolate';

import 'package:blog_builder/blog_builder.dart';
import 'package:blog_builder/src/fallback_root.dart';
import 'package:blog_builder/src/renderer.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:liquify/liquify.dart';
import 'package:path/path.dart' as pathlib;

class StaticSiteBuilder {
  final String inputDir;
  final String outputDir;
  late ConfigModel siteConfig;
  Root? _templateRoot;
  final TemplateRenderer? _injectedRenderer;
  TemplateRenderer? _renderer;
  int parseErrors = 0;
  int renderErrors = 0;
  
  // FileSystem abstraction for testability
  final FileSystem fileSystem;

  StaticSiteBuilder({
    required this.inputDir,
    required this.outputDir,
    this.fileSystem = const LocalFileSystem(),
    TemplateRenderer? renderer,
  }) : _injectedRenderer = renderer;
  
  // Getter for the renderer
  TemplateRenderer get renderer {
    if (_renderer != null) return _renderer!;
    if (_injectedRenderer != null) return _injectedRenderer!;
    throw StateError('Renderer not initialized. Call setupRenderer() or provide a renderer in the constructor.');
  }
  
  // Method to set up the renderer separately
  void setupRenderer(Root templateRoot) {
    _renderer = TemplateRenderer(templateRoot);
  }

  Future<void> build() async {
    print('Starting build process...');
    print('Input directory: ${pathlib.absolute(inputDir)}');
    print('Output directory: ${pathlib.absolute(outputDir)}');

    final outputDirectory = fileSystem.directory(outputDir);

    await _cleanAndCreateOutputDir(outputDirectory);
    await _parseConfig();
    await _setupTemplateRoot();
    
    // Initialize the renderer if not injected
    if (_injectedRenderer == null && _renderer == null) {
      setupRenderer(_templateRoot!);
    }

    final List<PageModel> pages = await _parseContent();

    await _generateIndexPages(
        fileSystem.directory(pathlib.join(inputDir, 'content')), pages);

    await _renderAllPages(pages);

    await _copyAssets();

    if (siteConfig.baseUrl != null) {
      await _generateSitemap(pages);
    } else {
      print('\nSkipping sitemap generation: baseUrl not set in config.yaml');
    }
  }

  Future<void> _cleanAndCreateOutputDir(Directory outputDirectory) async {
    try {
      if (await outputDirectory.exists()) {
        print('Cleaning output directory: $outputDir');
        await outputDirectory.delete(recursive: true);
      }
      await outputDirectory.create(recursive: true);
      print('Created output directory: $outputDir');
    } catch (e) {
      throw Exception(
          "Failed to clean or create output directory '$outputDir' : $e");
    }
  }

  Future<void> _parseConfig() async {
    final configFile = fileSystem.file(pathlib.join(inputDir, 'config.yaml'));
    print('\nChecking for config file: ${configFile.path}');

    if (!await configFile.exists()) {
      throw Exception('Required config.yaml file not found in $inputDir');
    }

    print('Parsing config.yaml...');
    try {
      siteConfig = ConfigModel.parse(configFile);
      print('Config loaded successfully (Title: ${siteConfig.title ?? 'N/A'})');
    } catch (e) {
      throw Exception('Failed to parse config.yaml : $e');
    }
  }

  Future<void> _setupTemplateRoot() async {
    final userTemplatesDirPath = pathlib.join(inputDir, 'templates');
    final userTemplatesDir = fileSystem.directory(userTemplatesDirPath);
    Root primaryRoot;

    print('\nChecking for user templates directory: $userTemplatesDirPath');
    if (await userTemplatesDir.exists()) {
      print('User templates found. Using: $userTemplatesDirPath');
      primaryRoot =
          FileSystemRoot(userTemplatesDirPath, fileSystem: fileSystem as LocalFileSystem);
    } else {
      print(
          'User templates directory not found. Will rely on bundled defaults.');
      primaryRoot = MapRoot({});
    }

    Root fallbackRoot; 
    try {
      final packageUri =
          Uri.parse('package:blog_builder/src/defaults/templates/');
      final resolvedUri = await Isolate.resolvePackageUri(packageUri);

      if (resolvedUri == null) {
        print(
            "Warning: Could not resolve package URI for bundled templates ($packageUri). Fallback templates unavailable.");
        fallbackRoot = MapRoot({});
      } else {
        final bundledTemplatesPath = pathlib.fromUri(resolvedUri);
        print('Located bundled default templates at: $bundledTemplatesPath');
        if (await fileSystem.directory(bundledTemplatesPath).exists()) {
          fallbackRoot = FileSystemRoot(bundledTemplatesPath,
              fileSystem: fileSystem as LocalFileSystem);
        } else {
          print(
              "Warning: Bundled templates directory does not exist at resolved path: $bundledTemplatesPath");
          fallbackRoot = MapRoot({});
        }
      }
    } catch (e, st) {
      print(
          "Warning: Error locating bundled default templates: $e\n$st. Fallback templates unavailable.");
      fallbackRoot = MapRoot({});
    }

    _templateRoot = FallbackRoot(primaryRoot, fallbackRoot);
    print('Template root configured with fallback support.');

    final defaultLayoutPath = '_layouts/default.liquid'.replaceAll(r'\', '/');
    try {
      await _templateRoot?.resolveAsync(defaultLayoutPath);
    } on Exception catch (e) {
      print(
          "Warning: Critical template '$defaultLayoutPath' not found in user templates or bundled defaults. Rendering might fail. Error: $e");
    } catch (e) {
      print(
          "Warning: Unexpected error checking for default layout '$defaultLayoutPath': $e");
    }
  }

  Future<List<PageModel>> _parseContent() async {
    final contentDirPath = pathlib.join(inputDir, 'content');
    final contentDir = fileSystem.directory(contentDirPath);
    print('\nChecking for content directory: $contentDirPath');

    if (!await contentDir.exists()) {
      print(
          'Warning: Content directory not found at $contentDirPath. No pages will be generated.');
      return [];
    }

    print('Processing markdown files...');
    final markdownFiles = await _findMarkdownFiles(contentDir);

    if (markdownFiles.isEmpty) {
      print(
          'Info: No markdown files (.md, .markdown) found in ${contentDir.path} or subdirectories.');
      return [];
    }

    final List<PageModel> pages = [];
    parseErrors = 0;

    for (final file in markdownFiles) {
      try {
        final relativePath = pathlib.relative(file.path, from: inputDir);
        print('Parsing: $relativePath');
        final pageModel = PageModel.from(file, contentDir);
        if (pageModel.draft) {
          print('  -> Skipping draft page: ${pageModel.route}');
        } else {
          pages.add(pageModel);
          print('  -> Parsed successfully: ${pageModel.route}');
        }
      } catch (e) {
        parseErrors++;
        final relativePath = pathlib.relative(file.path, from: inputDir);
        print('  -> Error parsing $relativePath: $e');
        print('  -> Skipping file due to error.');
      }
    }
    print('Markdown parsing complete. Found ${pages.length} non-draft pages.');
    if (parseErrors > 0) {
      print('Warning: Encountered $parseErrors parsing errors.');
    }
    return pages;
  }

  Future<void> _generateIndexPages(
      Directory contentDir, List<PageModel> pages) async {
    print('\nGenerating index page models...');
    int indexPagesGenerated = 0;

    final Set<String> generatedIndexRoutes = {};
    for (final page in pages) {
      if (page.route == '/' ||
          pathlib.basenameWithoutExtension(page.source).toLowerCase() ==
              'index') {
        generatedIndexRoutes.add(page.route);
        print(
            '  -> Found existing manual index page for route: ${page.route} (source: ${page.source})');
      }
    }

    final List<Directory> subDirs = [];
    try {
      await for (final entity
          in contentDir.list(recursive: true, followLinks: false)) {
        if (entity is Directory) {
          subDirs.add(entity);
        }
      }
    } catch (e) {
      print(
          "Warning: Error listing directories in ${contentDir.path} for index generation: $e");
      return;
    }

    final allDirs = [contentDir, ...subDirs];

    for (final dir in allDirs) {
      final relativeDirPath = pathlib.relative(dir.path, from: contentDir.path);
      final routePath =
          '/${relativeDirPath == '.' ? '' : relativeDirPath.replaceAll(r'\', '/')}';

      if (generatedIndexRoutes.contains(routePath)) {
        continue;
      }

      final dirPages = pages.where((p) {
        final pageSourceDir = pathlib.dirname(p.source);
        return pageSourceDir == dir.path && !p.isIndex;
      }).toList();

      if (dirPages.isNotEmpty) {
        print(
            '  -> Generating index model for directory: ${dir.path} (route: $routePath)');
        try {
          final indexPage = PageModel.index(dir, contentDir, dirPages);
          if (!generatedIndexRoutes.contains(indexPage.route)) {
            pages.add(indexPage);
            generatedIndexRoutes.add(indexPage.route);
            indexPagesGenerated++;
            print(
                '    -> Added index page model for route: ${indexPage.route}');
          } else {
            print(
                '    -> Skipping add - index model for route ${indexPage.route} was already generated.');
          }
        } catch (e) {
          print('    -> Error creating index model for ${dir.path}: $e');
        }
      }
    }

    if (indexPagesGenerated == 0) {
      print('No new index page models were generated.');
    } else {
      print('$indexPagesGenerated index page model(s) generated.');
    }
  }

  Future<void> _renderAllPages(List<PageModel> pages) async {
    if (pages.isEmpty) {
      print('\nNo pages (content or index) found to render.');
      return;
    }
    print('\nRendering ${pages.length} HTML page(s)...');
    renderErrors = 0;

    pages.sort((a, b) => a.route.compareTo(b.route));

    if (_templateRoot == null && _injectedRenderer == null) {
      throw Exception("Template root is not configured. Cannot render pages.");
    }

    for (final page in pages) {
      final layoutName = page.layoutId ?? (page.isIndex ? 'list' : 'default');
      final layoutPath = '_layouts/$layoutName.liquid'.replaceAll(r'\', '/');

      print('Rendering: ${page.route} (Source: ${pathlib.relative(page.source, from: inputDir)}) using layout "$layoutPath"');

      try {
        // Use the renderer to render the page
        final renderedContent = await renderer.renderPageWithSiteConfig(
          page, 
          siteConfig
        );
        
        // Write the rendered content to a file
        await _writeOutputFile(page, renderedContent);
      } catch (e, stackTrace) {
        renderErrors++;
        print('--------------------------');
        print('Error rendering page: ${page.source}');
        print('Route: ${page.route}');
        print('Layout used: $layoutName');
        print('Error: $e');
        print(stackTrace);
        print('--------------------------');
      }
    }
    print('HTML rendering complete.');
    if (renderErrors > 0) {
      print('Warning: Encountered $renderErrors rendering/writing errors.');
    }
  }

  Future<void> _writeOutputFile(PageModel page, String renderedContent) async {
    String relativePath =
        page.route.startsWith('/') ? page.route.substring(1) : page.route;
    String outputPath;
    if (page.route == '/') {
      outputPath = pathlib.join(outputDir, 'index.html');
    } else {
      outputPath = pathlib.join(outputDir, relativePath, 'index.html');
    }

    final outputFilePath = pathlib.normalize(outputPath);
    final outputDirectoryPath = pathlib.dirname(outputFilePath);
    final outputDirectory = fileSystem.directory(outputDirectoryPath);

    try {
      if (!await outputDirectory.exists()) {
        await outputDirectory.create(recursive: true);
      }
      final outputFile = fileSystem.file(outputFilePath);
      await outputFile.writeAsString(renderedContent);
      print(
          '  -> Generated: ${pathlib.relative(outputFilePath, from: fileSystem.currentDirectory.path)}');
    } catch (e) {
      renderErrors++;
      print('  -> Error writing output file $outputFilePath: $e');
    }
  }

  Future<void> _copyAssets() async {
    final assetsDirPath = pathlib.join(inputDir, 'assets');
    final assetsDir = fileSystem.directory(assetsDirPath);
    print('\nChecking for assets directory: $assetsDirPath');

    if (!await assetsDir.exists()) {
      print(
          'Assets directory not found at ${assetsDir.path}, skipping asset copy.');
      return;
    }

    final outputAssetsDirPath = pathlib.join(outputDir, 'assets');
    final outputAssetsDir = fileSystem.directory(outputAssetsDirPath);

    print('Copying assets from $assetsDirPath to $outputAssetsDirPath...');

    if (!await outputAssetsDir.exists()) {
      await outputAssetsDir.create(recursive: true);
    }
    await _copyDirectory(assetsDir, outputAssetsDir);
    print('Assets copied successfully.');
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity
        in source.list(recursive: false, followLinks: false)) {
      final newPath =
          pathlib.join(destination.path, pathlib.basename(entity.path));
      if (entity is File) {
        try {
          await entity.copy(newPath);
        } catch (e) {
          print(
              '  Warning: Failed to copy file ${entity.path} to $newPath: $e');
        }
      } else if (entity is Directory) {
        final newDir = fileSystem.directory(newPath);
        try {
          await newDir.create(recursive: true);
          await _copyDirectory(entity, newDir);
        } catch (e) {
          print(
              '  Warning: Failed to create/copy directory ${entity.path} to $newPath: $e');
        }
      }
    }
  }

  Future<List<File>> _findMarkdownFiles(Directory dir) async {
    final List<File> results = [];
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File &&
            (entity.path.endsWith('.md') ||
                entity.path.endsWith('.markdown'))) {
          results.add(entity);
        }
      }
    } catch (e) {
      throw Exception("Error reading content directory ${dir.path} : $e");
    }
    return results;
  }

  Future<void> _generateSitemap(List<PageModel> pages) async {
    print('\nGenerating sitemap...');
    final sitemapFile = pathlib.join(outputDir, 'sitemap.xml');
    try {
      if (siteConfig.baseUrl == null || siteConfig.baseUrl!.isEmpty) {
        print(
            "Warning: Cannot generate sitemap. 'baseUrl' is missing in config.yaml");
        return;
      }
      SitemapGenerator.generateFromPageModels(
        pages,
        siteConfig.baseUrl!,
        outFile: sitemapFile,
      );
      print('Sitemap generated successfully at $sitemapFile');
    } catch (e) {
      print('Error generating sitemap: $e');
    }
  }
}