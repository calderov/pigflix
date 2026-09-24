import 'package:flutter/material.dart';

import '../models/movie_info.dart';
import '../services/remote_ws_service.dart';
import '../utils/haptics.dart';
import '../widgets/dpad.dart';
import '../widgets/movie_detail_info.dart';
import '../widgets/pigflix_logo.dart';
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
    // Pre-filled with whatever's currently applied — a search started from
    // the companion app (or typed directly on Pigflix) stays active when
    // navigating back to the grid from a movie's detail screen, so without
    // this the sheet would look empty with no obvious way to tell there's
    // still a filter on, let alone clear it.
    final controller = TextEditingController(
      text: RemoteWsService.instance.searchQuery.value,
    );
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      tapHaptic();
                      controller.clear();
                      RemoteWsService.instance.clearSearchQuery();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      tapHaptic();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openSubtitlesSheet(BuildContext context, MovieInfo info) {
    void select(String? lang) {
      tapHaptic();
      RemoteWsService.instance.sendCommand(
        'select_subtitle',
        lang: lang ?? '__off__',
      );
      Navigator.of(context).pop();
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Off'),
              trailing:
                  info.activeSubtitleLang == null ||
                      info.activeSubtitleLang == '__off__'
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => select(null),
            ),
            for (final option in info.subtitles)
              ListTile(
                title: Text(option.label),
                trailing: info.activeSubtitleLang == option.lang
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => select(option.lang),
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
        onPressed: () {
          tapHaptic();
          _sendCommand('back');
        },
        icon: const Icon(Icons.arrow_back),
        label: const Text('Back'),
      ),
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

  /// Top-left Pigflix wordmark, shown only on the grid (d-pad) layout — the
  /// detail/player screens are already dominated by the movie's backdrop
  /// art, and adding it there would just compete with that.
  Widget _gridLogo() {
    return ValueListenableBuilder<String?>(
      valueListenable: RemoteWsService.instance.currentScreen,
      builder: (context, screen, _) {
        if (screen != 'grid') return const SizedBox.shrink();
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Align(alignment: Alignment.topLeft, child: PigflixLogo()),
          ),
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
          _gridLogo(),
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
                                    const SizedBox(height: 100),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ValueListenableBuilder<String>(
                                        valueListenable: RemoteWsService
                                            .instance
                                            .searchQuery,
                                        builder: (context, query, _) =>
                                            OutlinedButton.icon(
                                              onPressed: () {
                                                tapHaptic();
                                                _openSearchSheet(context);
                                              },
                                              icon: const Icon(Icons.search),
                                              label: Text(
                                                query.isEmpty
                                                    ? 'Search'
                                                    : 'Search: $query',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
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
                                        onPressed: () {
                                          tapHaptic();
                                          _sendCommand('select');
                                        },
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    MovieDetailInfo(
                                      showGenres: false,
                                      showOverview: false,
                                      trailing:
                                          ValueListenableBuilder<MovieInfo?>(
                                            valueListenable: RemoteWsService
                                                .instance
                                                .movieInfo,
                                            builder: (context, info, _) {
                                              final hasSubtitles =
                                                  info?.subtitles.isNotEmpty ??
                                                  false;
                                              return Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  PlaybackControls(
                                                    onCommand: _sendCommand,
                                                  ),
                                                  if (hasSubtitles) ...[
                                                    const SizedBox(height: 16),
                                                    SizedBox(
                                                      width: double.infinity,
                                                      child: OutlinedButton.icon(
                                                        onPressed: () {
                                                          tapHaptic();
                                                          _openSubtitlesSheet(
                                                            context,
                                                            info!,
                                                          );
                                                        },
                                                        icon: const Icon(
                                                          Icons.subtitles,
                                                        ),
                                                        label: const Text(
                                                          'Subtitles',
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              );
                                            },
                                          ),
                                    ),
                                    const SizedBox(height: 20),
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
