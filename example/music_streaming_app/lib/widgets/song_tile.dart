import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/download_service.dart';
import '../theme/app_theme.dart';

/// Rounded thumbnail with a graceful fallback when an artwork URL is
/// missing or unreachable (offline, or a video without a max-res image).
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    super.key,
    required this.url,
    required this.size,
    this.borderRadius = 10,
  });

  final String url;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? _fallback()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallback(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: AppTheme.surfaceVariant,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      color: AppTheme.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        color: AppTheme.textSecondary,
        size: size * 0.42,
      ),
    );
  }
}

/// Download button with three live states: download icon → circular
/// progress (tap to cancel) → green checkmark (tap managed by parent menu).
class DownloadButton extends StatelessWidget {
  const DownloadButton({
    super.key,
    required this.track,
    required this.downloadService,
    this.iconSize = 22,
  });

  final Track track;
  final DownloadService downloadService;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, double>>(
      valueListenable: downloadService.progress,
      builder: (context, progressMap, _) {
        final value = progressMap[track.videoId];
        if (value != null) {
          return IconButton(
            tooltip: 'Cancel download',
            onPressed: () => downloadService.cancelDownload(track.videoId),
            icon: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: value < 0 ? null : value,
                strokeWidth: 2.4,
                color: AppTheme.accent,
                backgroundColor: Colors.white12,
              ),
            ),
          );
        }
        return ValueListenableBuilder<List<Track>>(
          valueListenable: downloadService.downloads,
          builder: (context, downloads, _) {
            final downloaded =
                downloads.any((item) => item.videoId == track.videoId);
            if (downloaded) {
              return Icon(
                Icons.check_circle_rounded,
                color: AppTheme.accent,
                size: iconSize + 2,
              );
            }
            return IconButton(
              tooltip: 'Download for offline playback',
              icon: Icon(
                Icons.download_rounded,
                color: AppTheme.textSecondary,
                size: iconSize,
              ),
              onPressed: () async {
                try {
                  await downloadService.download(track);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Saved offline: ${track.title}')),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Download failed. Check your connection and retry.',
                        ),
                      ),
                    );
                  }
                }
              },
            );
          },
        );
      },
    );
  }
}

/// One song row: artwork, title, artist, duration and a download button.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.track,
    required this.onTap,
    required this.downloadService,
    this.isCurrent = false,
    this.isPlaying = false,
    this.trailing,
    this.showDownloadButton = true,
    this.subtitleOverride,
  });

  final Track track;
  final VoidCallback onTap;
  final DownloadService downloadService;
  final bool isCurrent;
  final bool isPlaying;
  final Widget? trailing;
  final bool showDownloadButton;
  final String? subtitleOverride;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        alignment: Alignment.center,
        children: [
          ArtworkImage(url: track.thumbnailUrl, size: 54),
          if (isCurrent)
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isPlaying ? Icons.equalizer_rounded : Icons.pause_rounded,
                color: AppTheme.accent,
                size: 22,
              ),
            ),
        ],
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isCurrent ? AppTheme.accent : AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitleOverride ??
            '${track.artist}  •  ${track.formattedDuration}'
                '${track.isDownloaded ? '  •  Offline' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
      trailing: trailing ??
          (showDownloadButton
              ? DownloadButton(track: track, downloadService: downloadService)
              : null),
    );
  }
}
