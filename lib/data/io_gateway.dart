/// Real `dart:io` file gateway with atomic write semantics.
///
/// A torn write (power cut mid-`writeAsString`) would truncate the day's
/// receipts into invalid JSON — the whole point of gap-free invoicing is
/// worthless if the file it lives in can be half-written. The write path is:
///
///   1. write the FULL new content to `<path>.tmp` with `flush: true`
///      (data is on disk — fsync — before the Future completes)
///   2. `rename()` the temp file over the target
///
/// `rename` within a directory is atomic on POSIX filesystems: any reader
/// (including this app after a crash) sees either the complete old file or
/// the complete new file — never a mix, never a truncated file.
library;

import 'dart:io';

import 'store.dart';

class IoFileGateway implements FileGateway {
  /// Test seam: invoked with the temp path after the temp file is durably
  /// flushed but *before* the atomic rename. Throwing here simulates a crash
  /// in the only window where a torn write could ever be observed.
  final void Function(String tmpPath)? debugBeforeRename;

  const IoFileGateway({this.debugBeforeRename});

  @override
  Future<String?> read(String path) async {
    final f = File(path);
    return f.existsSync() ? await f.readAsString() : null;
  }

  @override
  Future<void> write(String path, String content) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    try {
      // flush: true => content is on disk before we rename over the target.
      await tmp.writeAsString(content, flush: true);
      debugBeforeRename?.call(tmp.path); // may throw (simulated crash)
      await tmp.rename(path); // atomic replace: old or new, never torn
    } catch (_) {
      // Best-effort cleanup so a failed write leaves no litter; the target
      // file itself was never touched, so the previous state survives intact.
      try {
        tmp.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }
}
