import 'package:file/file.dart';

/// Build next to the destination (same filesystem), then publish by rename.
/// A failed build never touches the previous output; failed promotion rolls back.
class OutputTransaction {
  final FileSystem fs;
  final String destination;
  late Directory staging;
  OutputTransaction(this.fs, this.destination);
  Future<String> begin() async {
    final target = fs.directory(destination);
    await target.parent.create(recursive: true);
    staging = await target.parent
        .createTemp('.${fs.path.basename(destination)}-stage-');
    return staging.path;
  }

  Future<void> commit() async {
    final target = fs.directory(destination);
    Directory? backup;
    if (await target.exists()) {
      final placeholder = await target.parent
          .createTemp('.${fs.path.basename(destination)}-backup-');
      final name = placeholder.path;
      await placeholder.delete();
      backup = await target.rename(name);
    }
    try {
      await staging.rename(destination);
    } catch (_) {
      if (backup != null) await backup.rename(destination);
      rethrow;
    }
    if (backup != null) {
      try {
        await backup.delete(recursive: true);
      } catch (error) {
        print(
            'Build published; could not remove old output ${backup.path}: $error');
      }
    }
  }

  Future<void> discard() async {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
