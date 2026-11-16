import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/download_service.dart';
import '../theme/app_theme.dart';
import '../widgets/song_tile.dart';

/// Full-screen Now Playing: blurred artwork backdrop, large album art,
/// seek slider, transport, Shuffle/Repeat and offline download.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.audioHandler,
    required this.downloadService,
  });

  final MusicAudioHandler audioHandler;
  final DownloadService downloadService;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double? _draggedPositionMs;

  String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<MediaItem?>(
        stream: widget.audioHandler.mediaItem,
        initialData: widget.audioHandler.mediaItem.value,
        builder: (context, mediaSnapshot) {
          final mediaItem = mediaSnapshot.data;
          if (mediaItem == null) {
            return const Center(child: Text('Nothing is playing.'));
          }
          final track = Track.fromMediaItem(mediaItem);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Blurred, darkened artwork backdrop.
              if (track.thumbnailUrl.isNotEmpty)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                  child: Image.network(
                    track.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(color: AppTheme.background),
                  ),
                ),
              Container(color: Colors.black.withValues(alpha: 0.62)),
              SafeArea(
                child: Column(
                  children: [
                    _buildTopBar(context),
                    const SizedBox(height: 12),
                    _buildArtwork(track),
                    const SizedBox(height: 28),
                    _buildTitle(track),
                    const SizedBox(height: 8),
                    _buildSeekBar(mediaItem, track),
                    _buildTransport(),
                    _buildModeControls(track),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'NOW PLAYING',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildArtwork(Track track) {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: StreamBuilder<bool>(
            stream: widget.audioHandler.playingStream,
            initialData: false,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return AnimatedScale(
                scale: playing ? 1.0 : 0.94,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.28),
                        blurRadius: 48,
                        spreadRadius: 2,
                        offset: const Offset(0, 18),
                      ),
                      const BoxShadow(
                        color: Colors.black54,
                        blurRadius: 32,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: ArtworkImage(
                    url: track.thumbnailUrl,
                    size: 340,
                    borderRadius: 28,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(Track track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar(MediaItem mediaItem, Track track) {
    return StreamBuilder<Duration>(
      stream: widget.audioHandler.positionStream,
      initialData: widget.audioHandler.position,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration?>(
          stream: widget.audioHandler.durationStream,
          builder: (context, durationSnapshot) {
            final total = durationSnapshot.data ??
                mediaItem.duration ??
                track.duration;
            final totalMs = total.inMilliseconds.toDouble();
            final position =
                positionSnapshot.data ?? Duration.zero;
            final currentMs = _draggedPositionMs ??
                position.inMilliseconds
                    .toDouble()
                    .clamp(0.0, totalMs > 0 ? totalMs : 0.0);

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Slider(
                    value: totalMs > 0 ? currentMs : 0,
                    min: 0,
                    max: totalMs > 0 ? totalMs : 1,
                    onChanged: totalMs > 0
                        ? (value) =>
                            setState(() => _draggedPositionMs = value)
                        : null,
                    onChangeEnd: totalMs > 0
                        ? (value) async {
                            await widget.audioHandler.seek(
                              Duration(milliseconds: value.round()),
                            );
                            if (mounted) {
                              setState(() => _draggedPositionMs = null);
                            }
                          }
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _format(
                            Duration(milliseconds: currentMs.round()),
                          ),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _format(total),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTransport() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Previous',
            icon: const Icon(Icons.skip_previous_rounded, size: 40),
            onPressed: widget.audioHandler.skipToPrevious,
          ),
          StreamBuilder<PlayerState>(
            stream: widget.audioHandler.playerStateStream,
            builder: (context, snapshot) {
              final playerState = snapshot.data;
              final playing = playerState?.playing ?? false;
              final processing = playerState?.processingState;
              if (processing == ProcessingState.loading ||
                  processing == ProcessingState.buffering) {
                return const SizedBox(
                  width: 76,
                  height: 76,
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      color: AppTheme.accent,
                      strokeWidth: 3,
                    ),
                  ),
                );
              }
              return IconButton(
                tooltip: playing ? 'Pause' : 'Play',
                icon: Icon(
                  playing
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 76,
                  color: AppTheme.accent,
                ),
                onPressed: () =>
                    playing ? widget.audioHandler.pause() : widget.audioHandler.play(),
              );
            },
          ),
          IconButton(
            tooltip: 'Next',
            icon: const Icon(Icons.skip_next_rounded, size: 40),
            onPressed: widget.audioHandler.skipToNext,
          ),
        ],
      ),
    );
  }

  Widget _buildModeControls(Track track) {
    // Prefer the downloaded copy so the button state matches the file on disk.
    final effectiveTrack = widget.downloadService.resolveOfflineCopy(track);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          StreamBuilder<bool>(
            stream: widget.audioHandler.shuffleStream,
            initialData: false,
            builder: (context, snapshot) {
              final enabled = snapshot.data ?? false;
              return IconButton(
                tooltip: 'Shuffle',
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: enabled ? AppTheme.accent : AppTheme.textSecondary,
                ),
                onPressed: widget.audioHandler.toggleShuffle,
              );
            },
          ),
          StreamBuilder<LoopMode>(
            stream: widget.audioHandler.loopModeStream,
            initialData: LoopMode.off,
            builder: (context, snapshot) {
              final mode = snapshot.data ?? LoopMode.off;
              return IconButton(
                tooltip: 'Repeat',
                icon: Icon(
                  mode == LoopMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  color: mode == LoopMode.off
                      ? AppTheme.textSecondary
                      : AppTheme.accent,
                ),
                onPressed: widget.audioHandler.cycleRepeatMode,
              );
            },
          ),
          DownloadButton(
            track: effectiveTrack,
            downloadService: widget.downloadService,
            iconSize: 24,
          ),
        ],
      ),
    );
  }
}
