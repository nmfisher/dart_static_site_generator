import 'dart:isolate';

import 'package:blog_builder/blog_builder.dart';
import 'package:blog_builder/src/fallback_root.dart';
import 'package:blog_builder/src/renderer.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:liquify/liquify.dart';
import 'package:path/path.dart' as pathlib;
import 'package:blog_builder/src/site_data_model.dart'; // New import

class StaticSiteBuilder {
  final String inputDir;
  final String outputDir;
  late ConfigModel siteConfig;
  late SiteData siteData; // New field
  Root? _templateRoot;
  final TemplateRenderer? _injectedRenderer;
  TemplateRenderer? _renderer;
  int parseErrors = 0;
  int renderErrors = 0;

  // FileSystem abstraction for testability
  final FileSystem fileSystem;

  late final _logger = Logger(this.runtimeType.toString());

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
    throw StateError(
        'Renderer not initialized. Call setupRenderer() or provide a renderer in the constructor.');
  }

  void setupRenderer(Root templateRoot) {
    _renderer = TemplateRenderer(templateRoot);
  }

  Future<void> build() async {
    print('Input directory: ${pathlib.absolute(inputDir)}');
    print('Output directory: ${pathlib.absolute(outputDir)}');

    final outputDirectory = fileSystem.directory(outputDir);

    await _cleanAndCreateOutputDir(outputDirectory);
    await _parseConfig();
    await _setupTemplateRoot();

    if (_injectedRenderer == null && _renderer == null) {
      if (_templateRoot == null) {
        throw StateError(
            'Template root was not initialized successfully before setting up renderer.');
      }
      setupRenderer(_templateRoot!);
    }

    final List<PageModel> pages = await _parseContent();

    await _generateIndexPages(
        fileSystem.directory(pathlib.join(inputDir, 'content')), pages);

    // Build the hierarchical site data after all pages (including generated index pages) are parsed
    siteData = _buildSiteData(pages);

    await _renderAllPages(pages);

    await _copyAssets();

    if (siteConfig.baseUrl != null && siteConfig.baseUrl!.isNotEmpty) {
      await _generateSitemap(pages);
    } else {
      print(
          '\nSkipping sitemap generation: baseUrl not set or empty in config.yaml');
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
      _logger.warn(
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
      primaryRoot = FileSystemRoot(userTemplatesDirPath,
          fileSystem:
              fileSystem); // Correct: MemoryFileSystem for user templates
    } else {
      print(
          'User templates directory not found. Will rely on bundled defaults.');
      primaryRoot = MapRoot({});
    }

    Root fallbackRoot;
    try {
      final packageUri = Uri.parse('package:blog_builder/src/defaults/');
      final resolvedUri = await Isolate.resolvePackageUri(packageUri);

      if (resolvedUri == null) {
        print(
            "Warning: Could not resolve package URI for bundled templates ($packageUri). Fallback templates unavailable.");
        fallbackRoot = MapRoot({});
      } else {
        // Ensure the URI scheme is file-based before converting
        if (!resolvedUri.isScheme('file')) {
          throw Exception(
              "Resolved package URI is not a file URI: $resolvedUri");
        }
        final bundledTemplatesPath =
            pathlib.fromUri(resolvedUri); // Use pathlib.fromUri
        print('Located bundled default templates at: $bundledTemplatesPath');

        // IMPORTANT: Check existence using LocalFileSystem explicitly
        final realBundledDir =
            const LocalFileSystem().directory(bundledTemplatesPath);
        if (await realBundledDir.exists()) {
          // Use await with LocalFileSystem
          // Explicitly use LocalFileSystem for the fallback root
          fallbackRoot = FileSystemRoot(bundledTemplatesPath,
              fileSystem:
                  const LocalFileSystem()); // Correct: LocalFileSystem for real files
        } else {
          print(
              "Warning: Bundled templates directory (checked via LocalFileSystem) does not exist at resolved path: $bundledTemplatesPath");
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

    // Check if the essential default layout can be resolved (this seems to work)
    final defaultLayoutPath = '_layouts/default.liquid'.replaceAll(r'\', '/');
    try {
      // Use resolve, not resolveAsync, maybe async timing issue? (Unlikely but try)
      _templateRoot?.resolve(defaultLayoutPath);
      print(
          "Successfully resolved '$defaultLayoutPath' via template root (sync check).");
      // Try async again for good measure, as renderer uses it
      await _templateRoot?.resolveAsync(defaultLayoutPath);
      print(
          "Successfully resolved '$defaultLayoutPath' via template root (async check).");
    } on Exception catch (e) {
      // Catch specific Exception type
      print(
          "Warning: Critical template '$defaultLayoutPath' not found in user templates or bundled defaults during setup check. Rendering might fail. Error: $e");
    } catch (e) {
      // Catch any other error
      print(
          "Warning: Unexpected error checking for default layout '$defaultLayoutPath' during setup: $e");
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

    // Keep track of routes for which an index page (manual or generated) exists
    final Set<String> generatedIndexRoutes = {};
    for (final page in pages) {
      // Identify manually created index pages (index.md or route: /)
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

    // Process contentDir itself first, then subdirectories
    final allDirs = [contentDir, ...subDirs];

    for (final dir in allDirs) {
      // Calculate the route path for this directory
      final relativeDirPath = pathlib.relative(dir.path, from: contentDir.path);
      // Handle root directory case and normalize slashes
      final routePath =
          '/${relativeDirPath == '.' ? '' : relativeDirPath.replaceAll(pathlib.separator, '/')}';

      // Skip if an index page for this route already exists (manual or previously generated)
      if (generatedIndexRoutes.contains(routePath)) {
        continue;
      }

      // Find non-index pages directly within this directory
      final dirPages = pages.where((p) {
        final pageSourceDir = pathlib.dirname(p.source);
        // Ensure we only consider pages directly in this directory, not subdirs
        return pageSourceDir == dir.path && !p.isIndex;
      }).toList();

      // Generate an index only if there are child pages in this specific directory
      if (dirPages.isNotEmpty) {
        print(
            '  -> Generating index model for directory: ${dir.path} (route: $routePath)');
        try {
          final indexPage = PageModel.index(dir, contentDir, dirPages);

          // Double-check route collision before adding
          if (!generatedIndexRoutes.contains(indexPage.route)) {
            pages.add(indexPage);
            generatedIndexRoutes
                .add(indexPage.route); // Mark this route as having an index
            indexPagesGenerated++;
            print(
                '    -> Added index page model for route: ${indexPage.route}');
          } else {
            // This should ideally not happen due to the check above, but safeguard anyway
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

    if (_renderer == null && _injectedRenderer == null) {
      throw StateError("Renderer is not configured. Cannot render pages.");
    }

    for (final page in pages) {
      final layoutName = page.layoutId ?? (page.isIndex ? 'list' : 'default');

      try {
        final renderedContent = await renderer.renderPageWithSiteConfig(
            page, siteConfig, siteData,
            layoutName: layoutName // Pass siteData
            );

        await _writeOutputFile(page, renderedContent);
      } catch (e, stackTrace) {
        renderErrors++;
        print('--------------------------');
        print('Error rendering page: ${page.source}');
        print('Route: ${page.route}');
        print('Layout used: $layoutName');
        print('Error: $e');
        print('Stack Trace:\n$stackTrace');
        print('--------------------------');
      }
    }
    print('HTML rendering complete.');
    if (renderErrors > 0) {
      print('Warning: Encountered $renderErrors rendering/writing errors.');
    }
  }

  Future<void> _writeOutputFile(PageModel page, String renderedContent) async {
    // Convert route to relative file path
    // e.g., "/" -> "index.html"
    // e.g., "/about" -> "about/index.html"
    // e.g., "/posts/my-post" -> "posts/my-post/index.html"
    String relativePath =
        page.route.startsWith('/') ? page.route.substring(1) : page.route;
    String outputPath;
    if (page.route == '/') {
      // Root index page
      outputPath = pathlib.join(outputDir, 'index.html');
    } else {
      // Other pages go into their own directory with an index.html
      outputPath = pathlib.join(outputDir, relativePath, 'index.html');
    }

    // Normalize the path for the current OS
    final outputFilePath = pathlib.normalize(outputPath);
    final outputDirectoryPath = pathlib.dirname(outputFilePath);
    final outputDirectory = fileSystem.directory(outputDirectoryPath);

    try {
      // Ensure the target directory exists
      if (!await outputDirectory.exists()) {
        await outputDirectory.create(recursive: true);
      }
      // Write the file using the injected filesystem
      final outputFile = fileSystem.file(outputFilePath);
      await outputFile.writeAsString(renderedContent);
      print(
          '  -> Generated: ${pathlib.relative(outputFilePath, from: fileSystem.currentDirectory.path)}');
    } catch (e) {
      renderErrors++; // Increment render error count if writing fails too
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

    try {
      if (!await outputAssetsDir.exists()) {
        await outputAssetsDir.create(recursive: true);
      }
      await _copyDirectory(assetsDir, outputAssetsDir);
      print('Assets copied successfully.');
    } catch (e) {
      print('Error during asset copy: $e');
      // Decide if this should be fatal or just a warning
    }
  }

  // Recursive directory copy helper using the injected fileSystem
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity
        in source.list(recursive: false, followLinks: false)) {
      final newPath =
          pathlib.join(destination.path, pathlib.basename(entity.path));
      if (entity is File) {
        try {
          // Use the filesystem's copy method
          await entity.copy(newPath);
        } catch (e) {
          print(
              '  Warning: Failed to copy file ${entity.path} to $newPath: $e');
        }
      } else if (entity is Directory) {
        // Create the destination subdirectory using the filesystem
        final newDir = fileSystem.directory(newPath);
        try {
          await newDir.create(recursive: true);
          // Recurse into the subdirectory
          await _copyDirectory(entity, newDir);
        } catch (e) {
          print(
              '  Warning: Failed to create/copy directory ${entity.path} to $newPath: $e');
        }
      }
    }
  }

  // Helper to find markdown files recursively using the injected filesystem
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
      // Make error more specific
      throw Exception("Error searching for markdown files in ${dir.path}: $e");
    }
    return results;
  }

  Future<void> _generateSitemap(List<PageModel> pages) async {
    print('\nGenerating sitemap...');
    final sitemapFile = pathlib.join(outputDir, 'sitemap.xml');
    try {
      // Base URL check moved to build() method
      // Make the call async and pass the fileSystem
      await SitemapGenerator.generateFromPageModels(
        pages
            .where((p) => !p.draft)
            .toList(), // Ensure only non-drafts are included
        siteConfig.baseUrl!,
        outFile: sitemapFile,
        fileSystem: fileSystem, // Pass the builder's filesystem
      );
      // Success message handled inside SitemapGenerator
    } catch (e) {
      // Error message handled inside SitemapGenerator, just re-log here if needed
      print('Error occurred during sitemap generation step: $e');
    }
  }

  // Builds a hierarchical SiteData object from a flat list of PageModels
  SiteData _buildSiteData(List<PageModel> allPages) {
    final SiteData root = SiteData(name: 'root', route: '/');
    final Map<String, SiteData> nodes = {
      '/': root
    }; // Map of route to SiteData node

    // Helper to get or create a SiteData node for a given route
    SiteData getOrCreateNode(String route, String name) {
      if (!nodes.containsKey(route)) {
        final newNode = SiteData(name: name, route: route);
        nodes[route] = newNode;

        // Link to parent
        if (route != '/') {
          final parentRoute = pathlib.dirname(route);
          final parentName = pathlib.basename(parentRoute);
          final parentNode = getOrCreateNode(
              parentRoute, parentName.isEmpty ? 'root' : parentName);
          parentNode.children[name] = newNode;
        }
      }
      return nodes[route]!;
    }

    // Create all directory nodes first, ensuring parents exist before children
    // Sort pages by route length to ensure parent directories are processed before children
    allPages.sort((a, b) => a.route.length.compareTo(b.route.length));

    for (final page in allPages) {
      final segments = pathlib.split(page.route);
      String currentPath = '';
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        if (segment.isEmpty && i == 0) {
          // Root
          currentPath = '/';
        } else if (segment.isNotEmpty) {
          currentPath = pathlib.join(currentPath, segment);
        } else {
          continue;
        }
        getOrCreateNode(
            currentPath, segment.isEmpty && i == 0 ? 'root' : segment);
      }
    }

    // Now, assign pages to their respective SiteData nodes
    for (final page in allPages) {
      final parentRoute = page.route == '/' ? '/' : pathlib.dirname(page.route);
      final parentNode = nodes[parentRoute];

      if (parentNode != null) {
        if (page.isIndex && page.route == parentNode.route) {
          // This page is the index for its directory. Assign it to the node's 'page' property.
          parentNode.page = page;
        } else {
          // Regular page, add to parent's pages list
          parentNode.pages.add(page);
        }
      } else {
        print("Warning: Could not find parent node for page: ${page.route}");
      }
    }
    return root;
  }
}
