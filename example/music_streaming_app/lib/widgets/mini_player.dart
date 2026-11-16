import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/track.dart';
import '../screens/player_screen.dart';
import '../services/audio_handler.dart';
import '../services/download_service.dart';
import '../theme/app_theme.dart';
import 'song_tile.dart';

/// Horizontally scrolling single-line text (marquee) for long titles.
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _controller = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _timer?.cancel();
      if (_controller.hasClients) _controller.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
    }
  }

  void _startScrolling() {
    if (!mounted || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    if (max <= 0) return;
    var scrollingForward = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || !_controller.hasClients) return;
      final target = scrollingForward ? max : 0.0;
      scrollingForward = !scrollingForward;
      await _controller.animateTo(
        target,
        duration: Duration(milliseconds: (max * 18).round().clamp(800, 12000)),
        curve: Curves.linear,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        style: widget.style,
      ),
    );
  }
}

/// Persistent mini-player docked directly above the bottom navigation bar.
/// Hidden until a song is loaded; tapping it opens the full player.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({
    super.key,
    required this.audioHandler,
    required this.downloadService,
  });

  final MusicAudioHandler audioHandler;
  final DownloadService downloadService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      initialData: audioHandler.mediaItem.value,
      builder: (context, mediaSnapshot) {
        final mediaItem = mediaSnapshot.data;
        if (mediaItem == null) return const SizedBox.shrink();
        final track = Track.fromMediaItem(mediaItem);

        return StreamBuilder<Duration>(
          stream: audioHandler.positionStream,
          initialData: audioHandler.position,
          builder: (context, positionSnapshot) {
            final total = mediaItem.duration ?? track.duration;
            final position = positionSnapshot.data ?? Duration.zero;
            final progress = total.inMilliseconds > 0
                ? (position.inMilliseconds / total.inMilliseconds)
                    .clamp(0.0, 1.0)
                : 0.0;

            return Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlayerScreen(
                          audioHandler: audioHandler,
                          downloadService: downloadService,
                        ),
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                        child: Row(
                          children: [
                            ArtworkImage(
                              url: track.thumbnailUrl,
                              size: 46,
                              borderRadius: 10,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  MarqueeText(
                                    text: track.title,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Previous',
                              icon: const Icon(Icons.skip_previous_rounded),
                              onPressed: audioHandler.skipToPrevious,
                            ),
                            StreamBuilder<bool>(
                              stream: audioHandler.playingStream,
                              initialData: false,
                              builder: (context, playingSnapshot) {
                                final playing = playingSnapshot.data ?? false;
                                return IconButton(
                                  tooltip: playing ? 'Pause' : 'Play',
                                  icon: Icon(
                                    playing
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_fill_rounded,
                                    color: AppTheme.accent,
                                    size: 38,
                                  ),
                                  onPressed: () => playing
                                      ? audioHandler.pause()
                                      : audioHandler.play(),
                                );
                              },
                            ),
                            IconButton(
                              tooltip: 'Next',
                              icon: const Icon(Icons.skip_next_rounded),
                              onPressed: audioHandler.skipToNext,
                            ),
                          ],
                        ),
                      ),
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppTheme.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
