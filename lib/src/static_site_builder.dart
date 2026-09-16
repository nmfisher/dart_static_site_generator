import 'dart:isolate';
import 'dart:async';
import 'dart:convert';
import 'build_cache.dart';
import 'content_catalog.dart';
import 'output_transaction.dart';
import 'markdown_features.dart';

import 'package:blog_builder/blog_builder.dart';
import 'package:blog_builder/src/fallback_root.dart';
import 'package:blog_builder/src/renderer.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:liquify/liquify.dart';
import 'package:path/path.dart' as pathlib;
import 'package:blog_builder/src/site_data_model.dart'; // New import
import 'package:blog_builder/src/webp_html_processor.dart';

class StaticSiteBuilder {
  final String inputDir;
  final String outputDir;
  final bool includeDrafts, preview, incremental, announce;
  late final BuildCache cache;
  String? _stagingDir;
  String get _destination => _stagingDir ?? outputDir;
  bool _checking = false;
  final List<BuildDiagnostic> diagnostics = [];
  final Map<String, String> renderedPages = {};
  Future<void> _pending = Future.value();
  ContentCatalog? _catalog;
  late ConfigModel siteConfig;
  late WebPHtmlProcessor webpProcessor;
  late SiteData siteData; // New field
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
    this.includeDrafts = false,
    this.preview = false,
    this.incremental = true,
    this.announce = true,
  }) : _injectedRenderer = renderer {
    webpProcessor = WebPHtmlProcessor(fileSystem: fileSystem);
    cache = BuildCache(
        fileSystem, fileSystem.path.join(inputDir, '.blog-cache'),
        enabled: incremental);
  }

  // Getter for the renderer
  TemplateRenderer get renderer {
    if (_renderer != null) return _renderer!;
    if (_injectedRenderer != null) return _injectedRenderer!;
    throw StateError(
        'Renderer not initialized. Call setupRenderer() or provide a renderer in the constructor.');
  }

  void setupRenderer(Root templateRoot) {
    _renderer = TemplateRenderer(templateRoot, cache: _checking ? null : cache);
  }

  Future<void> build() {
    final next = _pending.then((_) => _runBuild());
    _pending = next.catchError((_) {});
    return next;
  }

  Future<List<BuildDiagnostic>> check() {
    final next = _pending.then((_) async {
      _checking = true;
      try {
        await _runBuild();
      } catch (error) {
        if (diagnostics.isEmpty)
          diagnostics.add(BuildDiagnostic(inputDir, '$error'));
      } finally {
        _checking = false;
      }
      return List<BuildDiagnostic>.unmodifiable(diagnostics);
    });
    _pending = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _runBuild() async {
    diagnostics.clear();
    renderedPages.clear();
    cache.resetStats();
    await _validateOutputDirectory();
    final transaction =
        OutputTransaction(fileSystem, fileSystem.path.absolute(outputDir));
    try {
      if (!_checking) _stagingDir = await transaction.begin();
      await _buildSite();
      if (!_checking) await transaction.commit();
    } finally {
      if (_stagingDir != null) await transaction.discard();
      _stagingDir = null;
    }
  }

  Future<void> _buildSite() async {
    print('Input directory: ${pathlib.absolute(inputDir)}');
    print('Output directory: ${pathlib.absolute(outputDir)}');

    parseErrors = 0;
    renderErrors = 0;
    webpProcessor.clear();
    await _validateOutputDirectory();
    await _parseConfig();
    if (siteConfig.rss.enabled) {
      final name = siteConfig.rss.fileName;
      _outputPath(name);
      final reserved = <String>{
        'sitemap.xml',
        'assets/style.css',
        'assets/css/site.css',
        if (siteConfig.searchEnabled) ...[
          'search-index.json',
          'assets/js/search.js'
        ],
        if (siteConfig.atProto.enabled) ...[
          'assets/js/at_comments.js',
          'assets/css/at_comments.css'
        ]
      };
      if (reserved.contains(name.toLowerCase()) ||
          (name.startsWith('assets/') &&
              fileSystem.file(pathlib.join(inputDir, name)).existsSync())) {
        throw FormatException(
            'RSS output conflicts with another generated file or asset: $name');
      }
    }

    await _setupTemplateRoot();

    if (_injectedRenderer == null) {
      if (_templateRoot == null) {
        throw StateError(
            'Template root was not initialized successfully before setting up renderer.');
      }
      setupRenderer(_templateRoot!);
    }

    List<PageModel> pages = await _parseContent();

    if (siteConfig.searchEnabled)
      pages.add(PageModel(
          title: 'Search',
          route: '/search',
          source: 'generated:/search',
          blurb: '',
          metadata: {},
          rawMarkdown: '',
          layoutId: 'search',
          draft: false));
    _catalog = ContentCatalog(siteConfig)
      ..collect(pages, pathlib.join(inputDir, 'content'));
    _catalog!.addNavigation(pages);
    pages.addAll(_catalog!.archives(pages));
    await _generateIndexPages(
        fileSystem.directory(pathlib.join(inputDir, 'content')), pages);

    diagnostics.addAll(SiteValidator.routes(pages));
    diagnostics.addAll(SiteValidator.outputs(pages, await _assetInventory()));
    if (diagnostics.isNotEmpty) throw StateError(diagnostics.join('\n'));

    // Create anchor posts for AT Protocol comments
    if (!_checking &&
        !preview &&
        !includeDrafts &&
        announce &&
        siteConfig.atProto.enabled &&
        siteConfig.baseUrl != null) {
      print('\nEnsuring AT Protocol anchor posts...');
      final announcer = AtProtoAnnouncer(config: siteConfig.atProto);
      pages = await announcer.ensureAnchorPosts(
        pages: pages,
        baseUrl:
            SiteUrls(siteConfig).absolute('/').replaceAll(RegExp(r'/+$'), ''),
      );
    }

    _catalog!.rebind(pages);

    // Build the hierarchical site data after all pages (including generated index pages) are parsed
    siteData = _buildSiteData(pages)..extraData = _catalog!.toMap;

    await _renderAllPages(pages);

    if (parseErrors > 0 || renderErrors > 0) {
      throw StateError(
          'Build failed: $parseErrors parse errors, $renderErrors render/write errors.');
    }

    if (_checking) {
      final assets = await _assetInventory();
      diagnostics.addAll(
          SiteValidator.links(renderedPages, pages, assets, siteConfig));
      return;
    }
    await _copyAssets();
    await _copySiteAssets();
    await _generateSearch(pages);

    // Process HTML to replace image references with WebP where available
    if (siteConfig.imageOptimization.webp.enabled) {
      print('\nProcessing HTML for WebP references...');
      final buildDir = fileSystem.directory(_destination);
      await webpProcessor.processHtmlDirectory(buildDir,
          basePath: siteConfig.basePath);
      webpProcessor.printSummary();
    }

    if (siteConfig.baseUrl != null && siteConfig.baseUrl!.isNotEmpty) {
      await _generateSitemap(pages);

      // Generate RSS feed
      if (siteConfig.rss.enabled) {
        await _generateRSSFeed(pages);
      }
    } else {
      print(
          '\nSkipping sitemap generation: baseUrl not set or empty in config.yaml');
    }
  }

  // Resolve existing ancestors as well as symlinks before checking containment.
  Future<String> _canonicalPath(String value) async {
    final absolute = fileSystem.path.normalize(fileSystem.path.absolute(value));
    final directory = fileSystem.directory(absolute);
    if (await directory.exists()) return directory.resolveSymbolicLinks();
    final parent = fileSystem.path.dirname(absolute);
    if (parent == absolute) return absolute;
    return fileSystem.path
        .join(await _canonicalPath(parent), fileSystem.path.basename(absolute));
  }

  Future<void> _validateOutputDirectory() async {
    final input = await _canonicalPath(inputDir);
    final output = await _canonicalPath(outputDir);
    final path = fileSystem.path;
    if (path.equals(input, output) || path.isWithin(output, input)) {
      throw ArgumentError(
          'Output directory must not equal or contain the input directory.');
    }
    for (final name in ['content', 'templates', 'assets', '.blog-cache']) {
      final source = await _canonicalPath(path.join(input, name));
      if (path.equals(source, output) ||
          path.isWithin(source, output) ||
          path.isWithin(output, source)) {
        throw ArgumentError(
            'Output directory overlaps the $name source directory.');
      }
    }
  }

  String _outputPath(String relativePath) {
    if (relativePath.isEmpty ||
        relativePath.contains('\\') ||
        pathlib.posix.isAbsolute(relativePath) ||
        pathlib.windows.isAbsolute(relativePath) ||
        relativePath.split('/').any((part) => part == '.' || part == '..')) {
      throw FormatException('Invalid output path: $relativePath');
    }
    final path = fileSystem.path;
    final output = path.normalize(path.absolute(_destination));
    final destination = path.normalize(path.join(output, relativePath));
    if (!path.isWithin(output, destination)) {
      throw FormatException(
          'Output path escapes the output directory: $relativePath');
    }
    return destination;
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
          throwOnMissing: true,
          fileSystem:
              fileSystem); // Correct: MemoryFileSystem for user templates
    } else {
      print(
          'User templates directory not found. Will rely on bundled defaults.');
      primaryRoot = MapRoot({}, throwOnMissing: true);
    }

    Root fallbackRoot;
    try {
      final packageUri = Uri.parse('package:blog_builder/src/defaults/');
      final resolvedUri = await Isolate.resolvePackageUri(packageUri);

      if (resolvedUri == null) {
        print(
            "Warning: Could not resolve package URI for bundled templates ($packageUri). Fallback templates unavailable.");
        fallbackRoot = MapRoot({}, throwOnMissing: true);
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
              throwOnMissing: true,
              fileSystem:
                  const LocalFileSystem()); // Correct: LocalFileSystem for real files
        } else {
          print(
              "Warning: Bundled templates directory (checked via LocalFileSystem) does not exist at resolved path: $bundledTemplatesPath");
          fallbackRoot = MapRoot({}, throwOnMissing: true);
        }
      }
    } catch (e, st) {
      print(
          "Warning: Error locating bundled default templates: $e\n$st. Fallback templates unavailable.");
      fallbackRoot = MapRoot({}, throwOnMissing: true);
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
        var pageModel = _parsePage(file, contentDir);
        final matchingCollections = siteConfig.collections.values.toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));
        for (final collection in matchingCollections) {
          if (pathlib.isWithin(
                  pathlib.join(contentDir.path, collection.path), file.path) &&
              pageModel.layoutId == null &&
              !pageModel.isIndex &&
              collection.layout != null) {
            pageModel = pageModel.copyWith(layoutId: collection.layout);
          }
        }
        _outputPath(pageModel.route == '/'
            ? 'index.html'
            : '${pageModel.route.substring(1)}/index.html');
        if (pageModel.draft && !includeDrafts) {
          print('  -> Skipping draft page: ${pageModel.route}');
        } else {
          pages.add(pageModel);
          print('  -> Parsed successfully: ${pageModel.route}');
        }
      } catch (e) {
        parseErrors++;
        diagnostics.add(BuildDiagnostic(file.path, '$e'));
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
      if (page.isIndex ||
          page.route == '/' ||
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
      if (routePath == '/' && dirPages.isEmpty) {
        dirPages.addAll(pages.where((p) => !p.isIndex && !p.generated));
      }
      if (dirPages.isNotEmpty || routePath == '/') {
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
          diagnostics.add(BuildDiagnostic(dir.path, '$e'));
          parseErrors++;
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

    if (_renderer == null && _injectedRenderer == null) {
      throw StateError("Renderer is not configured. Cannot render pages.");
    }

    renderErrors = 0;

    // Pass 1: Render content and store it in the PageModel
    print('\n--- Pass 1: Rendering content for ${pages.length} pages...');
    for (final page in pages) {
      try {
        page.renderedContent =
            await renderer.renderContent(page, siteConfig, siteData);
      } catch (e, stackTrace) {
        renderErrors++;
        diagnostics.add(BuildDiagnostic(page.source, '$e'));
        print('--------------------------');
        print('Error rendering content for page: ${page.source}');
        print('Route: ${page.route}');
        print('Error: $e');
        print('Stack Trace:\n$stackTrace');
        print('--------------------------');
      }
    }

    if (renderErrors > 0) {
      print(
          'Warning: Encountered $renderErrors errors during content rendering pass.');
      // Decide if you want to stop here or continue
    }

    // Pass 2: Render the full page with layout, now with access to all rendered content
    print('\n--- Pass 2: Rendering full layouts for ${pages.length} pages...');
    pages.sort((a, b) => a.route.compareTo(b.route));

    for (final page in pages) {
      final layoutName = page.layoutId ?? (page.isIndex ? 'list' : 'default');

      try {
        final renderedPage = await renderer.renderPageWithLayout(
          page,
          siteConfig,
          siteData,
          layoutName: layoutName,
        );

        renderedPages[page.route] = renderedPage;
        if (!_checking) await _writeOutputFile(page, renderedPage);
      } catch (e, stackTrace) {
        renderErrors++;
        diagnostics.add(BuildDiagnostic(page.source, '$e'));
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
      print(
          'Warning: Encountered a total of $renderErrors rendering/writing errors.');
    }
  }

  Future<void> _writeOutputFile(PageModel page, String renderedContent) async {
    // Convert route to relative file path
    // e.g., "/" -> "index.html"
    // e.g., "/about" -> "about/index.html"
    // e.g., "/posts/my-post" -> "posts/my-post/index.html"
    final relativePath =
        page.route.startsWith('/') ? page.route.substring(1) : page.route;
    final outputFilePath = _outputPath(
        page.route == '/' ? 'index.html' : '$relativePath/index.html');
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
      renderErrors++;
      diagnostics.add(BuildDiagnostic(page.source, '$e'));
      print('  -> Error writing output file $outputFilePath: $e');
    }
  }

  Future<void> _copyAssets() async {
    final assetsDirPath = pathlib.join(inputDir, 'assets');
    final assetsDir = fileSystem.directory(assetsDirPath);
    print('\nChecking for assets directory: $assetsDirPath');

    if (!await assetsDir.exists()) {
      if (siteConfig.atProto.enabled) await _copyBundledAtProtoAssets();
      print(
          'Assets directory not found at ${assetsDir.path}, skipping asset copy.');
      return;
    }

    final outputAssetsDirPath = pathlib.join(_destination, 'assets');
    final outputAssetsDir = fileSystem.directory(outputAssetsDirPath);

    // Initialize image processor if enabled
    ImageProcessor? imageProcessor;
    if (siteConfig.imageOptimization.enabled) {
      imageProcessor = ImageProcessor(config: siteConfig.imageOptimization);
      final webpStatus = siteConfig.imageOptimization.webp.enabled
          ? 'WebP: ON (quality: ${siteConfig.imageOptimization.webp.quality})'
          : 'WebP: OFF';
      print(
          'Image optimization enabled (PNG level: ${siteConfig.imageOptimization.png.level}, $webpStatus)');
    }

    print('Copying assets from $assetsDirPath to $outputAssetsDirPath...');

    if (!await outputAssetsDir.exists()) {
      await outputAssetsDir.create(recursive: true);
    }
    await _copyDirectory(assetsDir, outputAssetsDir,
        imageProcessor: imageProcessor);

    // Print image processing summary if enabled
    if (imageProcessor != null) {
      imageProcessor.stats.printSummary();
    }

    // Copy bundled AT Protocol assets if enabled
    if (siteConfig.atProto.enabled) {
      await _copyBundledAtProtoAssets();
    }

    print('Assets copied successfully.');
  }

  Future<void> _copyBundledAtProtoAssets() async {
    print('\nCopying bundled AT Protocol assets...');

    try {
      // Resolve the package URI to find bundled assets
      final packageUri = Uri.parse('package:blog_builder/src/defaults/assets/');
      final resolvedUri = await Isolate.resolvePackageUri(packageUri);

      if (resolvedUri == null) {
        print('Warning: Could not resolve bundled assets URI');
        return;
      }

      final bundledAssetsPath = resolvedUri.toFilePath();
      const bundledFileSystem = LocalFileSystem();
      final bundledAssetsDir = bundledFileSystem.directory(bundledAssetsPath);

      if (!await bundledAssetsDir.exists()) {
        print(
            'Warning: Bundled assets directory not found at $bundledAssetsPath');
        return;
      }

      // Copy JS files
      final jsSourcePath =
          pathlib.join(bundledAssetsPath, 'js', 'at_comments.js');
      final jsSourceFile = bundledFileSystem.file(jsSourcePath);

      if (await jsSourceFile.exists()) {
        final jsDestPath =
            pathlib.join(_destination, 'assets', 'js', 'at_comments.js');
        final jsDestDir = fileSystem.directory(pathlib.dirname(jsDestPath));

        if (!await jsDestDir.exists()) {
          await jsDestDir.create(recursive: true);
        }

        final jsDestFile = fileSystem.file(jsDestPath);
        await jsDestFile.writeAsString(await jsSourceFile.readAsString());
        print('  -> Copied: at_comments.js');
      }

      // Copy CSS files
      final cssSourcePath =
          pathlib.join(bundledAssetsPath, 'css', 'at_comments.css');
      final cssSourceFile = bundledFileSystem.file(cssSourcePath);

      if (await cssSourceFile.exists()) {
        final cssDestPath =
            pathlib.join(_destination, 'assets', 'css', 'at_comments.css');
        final cssDestDir = fileSystem.directory(pathlib.dirname(cssDestPath));

        if (!await cssDestDir.exists()) {
          await cssDestDir.create(recursive: true);
        }

        final cssDestFile = fileSystem.file(cssDestPath);
        await cssDestFile.writeAsString(await cssSourceFile.readAsString());
        print('  -> Copied: at_comments.css');
      }

      print('AT Protocol assets copied successfully.');
    } catch (e) {
      print('Warning: Failed to copy bundled AT Protocol assets: $e');
      rethrow;
    }
  }

  // Recursive directory copy helper using the injected fileSystem
  Future<void> _copyDirectory(
    Directory source,
    Directory destination, {
    ImageProcessor? imageProcessor,
  }) async {
    await for (final entity
        in source.list(recursive: false, followLinks: false)) {
      final newPath =
          pathlib.join(destination.path, pathlib.basename(entity.path));
      if (entity is File) {
        final assetKey = fingerprint([
          bytesFingerprint(await entity.readAsBytes()),
          pathlib.extension(entity.path),
          _imageConfigKey()
        ]);
        final cached = cache.read('asset-manifests', assetKey);
        if (cached != null &&
            await _restoreAsset(cached, assetKey, entity.path, newPath)) {
          cache.assetHits++;
          continue;
        }
        // Check if this is an image that should be processed
        if (imageProcessor != null && imageProcessor.isImageFile(entity.path)) {
          final outputFile = fileSystem.file(newPath);

          // Check if WebP conversion is enabled
          if (siteConfig.imageOptimization.webp.enabled) {
            final results = await imageProcessor.processImageWithWebP(
              entity,
              outputFile,
              fileSystem: fileSystem,
              assetsBasePath: pathlib.join(inputDir, 'assets'),
            );

            // Register WebP conversions with the HTML processor
            for (final result in results) {
              if (result.success &&
                  !imageProcessor.isWebp(entity.path) &&
                  result.outputPath.endsWith('.webp')) {
                // Calculate relative paths for HTML processing
                final originalRelative = pathlib.relative(entity.path,
                    from: pathlib.join(inputDir, 'assets'));
                final webpRelative =
                    pathlib.relative(result.outputPath, from: _destination);
                webpProcessor.registerWebPConversion(
                  pathlib
                      .join('assets', originalRelative)
                      .replaceAll(pathlib.separator, '/'),
                  webpRelative.replaceAll(pathlib.separator, '/'),
                );
              }
            }
            for (final result in results) {
              if (result.success) {
                if (result.outputPath.endsWith('.webp')) {
                  print(
                      '  -> WebP created: ${pathlib.basename(result.outputPath)} '
                      '(${ImageProcessingStats.formatBytes(result.originalSize)} → '
                      '${ImageProcessingStats.formatBytes(result.compressedSize)}, '
                      '-${result.savingsPercent.toStringAsFixed(1)}%)');
                } else if (result.savings > 0) {
                  print(
                      '  -> Compressed: ${pathlib.basename(result.outputPath)} '
                      '(${ImageProcessingStats.formatBytes(result.originalSize)} → '
                      '${ImageProcessingStats.formatBytes(result.compressedSize)}, '
                      '-${result.savingsPercent.toStringAsFixed(1)}%)');
                } else {
                  print(
                      '  -> Copied (no savings): ${pathlib.basename(result.outputPath)}');
                }
              } else {
                throw StateError('Image processing failed: ${result.error}');
              }
            }
          } else {
            // Use regular image processing without WebP
            final result =
                await imageProcessor.processImage(entity, outputFile);
            if (result.success && result.savings > 0) {
              print('  -> Compressed: ${pathlib.basename(entity.path)} '
                  '(${ImageProcessingStats.formatBytes(result.originalSize)} → '
                  '${ImageProcessingStats.formatBytes(result.compressedSize)}, '
                  '-${result.savingsPercent.toStringAsFixed(1)}%)');
            } else if (result.success) {
              print(
                  '  -> Copied (no savings): ${pathlib.basename(entity.path)}');
            } else {
              throw StateError('Image processing failed: ${result.error}');
            }
          }
        } else {
          // Use the filesystem's copy method for non-image files
          try {
            await entity.copy(newPath);
          } catch (e) {
            print(
                '  Warning: Failed to copy file ${entity.path} to $newPath: $e');
            rethrow;
          }
        }
        await _cacheAsset(assetKey, entity.path, newPath);
      } else if (entity is Directory) {
        // Create the destination subdirectory using the filesystem
        final newDir = fileSystem.directory(newPath);
        try {
          await newDir.create(recursive: true);
          // Recurse into the subdirectory
          await _copyDirectory(entity, newDir, imageProcessor: imageProcessor);
        } catch (e) {
          print(
              '  Warning: Failed to create/copy directory ${entity.path} to $newPath: $e');
          rethrow;
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
    final sitemapFile = pathlib.join(_destination, 'sitemap.xml');
    try {
      // Base URL check moved to build() method
      // Make the call async and pass the fileSystem
      await SitemapGenerator.generateFromPageModels(
        pages
            .where((p) => !p.draft)
            .toList(), // Ensure only non-drafts are included
        SiteUrls(siteConfig).absolute('/').replaceFirst(RegExp(r'/+$'), ''),
        outFile: sitemapFile,
        fileSystem: fileSystem, // Pass the builder's filesystem
      );
      // Success message handled inside SitemapGenerator
    } catch (e) {
      // Error message handled inside SitemapGenerator, just re-log here if needed
      print('Error occurred during sitemap generation step: $e');
      rethrow;
    }
  }

  Future<void> _generateRSSFeed(List<PageModel> pages) async {
    print('\nGenerating RSS feed...');
    final rssFile = _outputPath(siteConfig.rss.fileName);
    try {
      await RSSGenerator.generateFromPageModels(
        pages,
        siteConfig,
        outFile: rssFile,
        fileSystem: fileSystem,
      );
    } catch (e) {
      // Error message handled inside RSSGenerator, just re-log here if needed
      print('Error occurred during RSS generation step: $e');
      rethrow;
    }
  }

  PageModel _parsePage(File file, Directory contentDir) {
    final key = fingerprint(
        [file.path, file.readAsStringSync(), siteConfig.fallbackMetaTags]);
    final cached = _checking ? null : cache.read('pages', key);
    if (cached != null) {
      cache.parsedHits++;
      if (cached['date'] != null)
        cached['date'] = DateTime.parse(cached['date']);
      return PageModel.fromMap(cached);
    }
    final page = PageModel.from(file, contentDir,
        useFallbackMetaTags: siteConfig.fallbackMetaTags);
    if (!_checking)
      cache.write('pages', key, {
        'title': page.title,
        'route': page.route,
        'source': page.source,
        'rawMarkdown': page.rawMarkdown,
        'layoutId': page.layoutId,
        'templateId': page.templateId,
        'metadata': page.metadata,
        'blurb': page.blurb,
        'date': page.date?.toIso8601String(),
        'draft': page.draft,
        'isIndex': page.isIndex,
        'atUri': page.atUri,
        'extras': page.extras,
      });
    return page;
  }

  Object _imageConfigKey() {
    final c = siteConfig.imageOptimization;
    return [
      c.enabled,
      c.png.enabled,
      c.png.level,
      c.png.stripMetadata,
      c.jpeg.enabled,
      c.jpeg.quality,
      c.webp.enabled,
      c.webp.quality,
      c.webp.method,
      c.webp.createFallbacks
    ];
  }

  void _registerWebP(String original, String converted) {
    webpProcessor.registerWebPConversion(
        pathlib
            .join(
                'assets',
                pathlib.relative(original,
                    from: pathlib.join(inputDir, 'assets')))
            .replaceAll(pathlib.separator, '/'),
        pathlib
            .relative(converted, from: _destination)
            .replaceAll(pathlib.separator, '/'));
  }

  Future<bool> _restoreAsset(Map<String, dynamic> manifest, String key,
      String original, String output) async {
    if (!cache.enabled) return false;
    final outputs = <String, String>{
      if (manifest['original'] == true) 'original': output,
      if (manifest['webp'] == true)
        'webp': '${pathlib.withoutExtension(output)}.webp'
    };
    if (outputs.isEmpty ||
        outputs.keys.any(
            (name) => !fileSystem.file(cache.artifact(key, name)).existsSync()))
      return false;
    for (final entry in outputs.entries) {
      await fileSystem.file(cache.artifact(key, entry.key)).copy(entry.value);
    }
    if (outputs.containsKey('webp')) _registerWebP(original, outputs['webp']!);
    return true;
  }

  Future<void> _cacheAsset(String key, String source, String output) async {
    if (!cache.enabled) return;
    final converted = '${pathlib.withoutExtension(output)}.webp';
    final outputs = <String, String>{
      if (await fileSystem.file(output).exists()) 'original': output
    };
    if (siteConfig.imageOptimization.enabled &&
        siteConfig.imageOptimization.webp.enabled &&
        ['.png', '.jpg', '.jpeg']
            .contains(pathlib.extension(source).toLowerCase()) &&
        await fileSystem.file(converted).exists()) outputs['webp'] = converted;
    for (final entry in outputs.entries) {
      final target = fileSystem.file(cache.artifact(key, entry.key));
      await target.parent.create(recursive: true);
      await fileSystem.file(entry.value).copy(target.path);
    }
    cache.write(
        'asset-manifests', key, {for (final name in outputs.keys) name: true});
  }

  Future<Directory> _bundledAssets() async {
    final uri = await Isolate.resolvePackageUri(
        Uri.parse('package:blog_builder/src/defaults/assets/'));
    if (uri == null) throw StateError('Bundled assets could not be located');
    return const LocalFileSystem().directory(uri.toFilePath());
  }

  Future<void> _copySiteAssets() async {
    final bundled = await _bundledAssets();
    for (final name in [
      'style.css',
      'css/site.css',
      if (siteConfig.searchEnabled) 'js/search.js'
    ]) {
      final target = fileSystem.file(_outputPath('assets/$name'));
      if (await target.exists()) continue;
      await target.parent.create(recursive: true);
      await target.writeAsBytes(await bundled.childFile(name).readAsBytes());
    }
  }

  Future<Set<String>> _assetInventory() async {
    final paths = <String>{'/assets/style.css', '/assets/css/site.css'};
    if (siteConfig.searchEnabled)
      paths.addAll(['/assets/js/search.js', '/search-index.json']);
    if (siteConfig.atProto.enabled)
      paths
          .addAll(['/assets/js/at_comments.js', '/assets/css/at_comments.css']);
    if (siteConfig.baseUrl?.isNotEmpty == true) {
      paths.add('/sitemap.xml');
      if (siteConfig.rss.enabled) paths.add('/${siteConfig.rss.fileName}');
    }
    final assets = fileSystem.directory(pathlib.join(inputDir, 'assets'));
    if (await assets.exists()) {
      await for (final entity
          in assets.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final name =
              '/assets/${pathlib.relative(entity.path, from: assets.path).replaceAll(pathlib.separator, '/')}';
          paths.add(name);
          if (siteConfig.imageOptimization.enabled &&
              siteConfig.imageOptimization.webp.enabled &&
              ['.png', '.jpg', '.jpeg'].contains(pathlib.extension(name)))
            paths.add('${pathlib.withoutExtension(name)}.webp');
        }
      }
    }
    return paths;
  }

  Future<void> _generateSearch(List<PageModel> pages) async {
    if (!siteConfig.searchEnabled) return;
    final urls = SiteUrls(siteConfig);
    final records = pages
        .where((p) => !p.generated && !p.isIndex && (!p.draft || includeDrafts))
        .map((page) => {
              'title': page.title,
              'url': urls.relative('${page.route}/'),
              'text': plainContent(page.renderedContent ?? ''),
              'tags': page.extras['tags'] ?? [],
            })
        .toList();
    await fileSystem
        .file(_outputPath('search-index.json'))
        .writeAsString(jsonEncode(records));
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
          final parentRoute = pathlib.posix.dirname(route);
          final parentName = pathlib.posix.basename(parentRoute);
          final parentNode = getOrCreateNode(
              parentRoute, parentName.isEmpty ? 'root' : parentName);
          parentNode.children[name] = newNode;
        }
      }
      return nodes[route]!;
    }

    for (final page in allPages) {
      final node =
          getOrCreateNode(page.route, pathlib.posix.basename(page.route));
      node.page = page;
      if (!page.isIndex && page.route != '/') {
        final parentRoute = pathlib.posix.dirname(page.route);
        getOrCreateNode(parentRoute, pathlib.posix.basename(parentRoute))
            .pages
            .add(page);
      }
    }
    return root;
  }
}
