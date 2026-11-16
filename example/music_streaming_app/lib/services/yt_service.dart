import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/track.dart';

/// Raised when YouTube data cannot be resolved (offline, video removed,
/// age-restricted, no audio stream, ...). UI layers show [message] verbatim.
class YtServiceException implements Exception {
  const YtServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _CachedUrl {
  const _CachedUrl(this.url, this.expiresAt);

  final String url;
  final DateTime expiresAt;

  bool get isValid => DateTime.now().isBefore(expiresAt);
}

/// Resolved audio-stream details needed by the downloader.
class AudioStreamData {
  const AudioStreamData({
    required this.info,
    required this.totalBytes,
    required this.fileExtension,
  });

  final AudioOnlyStreamInfo info;
  final int totalBytes;

  /// `m4a` for MP4 audio (what YouTube serves for nearly all music videos).
  final String fileExtension;
}

/// On-device YouTube backend. Talks to YouTube directly through
/// `youtube_explode_dart` — there is no external server involved.
class YtService {
  YtService({YoutubeExplode? explode}) : _yt = explode ?? YoutubeExplode();

  final YoutubeExplode _yt;

  /// Stream URLs returned by YouTube expire after a few hours, so resolved
  /// URLs are reused for 30 minutes and then resolved again.
  static const Duration cacheTtl = Duration(minutes: 30);

  final Map<String, _CachedUrl> _urlCache = <String, _CachedUrl>{};

  YoutubeExplode get client => _yt;

  /// Searches YouTube and returns playable songs only (live streams and
  /// results without a duration cannot be queued reliably, so they are
  /// filtered out).
  Future<List<Track>> searchSongs(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <Track>[];
    try {
      final results = await _yt.search.search(trimmed);
      return results
          .where((video) => !video.isLive && video.duration != null)
          .map(
            (video) => Track(
              videoId: video.id.value,
              title: video.title,
              artist: video.author,
              duration: video.duration ?? Duration.zero,
              // maxResUrl is 1280x720 when available; the player and lists
              // fall back gracefully (see ArtworkImage error handling) for
              // the minority of videos that only ship lower resolutions.
              thumbnailUrl: video.thumbnails.maxResUrl,
            ),
          )
          .toList(growable: false);
    } on YtServiceException {
      rethrow;
    } catch (error) {
      throw YtServiceException(_friendlyError(error));
    }
  }

  /// Resolves (and caches for [cacheTtl]) the direct audio stream URL for
  /// [videoId], picking the highest-bitrate audio-only stream.
  Future<String> getAudioStreamUrl(String videoId) async {
    final cached = _urlCache[videoId];
    if (cached != null && cached.isValid) return cached.url;
    if (cached != null) _urlCache.remove(videoId);

    try {
      final streamInfo = await _resolveBestAudio(videoId);
      final url = streamInfo.url.toString();
      _urlCache[videoId] =
          _CachedUrl(url, DateTime.now().add(cacheTtl));
      return url;
    } catch (error) {
      throw YtServiceException(_friendlyError(error));
    }
  }

  /// Full stream info (including total size) for downloads.
  Future<AudioStreamData> getAudioStreamData(String videoId) async {
    try {
      final info = await _resolveBestAudio(videoId, preferMp4: true);
      return AudioStreamData(
        info: info,
        totalBytes: info.size.totalBytes,
        fileExtension: info.container.name == 'mp4'
            ? 'm4a'
            : info.container.name,
      );
    } catch (error) {
      throw YtServiceException(_friendlyError(error));
    }
  }

  /// Raw byte stream for [AudioStreamData.info]; used by DownloadService.
  Stream<List<int>> getStreamBytes(AudioOnlyStreamInfo info) {
    return _yt.videos.streamsClient.get(info);
  }

  /// Drops a cached URL, e.g. after playback fails with an expired link.
  void invalidateUrl(String videoId) => _urlCache.remove(videoId);

  void clearCache() => _urlCache.clear();

  void dispose() {
    clearCache();
    _yt.close();
  }

  Future<AudioOnlyStreamInfo> _resolveBestAudio(
    String videoId, {
    bool preferMp4 = false,
  }) async {
    final manifest =
        await _yt.videos.streamsClient.getManifest(VideoId(videoId));
    if (manifest.audioOnly.isEmpty) {
      throw const YtServiceException(
        'No audio stream is available for this video.',
      );
    }
    if (preferMp4) {
      final mp4Streams = manifest.audioOnly
          .where((stream) => stream.container.name == 'mp4')
          .toList();
      if (mp4Streams.isNotEmpty) return mp4Streams.withHighestBitrate();
    }
    return manifest.audioOnly.withHighestBitrate();
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('Failed host lookup')) {
      return 'No internet connection. Downloaded songs still work offline.';
    }
    if (text.contains('VideoUnavailable') ||
        text.contains('Video is not available')) {
      return 'This video is unavailable or has been removed.';
    }
    if (text.contains('Private') || text.contains('LoginRequired')) {
      return 'This video is private or requires sign-in.';
    }
    return 'Something went wrong while contacting YouTube. Please retry.';
  }
}
