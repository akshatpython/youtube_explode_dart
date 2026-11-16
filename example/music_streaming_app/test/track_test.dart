import 'package:flutter_test/flutter_test.dart';
import 'package:music_streaming_app/models/track.dart';

void main() {
  group('Track', () {
    const track = Track(
      videoId: 'dQw4w9WgXcQ',
      title: 'Never Gonna Give You Up',
      artist: 'Rick Astley',
      duration: Duration(minutes: 3, seconds: 33),
      thumbnailUrl: 'https://img.youtube.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
      localPath: '/data/music_downloads/dQw4w9WgXcQ.m4a',
    );

    test('formats durations without hours when under one hour', () {
      expect(track.formattedDuration, '03:33');
      expect(
        const Track(
          videoId: 'x',
          title: 't',
          artist: 'a',
          duration: Duration(hours: 1, minutes: 2, seconds: 5),
          thumbnailUrl: '',
        ).formattedDuration,
        '1:02:05',
      );
    });

    test('round-trips through JSON (SharedPreferences format)', () {
      final restored = Track.fromJson(track.toJson());
      expect(restored, track);
      expect(restored.localPath, track.localPath);
      expect(restored.isDownloaded, isTrue);
      expect(restored.duration, track.duration);
    });

    test('round-trips through MediaItem (queue format)', () {
      final restored = Track.fromMediaItem(track.toMediaItem());
      expect(restored, track);
      expect(restored.title, track.title);
      expect(restored.artist, track.artist);
      expect(restored.thumbnailUrl, track.thumbnailUrl);
    });

    test('copyWith can clear the local path', () {
      final streaming = track.copyWith(clearLocalPath: true);
      expect(streaming.isDownloaded, isFalse);
      expect(streaming.videoId, track.videoId);
    });
  });
}
