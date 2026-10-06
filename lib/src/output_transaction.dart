import 'package:file/file.dart';

/// Build next to the destination (same filesystem), then publish by rename.
/// A failed build never touches the previous output; failed promotion rolls back.
class OutputTransaction {
  final FileSystem fs;
  final String destination;
  late Directory staging;

  /// When true, commit keeps the replaced output as a timestamped sibling
  /// backup instead of deleting it.
  final bool keepBackup;

  OutputTransaction(this.fs, this.destination, {this.keepBackup = false});

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
      final base = keepBackup
          ? '${fs.path.basename(destination)}-backup-${_backupStamp(DateTime.now())}'
          : '.${fs.path.basename(destination)}-backup';
      backup = await _moveAside(target, base);
    }
    try {
      await staging.rename(destination);
    } catch (_) {
      if (backup != null) {
        // A partial result may have landed at the destination before the
        // rename failed; remove it so the old output can be restored.
        if (await target.exists()) {
          try {
            await target.delete(recursive: true);
          } catch (_) {
            // Surface the original failure instead of a deletion error.
          }
        }
        await backup.rename(destination);
      }
      rethrow;
    }
    if (backup != null) {
      if (keepBackup) {
        print('Kept backup of previous output at ${backup.path}');
        return;
      }
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

  /// Renames [target] to a sibling directory based on [base], retrying with
  /// fresh suffixed names while a concurrent writer occupies the candidate
  /// path. Never deletes pre-existing data.
  Future<Directory> _moveAside(Directory target, String base) async {
    final parent = target.parent;
    for (var attempt = 0;; attempt++) {
      final suffix = attempt == 0 ? '' : '-${_backupStamp(DateTime.now())}-$attempt';
      final backup = parent.childDirectory('$base$suffix');
      try {
        await target.rename(backup.path);
        return backup;
      } on FileSystemException {
        // Candidate occupied by a concurrent commit: try a fresh name.
        final occupied = await backup.exists();
        if (!occupied || attempt > 16) rethrow;
      }
    }
  }

  static String _backupStamp(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}-'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';
}
