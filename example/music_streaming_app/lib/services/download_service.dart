import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'yt_service.dart';

/// Downloads audio streams to local storage and persists their metadata in
/// SharedPreferences, so the offline library is available instantly on the
/// next launch — with no internet connection at all.
class DownloadService {
  DownloadService({required YtService ytService}) : _ytService = ytService;

  final YtService _ytService;

  static const String _prefsKey = 'wave_music.downloaded_tracks.v1';
  static const String _folderName = 'music_downloads';

  /// All downloaded tracks (metadata + local path). Listen to rebuild the
  /// Downloads tab and download buttons.
  final ValueNotifier<List<Track>> downloads =
      ValueNotifier<List<Track>>(const <Track>[]);

  /// Live progress per videoId: 0.0 → 1.0. An entry exists only while the
  /// download is running; -1.0 means "started, size not known yet".
  final ValueNotifier<Map<String, double>> progress =
      ValueNotifier<Map<String, double>>(const <String, double>{});

  final Map<String, StreamSubscription<List<int>>> _activeSubscriptions =
      <String, StreamSubscription<List<int>>>{};
  final Map<String, Completer<void>> _activeCompleters =
      <String, Completer<void>>{};
  final Map<String, Completer<void>> _pipeCompleters =
      <String, Completer<void>>{};

  bool _loaded = false;

  bool isDownloading(String videoId) => progress.value.containsKey(videoId);

  double? progressFor(String videoId) => progress.value[videoId];

  bool isDownloaded(String videoId) =>
      downloads.value.any((track) => track.videoId == videoId);

  Track? downloadedTrack(String videoId) {
    for (final track in downloads.value) {
      if (track.videoId == videoId) return track;
    }
    return null;
  }

