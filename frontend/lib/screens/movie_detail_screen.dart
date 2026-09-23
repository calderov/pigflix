import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie.dart';
import '../services/admin_session.dart';
import '../services/api_service.dart';
import '../services/remote_control_service.dart';
import '../services/route_observer.dart';
import '../widgets/poster_placeholder.dart';
import 'player_screen.dart';

class MovieDetailScreen extends StatefulWidget {
  final Movie movie;

  const MovieDetailScreen({super.key, required this.movie});

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> with RouteAware {
  final ApiService _api = ApiService();
  late Movie _movie = widget.movie;
  StreamSubscription<Map<String, dynamic>>? _remoteSub;

  @override
  void initState() {
    super.initState();
    _remoteSub = RemoteControlService.instance.commandStream.listen(
      _handleRemoteCommand,
    );
    _broadcastScreenState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _remoteSub?.cancel();
    super.dispose();
  }

  // Popping back here from the player screen doesn't re-run initState (this
  // is the same, already-existing screen instance), so without this the
  // paired remote would keep showing the player's controls after the user
  // (or a remote "back" command) navigated back to this screen.
  @override
  void didPopNext() => _broadcastScreenState();

  void _broadcastScreenState() {
    RemoteControlService.instance.sendScreenState(
      'detail',
      movieTitle: _movie.title,
    );
  }

  // Play is this screen's sole default action (autofocus by default), so
  // remote "select" always activates it — no need to track which of
  // Back/Play currently holds focus.
  //
  // The `isCurrent` guard matters here: this screen's State stays alive
  // (and its commandStream subscription with it) while the player screen
  // is pushed on top of it, so without the guard a remote "back" sent from
  // the player would also pop *this* screen, skipping straight to the grid
  // instead of stopping on the detail screen.
  void _handleRemoteCommand(Map<String, dynamic> msg) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    if (msg['type'] != 'command') return;
    switch (msg['action']) {
      case 'select':
        _play();
      case 'back':
        Navigator.of(context).maybePop();
    }
  }

  void _play() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PlayerScreen(movie: _movie)));
  }

  String? get _formattedRuntime {
    final runtime = _movie.runtime;
    if (runtime == null || runtime <= 0) return null;
    final hours = runtime ~/ 60;
    final minutes = runtime % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  Future<void> _fixMatch() async {
    final result = await showDialog<Movie>(
      context: context,
      builder: (_) => _RetryMetadataDialog(movie: _movie, api: _api),
    );
    if (result == null || !mounted) return;

    setState(() => _movie = result);

    final message = result.metadataStatus == 'ready'
        ? 'Matched to "${result.title}"${result.year != null ? ' (${result.year})' : ''}.'
        : 'No match found for "${result.title}". Try a different title or year.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: _movie.posterUrl == null
            ? PosterPlaceholder(title: _movie.title)
            : Image.network(
                _movie.posterUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    PosterPlaceholder(title: _movie.title),
              ),
      ),
    );

    final details = ValueListenableBuilder<bool>(
      valueListenable: AdminSession.isAdmin,
      builder: (context, isAdmin, _) => _DetailsColumn(
        movie: _movie,
        formattedRuntime: _formattedRuntime,
        onPlay: _play,
        onFixMatch: _fixMatch,
        showFixMatch: isAdmin,
      ),
    );

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.backspace): () =>
              Navigator.of(context).maybePop(),
        },
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            leading: FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            title: Text(_movie.title),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_movie.backdropUrl != null)
                Image.network(
                  _movie.backdropUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(color: Colors.black),
                )
              else
                Container(color: Colors.black),
              // Dark scrim so the foreground text/controls stay readable over
              // whatever the backdrop image looks like.
              Container(color: Colors.black.withValues(alpha: 0.55)),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 560;
                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(height: 320, child: poster),
                                const SizedBox(height: 24),
                                details,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 260, child: poster),
                              const SizedBox(width: 32),
                              Expanded(child: details),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsColumn extends StatelessWidget {
  final Movie movie;
  final String? formattedRuntime;
  final VoidCallback onPlay;
  final VoidCallback onFixMatch;
  final bool showFixMatch;

  const _DetailsColumn({
    required this.movie,
    required this.formattedRuntime,
    required this.onPlay,
    required this.onFixMatch,
    required this.showFixMatch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(movie.title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (movie.year != null)
              Text('${movie.year}', style: theme.textTheme.titleMedium),
            if (formattedRuntime != null)
              Text(formattedRuntime!, style: theme.textTheme.titleMedium),
            if (movie.rating != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${movie.rating!.toStringAsFixed(1)} / 10',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
          ],
        ),
        if (movie.genres.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: movie.genres
                .map((genre) => Chip(label: Text(genre)))
                .toList(),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          movie.overview?.isNotEmpty == true
              ? movie.overview!
              : 'No overview available.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: SizedBox(
                width: 180,
                child: FilledButton.icon(
                  onPressed: onPlay,
                  autofocus: true,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            // Excluded from keyboard traversal: Tab only cycles back/play by
            // design here. Still reachable by mouse/touch when visible.
            if (showFixMatch)
              ExcludeFocusTraversal(
                child: SizedBox(
                  width: 180,
                  child: OutlinedButton.icon(
                    onPressed: onFixMatch,
                    icon: const Icon(Icons.search),
                    label: const Text('Fix match'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Dialog that lets the user retry the TMDb search with a corrected title
/// and (optional) year, for movies that were never matched or were matched
/// to the wrong film. Performs the search itself and pops with the updated
/// [Movie] on success.
class _RetryMetadataDialog extends StatefulWidget {
  final Movie movie;
  final ApiService api;

  const _RetryMetadataDialog({required this.movie, required this.api});

  @override
  State<_RetryMetadataDialog> createState() => _RetryMetadataDialogState();
}

class _RetryMetadataDialogState extends State<_RetryMetadataDialog> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.movie.title,
  );
  late final TextEditingController _yearController = TextEditingController(
    text: widget.movie.year?.toString() ?? '',
  );
  final _formKey = GlobalKey<FormState>();

  static final RegExp _idPattern = RegExp(
    r'^id:\s*(.*)$',
    caseSensitive: false,
  );

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onTitleChanged);
  }

  void _onTitleChanged() => setState(() {});

  bool get _isIdLookup => _idPattern.hasMatch(_titleController.text.trim());

  @override
  void dispose() {
    _titleController.removeListener(_onTitleChanged);
    _titleController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final yearText = _yearController.text.trim();
    try {
      final updated = await widget.api.retryMetadata(
        widget.movie.id,
        title: _titleController.text.trim(),
        year: yearText.isEmpty ? null : int.parse(yearText),
      );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fix match'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Search TMDb again with the correct title and year (optional) '
                'to fix an unrecognized or mislabeled movie, or enter '
                'id:<tmdb id> to match an exact TMDb movie page.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                enabled: !_submitting,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. The Matrix, or id:603',
                ),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return 'Title is required';
                  final idMatch = _idPattern.firstMatch(trimmed);
                  if (idMatch != null &&
                      int.tryParse(idMatch.group(1)!.trim()) == null) {
                    return 'Invalid TMDb id — expected e.g. "id:603"';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _yearController,
                enabled: !_submitting && !_isIdLookup,
                decoration: InputDecoration(
                  labelText: 'Year (optional)',
                  helperText: _isIdLookup
                      ? 'Ignored when using id:<tmdb id>'
                      : null,
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return null;
                  return int.tryParse(trimmed) == null
                      ? 'Year must be a number'
                      : null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Search'),
        ),
      ],
    );
  }
}
