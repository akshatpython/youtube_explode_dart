import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/download_service.dart';
import '../services/yt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';
import 'player_screen.dart';

/// Root shell: Discover / Downloads / Queue tabs, with the mini-player
/// docked above the bottom navigation bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.ytService,
    required this.audioHandler,
    required this.downloadService,
  });

  final YtService ytService;
  final MusicAudioHandler audioHandler;
  final DownloadService downloadService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  _DiscoverTab(
                    ytService: widget.ytService,
                    audioHandler: widget.audioHandler,
                    downloadService: widget.downloadService,
                  ),
                  _DownloadsTab(
                    audioHandler: widget.audioHandler,
                    downloadService: widget.downloadService,
                  ),
                  _QueueTab(
                    audioHandler: widget.audioHandler,
                    downloadService: widget.downloadService,
                  ),
                ],
              ),
            ),
            MiniPlayer(
              audioHandler: widget.audioHandler,
              downloadService: widget.downloadService,
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore_rounded),
            label: 'Discover',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.download_outlined),
            activeIcon: Icon(Icons.download_rounded),
            label: 'Downloads',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.queue_music_outlined),
            activeIcon: Icon(Icons.queue_music_rounded),
            label: 'Queue',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Discover / Search tab
// ---------------------------------------------------------------------------

class _DiscoverTab extends StatefulWidget {
  const _DiscoverTab({
    required this.ytService,
    required this.audioHandler,
    required this.downloadService,
  });