  /// Loads persisted metadata, dropping rows whose file was deleted outside
  /// the app (e.g. by a storage cleaner).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const <String>[];
    final loaded = <Track>[];
    for (final entry in raw) {
      try {
        final track =
            Track.fromJson(jsonDecode(entry) as Map<String, dynamic>);
        if (track.localPath != null &&
            await File(track.localPath!).exists()) {
          loaded.add(track);
        }
      } catch (_) {
        // Corrupted entry: skip it rather than breaking the whole library.
      }
    }
    downloads.value = List<Track>.unmodifiable(loaded);
    if (loaded.length != raw.length) await _persist();
  }

  /// Downloads [track] as an `.m4a` file. Calling this while the same track
  /// is already downloading is a no-op; calling it for an already-downloaded
  /// track completes immediately.
  Future<void> download(Track track) async {
    await load();
    final existing = downloadedTrack(track.videoId);
    if (existing != null && existing.localPath != null) {
      if (await File(existing.localPath!).exists()) return;
      downloads.value = downloads.value
          .where((item) => item.videoId != track.videoId)
          .toList(growable: false);
    }
    if (_activeCompleters.containsKey(track.videoId)) {
      return _activeCompleters[track.videoId]!.future;
    }

    final completer = Completer<void>();
    _activeCompleters[track.videoId] = completer;
    _setProgress(track.videoId, -1);

    RandomAccessFile? randomAccessFile;
    File? partFile;
    try {
      final data = await _ytService.getAudioStreamData(track.videoId);
      final directory = await _downloadsDirectory();
      final fileName =
          '${_sanitize(track.videoId)}.${data.fileExtension}';
      partFile = File('${directory.path}/$fileName.part');
      final finalFile = File('${directory.path}/$fileName');
      if (await partFile.exists()) await partFile.delete();

      randomAccessFile = await partFile.open(mode: FileMode.writeOnly);
      var received = 0;
      final subscription =
          _ytService.getStreamBytes(data.info).listen(null);
      _activeSubscriptions[track.videoId] = subscription;

      await _pipeToFile(
        videoId: track.videoId,
        subscription: subscription,
        sink: randomAccessFile,
        onBytes: (chunkLength) {
          received += chunkLength;
          if (data.totalBytes > 0) {
            _setProgress(
              track.videoId,
              (received / data.totalBytes).clamp(0.0, 1.0),
            );
          }
        },
      );
      await randomAccessFile.close();
      randomAccessFile = null;

      if (await finalFile.exists()) await finalFile.delete();
      await partFile.rename(finalFile.path);

      final downloaded = track.copyWith(localPath: finalFile.path);
      downloads.value = List<Track>.unmodifiable(
        <Track>[
          ...downloads.value
              .where((item) => item.videoId != track.videoId),
          downloaded,
        ],
      );
      await _persist();
      completer.complete();
    } catch (error, stackTrace) {
      await randomAccessFile?.close();
      try {
        if (partFile != null && await partFile.exists()) {
          await partFile.delete();
        }
      } catch (_) {
        // Best-effort cleanup only; the next attempt removes leftovers.
      }
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    } finally {
      _activeSubscriptions.remove(track.videoId);
      _activeCompleters.remove(track.videoId);
      _pipeCompleters.remove(track.videoId);
      _clearProgress(track.videoId);
    }
    return completer.future;
  }

  Future<void> _pipeToFile({
    required String videoId,
    required StreamSubscription<List<int>> subscription,
    required RandomAccessFile sink,
    required void Function(int chunkLength) onBytes,
  }) async {
    final done = Completer<void>();
    _pipeCompleters[videoId] = done;
    subscription.onData((chunk) {
      try {
        sink.writeFromSync(chunk);
        onBytes(chunk.length);
      } catch (error, stackTrace) {
        if (!done.isCompleted) done.completeError(error, stackTrace);
        subscription.cancel();
      }
    });
    subscription.onError((Object error, StackTrace stackTrace) {
      if (!done.isCompleted) done.completeError(error, stackTrace);
    });
    subscription.onDone(() {
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  /// Cancels an in-flight download and removes its partial file.
  Future<void> cancelDownload(String videoId) async {
    // Unblock DownloadService.download first; its cleanup then closes the
    // file handle and deletes the partial download.
    final pipe = _pipeCompleters[videoId];
    if (pipe != null && !pipe.isCompleted) {
      pipe.completeError(StateError('Download cancelled.'));
    }
    await _activeSubscriptions[videoId]?.cancel();
    _activeSubscriptions.remove(videoId);
    final completer = _activeCompleters.remove(videoId);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('Download cancelled.'));
    }
    _clearProgress(videoId);
    final directory = await _downloadsDirectory();
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path.contains(_sanitize(videoId)) &&
          entity.path.endsWith('.part')) {
        if (await entity.exists()) await entity.delete();
      }
    }
  }

  /// Deletes the local file and its persisted metadata.
  Future<void> deleteDownload(String videoId) async {
    await load();
    final track = downloadedTrack(videoId);
    if (track?.localPath != null) {
      final file = File(track!.localPath!);
      if (await file.exists()) await file.delete();
    }
    downloads.value = List<Track>.unmodifiable(
      downloads.value.where((item) => item.videoId != videoId),
    );
    await _persist();
  }

  /// Resolves a search-result / queue track to its downloaded copy, if any,
  /// so playback transparently prefers the offline file.
  Track resolveOfflineCopy(Track track) =>
      downloadedTrack(track.videoId) ?? track;

  Future<Directory> _downloadsDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/$_folderName');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      downloads.value.map((track) => jsonEncode(track.toJson())).toList(),
    );
  }

  void _setProgress(String videoId, double value) {
    progress.value = <String, double>{...progress.value, videoId: value};
  }

  void _clearProgress(String videoId) {
    if (!progress.value.containsKey(videoId)) return;
    final next = <String, double>{...progress.value}..remove(videoId);
    progress.value = Map<String, double>.unmodifiable(next);
  }

  String _sanitize(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  void dispose() {
    for (final subscription in _activeSubscriptions.values) {
      subscription.cancel();
    }
    _activeSubscriptions.clear();
    downloads.dispose();
    progress.dispose();
  }
}
