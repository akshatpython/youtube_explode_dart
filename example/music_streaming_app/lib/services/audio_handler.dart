import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import 'yt_service.dart';

/// Background audio handler: bridges just_audio (playback) with
/// audio_service (media notification, lock screen, headset controls).
///
/// The queue is a [ConcatenatingAudioSource], so just_audio itself handles
/// skipping, Shuffle (true Shuffle order), and Repeat Off/One/All. Stream
/// URLs are resolved through [YtService] (30-minute cache) when a queue is
/// set; downloaded tracks play from their local file instead.
class MusicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MusicAudioHandler({required YtService ytService}) : _ytService = ytService {
    _listenToPlayerEvents();
  }

  final YtService _ytService;
  final AudioPlayer _player = AudioPlayer();

  List<Track> _tracks = <Track>[];
  ConcatenatingAudioSource? _source;
  StreamSubscription<PlaybackEvent>? _eventSubscription;

  // --- Streams exposed to the UI -------------------------------------------
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  Stream<bool> get shuffleStream => _player.shuffleModeEnabledStream;
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Duration get position => _player.position;

  Track? get currentTrack {
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= _tracks.length) return null;
    return _tracks[index];
  }

  List<Track> get currentTracks => List<Track>.unmodifiable(_tracks);

  bool get hasQueue => _tracks.isNotEmpty;

  // --- Queue setup ----------------------------------------------------------

  /// Replaces the whole queue with [tracks] and starts at [initialIndex].
  /// Downloaded tracks in the list play offline automatically.
  Future<void> setQueue(
    List<Track> tracks, {
    int initialIndex = 0,
    bool autoPlay = true,
  }) async {
    if (tracks.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, tracks.length - 1);

    final sources = await Future.wait(
      tracks.map((track) async {
        final tag = track.toMediaItem();
        final localPath = track.localPath;
        if (localPath != null && await File(localPath).exists()) {
          return AudioSource.file(localPath, tag: tag);
        }
        final url = await _ytService.getAudioStreamUrl(track.videoId);
        return AudioSource.uri(Uri.parse(url), tag: tag);
      }),
    );

    _tracks = List<Track>.of(tracks);
    _source = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: sources,
    );
    queue.add(_tracks.map((track) => track.toMediaItem()).toList());
    mediaItem.add(_tracks[safeIndex].toMediaItem());

    await _player.setAudioSource(
      _source!,
      initialIndex: safeIndex,
      initialPosition: Duration.zero,
    );
    if (autoPlay) await _player.play();
  }

  /// Plays [track]; when [context] (e.g. a search-result list) is given it
  /// becomes the queue, so Next/Previous walk through that list.
  Future<void> playTrack(Track track, {List<Track>? context}) async {
    final list = context ?? <Track>[track];
    final index = list.indexWhere((item) => item.videoId == track.videoId);
    await setQueue(list, initialIndex: index < 0 ? 0 : index);
  }

  /// Appends [track] to the current queue without interrupting playback,
  /// or starts playback immediately when nothing is queued yet.
  Future<void> addToQueue(Track track) async {
    if (_source == null || _tracks.isEmpty) {
      await setQueue(<Track>[track]);
      return;
    }
    final localPath = track.localPath;
    final AudioSource source;
    if (localPath != null && await File(localPath).exists()) {
      source = AudioSource.file(localPath, tag: track.toMediaItem());
    } else {
      final url = await _ytService.getAudioStreamUrl(track.videoId);
      source = AudioSource.uri(Uri.parse(url), tag: track.toMediaItem());
    }
    await _source!.add(source);
    _tracks = <Track>[..._tracks, track];
    queue.add(_tracks.map((item) => item.toMediaItem()).toList());
  }

  /// Removes the queue item at [index] (Queue tab / audio_service queue).
  @override
  Future<void> removeQueueItemAt(int index) async {
    if (_source == null || index < 0 || index >= _tracks.length) return;
    await _source!.removeAt(index);
    _tracks = <Track>[..._tracks]..removeAt(index);
    queue.add(_tracks.map((item) => item.toMediaItem()).toList());
    if (_tracks.isEmpty) {
      await _player.stop();
      mediaItem.add(null);
    }
  }

  /// Moves a queue item (ReorderableListView in the Queue tab).
  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    if (_source == null) return;
    if (oldIndex < 0 || oldIndex >= _tracks.length) return;
    final target = newIndex.clamp(0, _tracks.length - 1);
    if (oldIndex == target) return;
    await _source!.move(oldIndex, target);
    final moved = _tracks.removeAt(oldIndex);
    _tracks.insert(target, moved);
    queue.add(_tracks.map((item) => item.toMediaItem()).toList());
  }

  // --- Transport (called by UI, notification and lock screen) --------------

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    // Convention: more than 3 seconds into a song, Previous restarts it.
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.one => LoopMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group =>
        LoopMode.all,
      AudioServiceRepeatMode.none => LoopMode.off,
    };
    await _player.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  /// Cycles Off → All → One → Off (used by the player screen button).
  Future<void> cycleRepeatMode() async {
    final next = switch (_player.loopMode) {
      LoopMode.off => AudioServiceRepeatMode.all,
      LoopMode.all => AudioServiceRepeatMode.one,
      LoopMode.one => AudioServiceRepeatMode.none,
    };
    await setRepeatMode(next);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    if (enabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(
      playbackState.value.copyWith(shuffleMode: shuffleMode),
    );
  }

  Future<void> toggleShuffle() async {
    await setShuffleMode(
      _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.none
          : AudioServiceShuffleMode.all,
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    if (!_player.playing) {
      await stop();
      await _disposePlayer();
    }
    await super.onTaskRemoved();
  }

  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _disposePlayer();
  }

  Future<void> _disposePlayer() async {
    try {
      await _player.dispose();
    } catch (_) {
      // Player was already disposed (e.g. task removed twice).
    }
  }

  // --- audio_service state synchronisation ---------------------------------

  void _listenToPlayerEvents() {
    _eventSubscription = _player.playbackEventStream.listen(
      (_) => _broadcastState(),
      onError: (Object error, StackTrace stackTrace) {
        // A stream URL can expire mid-queue: drop it from the cache so the
        // next attempt resolves a fresh one, and surface a stopped state.
        final track = currentTrack;
        if (track != null) _ytService.invalidateUrl(track.videoId);
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
        ));
      },
    );
    _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _tracks.length) {
        mediaItem.add(_tracks[index].toMediaItem());
      }
      _broadcastState();
    });
    _player.durationStream.listen((duration) {
      final current = mediaItem.value;
      if (current != null && duration != null) {
        mediaItem.add(current.copyWith(duration: duration));
      }
    });
  }

  void _broadcastState() {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: <MediaControl>[
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const <MediaAction>{
        MediaAction.seek,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.skipToQueueItem,
      },
      androidCompactActionIndices: const <int>[0, 1, 2],
      processingState: _mapProcessingState(_player.processingState),
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
      repeatMode: switch (_player.loopMode) {
        LoopMode.one => AudioServiceRepeatMode.one,
        LoopMode.all => AudioServiceRepeatMode.all,
        LoopMode.off => AudioServiceRepeatMode.none,
      },
      shuffleMode: _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    return switch (state) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };
  }
}
