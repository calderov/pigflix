import 'dart:async';
import 'dart:html' as html;

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/movie.dart';
import '../services/api_service.dart';
import '../services/srt_parser.dart';

class PlayerScreen extends StatefulWidget {
  final Movie movie;

  const PlayerScreen({super.key, required this.movie});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final ApiService _api = ApiService();
  Timer? _statusPoll;
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  String? _error;
  String _transcodeStatus = 'not_started';
  double _transcodeProgress = 0;
  SubtitleTrack? _activeSubtitleTrack;
  List<Subtitle>? _cues;

  bool _showBackButton = true;
  Timer? _hideBackButtonTimer;
  final FocusNode _playerFocusNode = FocusNode(debugLabel: 'video player');

  @override
  void initState() {
    super.initState();
    _requestBrowserFullscreen();
    _pollUntilReady();
    _resetBackButtonTimer();
  }

  void _onMouseActivity([PointerEvent? _]) {
    if (!_showBackButton) setState(() => _showBackButton = true);
    _resetBackButtonTimer();
  }

  void _resetBackButtonTimer() {
    _hideBackButtonTimer?.cancel();
    _hideBackButtonTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showBackButton = false);
    });
  }

  void _goBack() {
    _videoController?.pause();
    Navigator.of(context).pop();
  }

  void _requestBrowserFullscreen() {
    try {
      html.document.documentElement?.requestFullscreen();
    } catch (_) {
      // Fullscreen requires a user gesture in some browsers; ignore if denied.
    }
  }

  void _toggleFullscreen() {
    try {
      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
      } else {
        html.document.documentElement?.requestFullscreen();
      }
    } catch (_) {
      // Fullscreen requires a user gesture in some browsers; ignore if denied.
    }
  }

  void _pollUntilReady() {
    _checkStatus(); // fire immediately, then on an interval
    _statusPoll = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkStatus(),
    );
  }

  Future<void> _checkStatus() async {
    try {
      final movie = await _api.fetchMovieStatus(widget.movie.id);
      if (!mounted) return;

      if (movie.transcodeStatus == 'error') {
        _statusPoll?.cancel();
        setState(
          () => _error =
              'The backend failed to prepare this video for streaming.',
        );
        return;
      }

      setState(() {
        _transcodeStatus = movie.transcodeStatus;
        _transcodeProgress = movie.transcodeProgress;
      });

      if (movie.transcodeStatus == 'done') {
        _statusPoll?.cancel();
        _initPlayer();
      }
    } catch (e) {
      // Transient network hiccups shouldn't kill the poll loop; keep trying.
    }
  }

  Future<void> _initPlayer() async {
    final url = Uri.parse(widget.movie.streamUrl);
    final controller = VideoPlayerController.networkUrl(url);
    _videoController = controller;
    try {
      await controller.initialize();
      if (!mounted) return;

      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: controller,
          autoPlay: true,
          looping: false,
          // We already request true browser-level fullscreen ourselves (see
          // _requestBrowserFullscreen). Chewie's own fullScreenByDefault would
          // push a second, separate fullscreen route on top of this screen,
          // which swallows mouse-hover events before our back-button overlay
          // ever sees them.
          allowFullScreen: false,
          deviceOrientationsAfterFullScreen: const [],
          materialProgressColors: ChewieProgressColors(
            playedColor: Colors.redAccent,
            handleColor: Colors.redAccent,
          ),
          // Subtitles are rendered by our own overlay (_SubtitleOverlay)
          // instead of Chewie's built-in one: Chewie only re-reads
          // showSubtitles when the *controller instance* changes, which
          // would mean rebuilding ChewieController every time the viewer
          // picks a track — and doing that mid-playback turned out to reset
          // the underlying <video> element's position on web. Owning the
          // overlay ourselves means turning captions on/off is just a
          // setState away, with no effect on playback.
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load video: $e');
    }
  }

  Future<void> _selectSubtitleTrack(SubtitleTrack? track) async {
    if (track == null) {
      setState(() {
        _cues = null;
        _activeSubtitleTrack = null;
      });
      return;
    }

    try {
      final srt = await _api.fetchSubtitle(track.url);
      final cues = parseSrt(srt);
      if (!mounted) return;
      setState(() {
        _cues = cues;
        _activeSubtitleTrack = track;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load subtitles: $e')));
    }
  }

  @override
  void dispose() {
    _statusPoll?.cancel();
    _hideBackButtonTimer?.cancel();
    try {
      if (html.document.fullscreenElement != null) {
        html.document.exitFullscreen();
      }
    } catch (_) {}
    _chewieController?.dispose();
    _videoController?.dispose();
    _playerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.backspace): _goBack,
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: _onMouseActivity,
          cursor: _showBackButton
              ? SystemMouseCursors.basic
              : SystemMouseCursors.none,
          // MouseRegion.onHover never fires on touch devices, so without this
          // the back button and subtitle picker — once auto-hidden — would be
          // permanently unreachable on a phone/tablet. `translucent` lets the
          // tap still reach Chewie's own controls underneath for its own
          // play/pause and show/hide handling.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _onMouseActivity(),
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: Focus(
                      focusNode: _playerFocusNode,
                      autofocus: true,
                      child: _error != null
                          ? _buildError(_error!)
                          : _chewieController == null
                          ? _buildPreparing()
                          : Chewie(controller: _chewieController!),
                    ),
                  ),
                  if (_error == null &&
                      _cues != null &&
                      _videoController != null)
                    _SubtitleOverlay(
                      videoController: _videoController!,
                      cues: _cues!,
                    ),
                  if (_error == null)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: AnimatedOpacity(
                        opacity: _showBackButton ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: !_showBackButton,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _BackButton(onPressed: _goBack),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  widget.movie.year != null
                                      ? '${widget.movie.title} (${widget.movie.year})'
                                      : widget.movie.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_error == null &&
                      _chewieController != null &&
                      widget.movie.subtitles.isNotEmpty)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: AnimatedOpacity(
                        opacity: _showBackButton ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: !_showBackButton,
                          child: _SubtitleTrackButton(
                            tracks: widget.movie.subtitles,
                            active: _activeSubtitleTrack,
                            onSelect: _selectSubtitleTrack,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreparing() {
    final isRemuxOrEncoding = _transcodeStatus == 'processing';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            color: Colors.redAccent,
            value: isRemuxOrEncoding && _transcodeProgress > 0
                ? _transcodeProgress / 100
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isRemuxOrEncoding
              ? 'Preparing video… ${_transcodeProgress.toStringAsFixed(0)}%'
              : 'Preparing video…',
          style: const TextStyle(color: Colors.white70),
        ),
        if (isRemuxOrEncoding) ...[
          const SizedBox(height: 4),
          const Text(
            'First playback of a movie can take a while.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildError(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.white70, size: 48),
        const SizedBox(height: 12),
        Text(message, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Go back'),
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        tooltip: 'Back',
        onPressed: onPressed,
      ),
    );
  }
}

/// Lets the user pick which subtitle language is shown (or turn them off).
/// This is the sole on/off control — captions are rendered by our own
/// _SubtitleOverlay, not Chewie's built-in one, so picking a track here
/// turns them on immediately with no extra toggle to press.
class _SubtitleTrackButton extends StatelessWidget {
  final List<SubtitleTrack> tracks;
  final SubtitleTrack? active;
  final ValueChanged<SubtitleTrack?> onSelect;

  const _SubtitleTrackButton({
    required this.tracks,
    required this.active,
    required this.onSelect,
  });

  // PopupMenuButton treats a tapped item whose value is null the same as the
  // menu being dismissed without a selection (onSelected never fires) — so
  // "Off" needs a real, non-null sentinel rather than null itself.
  static final SubtitleTrack _offSentinel = SubtitleTrack(
    lang: '__off__',
    url: '',
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: PopupMenuButton<SubtitleTrack>(
        tooltip: 'Subtitles',
        icon: const Icon(Icons.subtitles, color: Colors.white),
        onSelected: (track) =>
            onSelect(identical(track, _offSentinel) ? null : track),
        itemBuilder: (context) => [
          CheckedPopupMenuItem<SubtitleTrack>(
            value: _offSentinel,
            checked: active == null,
            child: const Text('Off'),
          ),
          for (final track in tracks)
            CheckedPopupMenuItem<SubtitleTrack>(
              value: track,
              checked: active == track,
              child: Text(_languageLabel(track.lang)),
            ),
        ],
      ),
    );
  }
}

/// Best-effort display name for a subtitle filename's language suffix (e.g.
/// "en"/"eng" -> English). Falls back to the raw code for anything unknown
/// rather than guessing.
String _languageLabel(String? code) {
  if (code == null) return 'Default';
  const names = {
    'en': 'English',
    'eng': 'English',
    'es': 'Spanish',
    'spa': 'Spanish',
    'fr': 'French',
    'fre': 'French',
    'fra': 'French',
    'de': 'German',
    'ger': 'German',
    'deu': 'German',
    'it': 'Italian',
    'ita': 'Italian',
    'pt': 'Portuguese',
    'por': 'Portuguese',
  };
  return names[code.toLowerCase()] ?? code.toUpperCase();
}

/// Renders the current subtitle cue for [videoController]'s playback
/// position, re-evaluated on every position update. Positioned above
/// Chewie's (auto-hiding) control bar regardless of the video's own
/// letterboxing.
class _SubtitleOverlay extends StatelessWidget {
  final VideoPlayerController videoController;
  final List<Subtitle> cues;

  const _SubtitleOverlay({required this.videoController, required this.cues});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 100,
      child: IgnorePointer(
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: videoController,
          builder: (context, value, _) {
            final matches = Subtitles(cues).getByPosition(value.position);
            if (matches.isEmpty) return const SizedBox.shrink();
            return Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x96000000),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text.rich(
                  parseSubtitleMarkup(
                    '${matches.first!.text}',
                    style: const TextStyle(color: Colors.white, fontSize: 48),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