  final YtService ytService;
  final MusicAudioHandler audioHandler;
  final DownloadService downloadService;

  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab> {
  static const List<String> _quickSearches = <String>[
    'Top hits',
    'Lo-fi beats',
    'Rock classics',
    'Pop hits',
    'Jazz essentials',
    'Workout music',
    'Acoustic covers',
    'Electronic dance',
  ];
  static const String _initialQuery = 'Trending music hits';

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<Track> _results = const <Track>[];
  bool _isLoading = false;
  String? _error;
  String _activeChip = '';
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _runSearch(_initialQuery);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _runSearch(value.trim().isEmpty ? _initialQuery : value);
    });
  }

  Future<void> _runSearch(String query) async {
    final token = ++_searchToken;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await widget.ytService.searchSongs(query);
      if (!mounted || token != _searchToken) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } on YtServiceException catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _error = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _error = 'Search failed. Check your connection and try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _play(Track track) async {
    // Downloaded copies play offline even when they came from search.
    final queue = _results
        .map(widget.downloadService.resolveOfflineCopy)
        .toList(growable: false);
    final effective = widget.downloadService.resolveOfflineCopy(track);
    try {
      await widget.audioHandler.playTrack(effective, context: queue);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not play this track. It may be unavailable.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Text(
            'Wave Music',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            onSubmitted: (value) =>
                _runSearch(value.trim().isEmpty ? _initialQuery : value),
            decoration: InputDecoration(
              hintText: 'Search songs, artists...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _activeChip = '');
                        _runSearch(_initialQuery);
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _quickSearches.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final chip = _quickSearches[index];
              final selected = _activeChip == chip;
              return ChoiceChip(
                label: Text(chip),
                selected: selected,
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: selected ? Colors.black : AppTheme.textPrimary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                onSelected: (_) {
                  setState(() => _activeChip = chip);
                  _searchController.text = chip;
                  _runSearch(chip);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    if (_isLoading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _results.isEmpty) {
      return _EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load songs',
        message: _error!,
        actionLabel: 'Retry',
        onAction: () => _runSearch(
          _searchController.text.trim().isEmpty
              ? _initialQuery
              : _searchController.text,
        ),
      );
    }
    if (_results.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No songs found',
        message: 'Try a different song, artist or genre.',
      );
    }
    return StreamBuilder<MediaItem?>(
      stream: widget.audioHandler.mediaItem,
      initialData: widget.audioHandler.mediaItem.value,
      builder: (context, mediaSnapshot) {
        return StreamBuilder<bool>(
          stream: widget.audioHandler.playingStream,
          initialData: false,
          builder: (context, playingSnapshot) {
            final currentId = mediaSnapshot.data?.id;
            final playing = playingSnapshot.data ?? false;
            return RefreshIndicator(
              color: AppTheme.accent,
              onRefresh: () => _runSearch(
                _searchController.text.trim().isEmpty
                    ? _initialQuery
                    : _searchController.text,
              ),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final track = _results[index];
                  return SongTile(
                    track: track,
                    downloadService: widget.downloadService,
                    isCurrent: track.videoId == currentId,
                    isPlaying: playing && track.videoId == currentId,
                    onTap: () => _play(track),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Downloads (offline library) tab
// ---------------------------------------------------------------------------

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab({
    required this.audioHandler,
    required this.downloadService,
  });

  final MusicAudioHandler audioHandler;
  final DownloadService downloadService;

  Future<void> _confirmDelete(BuildContext context, Track track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete download?'),
        content: Text(
          '"${track.title}" will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await downloadService.deleteDownload(track.videoId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Text(
            'Downloads',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Saved on this device. Plays with no internet connection.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ValueListenableBuilder<List<Track>>(
            valueListenable: downloadService.downloads,
            builder: (context, downloads, _) {
              if (downloads.isEmpty) {
                return const _EmptyState(
                  icon: Icons.download_for_offline_outlined,
                  title: 'No downloads yet',
                  message:
                      'Tap the download icon on any song and it will '
                      'appear here for offline playback.',
                );
              }
              return StreamBuilder<MediaItem?>(
                stream: audioHandler.mediaItem,
                initialData: audioHandler.mediaItem.value,
                builder: (context, mediaSnapshot) {
                  return StreamBuilder<bool>(
                    stream: audioHandler.playingStream,
                    initialData: false,
                    builder: (context, playingSnapshot) {
                      final currentId = mediaSnapshot.data?.id;
                      final playing = playingSnapshot.data ?? false;
                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: downloads.length,
                        itemBuilder: (context, index) {
                          final track = downloads[index];
                          return SongTile(
                            track: track,
                            downloadService: downloadService,
                            showDownloadButton: false,
                            isCurrent: track.videoId == currentId,
                            isPlaying:
                                playing && track.videoId == currentId,
                            subtitleOverride:
                                '${track.artist}  •  Offline  •  '
                                '${track.formattedDuration}',
                            onTap: () => audioHandler.playTrack(
                              track,
                              context: downloads,
                            ),
                            trailing: IconButton(
                              tooltip: 'Delete download',
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () =>
                                  _confirmDelete(context, track),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Queue tab
// ---------------------------------------------------------------------------

class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.audioHandler,
    required this.downloadService,
  });

  final MusicAudioHandler audioHandler;
  final DownloadService downloadService;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Queue',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Open player',
                icon: const Icon(Icons.open_in_full_rounded),
                onPressed: () {
                  if (audioHandler.mediaItem.value == null) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerScreen(
                        audioHandler: audioHandler,
                        downloadService: downloadService,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Drag to reorder. Tap a song to jump to it.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<List<MediaItem>>(
            stream: audioHandler.queue,
            initialData: audioHandler.queue.value,
            builder: (context, queueSnapshot) {
              final queueItems = queueSnapshot.data ?? const <MediaItem>[];
              if (queueItems.isEmpty) {
                return const _EmptyState(
                  icon: Icons.queue_music_rounded,
                  title: 'Queue is empty',
                  message: 'Play a song and your upcoming tracks '
                      'will be listed here.',
                );
              }
              return StreamBuilder<MediaItem?>(
                stream: audioHandler.mediaItem,
                initialData: audioHandler.mediaItem.value,
                builder: (context, mediaSnapshot) {
                  final currentId = mediaSnapshot.data?.id;
                  return ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: queueItems.length,
                    onReorder: (oldIndex, newIndex) {
                      // ReorderableListView reports newIndex after removal.
                      final target =
                          newIndex > oldIndex ? newIndex - 1 : newIndex;
                      audioHandler.moveQueueItem(oldIndex, target);
                    },
                    itemBuilder: (context, index) {
                      final item = queueItems[index];
                      final track = Track.fromMediaItem(item);
                      final isCurrent = item.id == currentId;
                      return ListTile(
                        key: ValueKey<String>(
                          '${item.id}-$index',
                        ),
                        onTap: () => audioHandler.skipToQueueItem(index),
                        leading: ArtworkImage(
                          url: track.thumbnailUrl,
                          size: 48,
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent
                                ? AppTheme.accent
                                : AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          isCurrent
                              ? 'Now playing  •  ${track.artist}'
                              : track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Remove from queue',
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppTheme.textSecondary,
                                size: 20,
                              ),
                              onPressed: () =>
                                  audioHandler.removeQueueItemAt(index),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(
                                Icons.drag_handle_rounded,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

}

// ---------------------------------------------------------------------------
// Shared empty-state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.black,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
