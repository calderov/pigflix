import 'package:flutter/material.dart';

import '../models/movie_info.dart';
import '../services/remote_ws_service.dart';
import '../widgets/dpad.dart';
import '../widgets/movie_detail_info.dart';
import '../widgets/playback_controls.dart';

/// The remote-control screen shown once paired. Its button layout adapts to
/// whichever screen the web frontend is currently showing, per the
/// `currentScreen` state broadcast over the socket.
class RemoteScreen extends StatelessWidget {
  const RemoteScreen({super.key});

  void _sendCommand(String action, {int? deltaSeconds}) {
    RemoteWsService.instance.sendCommand(action, deltaSeconds: deltaSeconds);
  }

  void _openSearchSheet(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search movies',
                border: OutlineInputBorder(),
              ),
              onChanged: RemoteWsService.instance.sendSearchQuery,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _backButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _sendCommand('back'),
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back'),
      ),
    );
  }

  /// Small poster thumbnail + title/year, shown above the playback controls
  /// so it's clear at a glance what's playing without needing to look at
  /// the TV — a compact version of [MovieDetailInfo] since the detail
  /// screen's full write-up isn't needed once the movie's already playing.
  Widget _nowPlayingHeader() {
    return ValueListenableBuilder<MovieInfo?>(
      valueListenable: RemoteWsService.instance.movieInfo,
      builder: (context, info, _) {
        if (info?.title == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (info!.posterUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 56,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: Image.network(
                        info.posterUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      info.title!,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (info.year != null)
                      Text('${info.year}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Full-bleed backdrop behind the detail/player screens' controls,
  /// matching whatever movie is currently on screen on Pigflix — mirrors
  /// the web frontend's own detail/player screens (image + dark scrim for
  /// legibility). Empty on the grid screen, which has no single movie to
  /// show a backdrop for.
  Widget _movieBackdrop() {
    return ValueListenableBuilder<String?>(
      valueListenable: RemoteWsService.instance.currentScreen,
      builder: (context, screen, _) {
        if (screen != 'detail' && screen != 'player') {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<MovieInfo?>(
          valueListenable: RemoteWsService.instance.movieInfo,
          builder: (context, info, _) {
            final url = info?.backdropUrl;
            if (url == null) return const SizedBox.shrink();
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
                Container(color: Colors.black.withValues(alpha: 0.55)),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _movieBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  // Full detail info (poster + title + overview, etc.) can
                  // be taller than the screen on a phone, so this scrolls
                  // when it overflows — but the shorter grid/player layouts
                  // should still sit centered rather than pinned to the top.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 48,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: ValueListenableBuilder<String?>(
                          valueListenable:
                              RemoteWsService.instance.currentScreen,
                          builder: (context, screen, _) {
                            switch (screen) {
                              case 'grid':
                                // No Back button here: the grid is the root
                                // screen on Pigflix, so there's nowhere for
                                // "back" to go — the display's own command
                                // handler treats it as a no-op.
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    DPad(onCommand: _sendCommand),
                                    const SizedBox(height: 24),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            _openSearchSheet(context),
                                        icon: const Icon(Icons.search),
                                        label: const Text('Search'),
                                      ),
                                    ),
                                  ],
                                );
                              case 'detail':
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const MovieDetailInfo(),
                                    const SizedBox(height: 20),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () => _sendCommand('select'),
                                        icon: const Icon(Icons.play_arrow),
                                        label: const Text('Play'),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _backButton(),
                                  ],
                                );
                              case 'player':
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _nowPlayingHeader(),
                                    PlaybackControls(onCommand: _sendCommand),
                                    const SizedBox(height: 24),
                                    _backButton(),
                                  ],
                                );
                              default:
                                return const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 16),
                                    Text('Connected — waiting for Pigflix…'),
                                  ],
                                );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
