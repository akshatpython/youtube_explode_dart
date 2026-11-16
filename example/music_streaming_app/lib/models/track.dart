import 'package:audio_service/audio_service.dart';

/// Immutable description of one playable song, used by every layer of the
/// app (search results, playback queue, offline downloads).
class Track {
  const Track({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.duration,
    required this.thumbnailUrl,
    this.localPath,
  });

  final String videoId;
  final String title;
  final String artist;
  final Duration duration;
  final String thumbnailUrl;

  /// Absolute path of the downloaded `.m4a` file, or null when streaming.
  final String? localPath;

  bool get isDownloaded => localPath != null && localPath!.isNotEmpty;

  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Track copyWith({
    String? videoId,
    String? title,
    String? artist,
    Duration? duration,
    String? thumbnailUrl,
    String? localPath,
    bool clearLocalPath = false,
  }) {
    return Track(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      duration: duration ?? this.duration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
    );
  }

  MediaItem toMediaItem() {
    return MediaItem(
      id: videoId,
      title: title,
      artist: artist,
      album: 'Wave Music',
      duration: duration,
      artUri: thumbnailUrl.isEmpty ? null : Uri.tryParse(thumbnailUrl),
      playable: true,
      extras: <String, dynamic>{
        'videoId': videoId,
        'thumbnailUrl': thumbnailUrl,
        'localPath': localPath,
      },
    );
  }

  factory Track.fromMediaItem(MediaItem item) {
    final extras = item.extras ?? const <String, dynamic>{};
    return Track(
      videoId: (extras['videoId'] as String?) ?? item.id,
      title: item.title,
      artist: item.artist ?? 'Unknown artist',
      duration: item.duration ?? Duration.zero,
      thumbnailUrl:
          (extras['thumbnailUrl'] as String?) ?? item.artUri?.toString() ?? '',
      localPath: extras['localPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'videoId': videoId,
      'title': title,
      'artist': artist,
      'durationMs': duration.inMilliseconds,
      'thumbnailUrl': thumbnailUrl,
      'localPath': localPath,
    };
  }

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      videoId: json['videoId'] as String,
      title: json['title'] as String,
      artist: (json['artist'] as String?) ?? 'Unknown artist',
      duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0),
      thumbnailUrl: (json['thumbnailUrl'] as String?) ?? '',
      localPath: json['localPath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          videoId == other.videoId &&
          localPath == other.localPath;

  @override
  int get hashCode => Object.hash(videoId, localPath);

  @override
  String toString() => 'Track($videoId, $title, downloaded=$isDownloaded)';
}
