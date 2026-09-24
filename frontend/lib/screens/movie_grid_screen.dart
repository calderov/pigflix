import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/movie.dart';
import '../services/admin_session.dart';
import '../services/api_service.dart';
import '../services/remote_control_service.dart';
import '../services/route_observer.dart';
import '../widgets/poster_placeholder.dart';
import 'movie_detail_screen.dart';

// Must match the GridView.builder's own padding/gridDelegate constants below
// — used to independently work out how many columns Flutter will lay the
// grid out with (and each row's pixel height), so arrow-key navigation can
// move by the right amount and scroll a far-off-screen tile into view.
const double _gridPadding = 16;
const double _gridMaxCrossAxisExtent = 220;
const double _gridCrossAxisSpacing = 16;
const double _gridMainAxisSpacing = 16;
const double _gridChildAspectRatio = 0.6;

class MovieGridScreen extends StatefulWidget {
  const MovieGridScreen({super.key});

  @override
  State<MovieGridScreen> createState() => _MovieGridScreenState();
}

class _MovieGridScreenState extends State<MovieGridScreen> with RouteAware {
  final ApiService _api = ApiService();
  late Future<List<Movie>> _moviesFuture;
  List<Movie> _allMovies = [];
  String _query = '';

  final FocusNode _gridFocusNode = FocusNode(debugLabel: 'movie grid');
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'search field');
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _gridScrollController = ScrollController();
  // Guards against the search field's onChanged firing (and re-broadcasting
  // right back out) as a side effect of _searchController.text being set
  // programmatically below — TextField's onChanged fires on any controller
  // value change, not just actual keystrokes.
  bool _syncingSearchFromRemote = false;
  int _focusedTileIndex = 0;
  int _crossAxisCount = 1;
  // Pixel distance from one row's top edge to the next row's top edge
  // (tile height + mainAxisSpacing). Recomputed on every layout alongside
  // _crossAxisCount; used to compute exactly how far to scroll to reveal
  // the focused tile, however far off-screen it is.
  double _rowStride = 0;

  StreamSubscription<Map<String, dynamic>>? _remoteSub;

  @override
  void initState() {
    super.initState();
    _moviesFuture = _load();
    _gridFocusNode.addListener(_onGridFocusChange);
    _remoteSub = RemoteControlService.instance.commandStream.listen(
      _handleRemoteCommand,
    );
    _broadcastScreenState();
  }

  void _broadcastScreenState() {
    RemoteControlService.instance.sendScreenState('grid', searchQuery: _query);
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
    _gridFocusNode.removeListener(_onGridFocusChange);
    _gridFocusNode.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  // Popping back here from the detail screen doesn't re-run initState (this
  // is the same, already-existing screen instance), so without this the
  // paired remote would keep showing the detail screen's controls after the
  // user (or a remote "back" command) navigated back to the grid.
  @override
  void didPopNext() => _broadcastScreenState();

  // Navigator.push keeps this screen's State alive underneath whatever's
  // pushed on top of it, so its commandStream subscription would otherwise
  // keep reacting to remote commands even while the detail/player screen is
  // the one actually visible (e.g. a remote "select" sent from the detail
  // screen would also open whatever tile happens to be grid-focused here).
  void _handleRemoteCommand(Map<String, dynamic> msg) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final movies = _filtered;
    if (msg['type'] == 'search_query') {
      final query = msg['query'] as String? ?? '';
      _syncingSearchFromRemote = true;
      _searchController.text = query;
      _syncingSearchFromRemote = false;
      setState(() => _query = query);
      _broadcastScreenState();
      return;
    }
    if (msg['type'] != 'command' || movies.isEmpty) return;
    switch (msg['action']) {
      case 'move_up':
        _moveFocusVertical(-1, movies.length);
      case 'move_down':
        _moveFocusVertical(1, movies.length);
      case 'move_left':
        _moveFocusHorizontal(-1, movies.length);
      case 'move_right':
        _moveFocusHorizontal(1, movies.length);
      case 'select':
        _openMovie(movies[_clampFocusIndex(_focusedTileIndex, movies.length)]);
    }
  }

  void _onGridFocusChange() => setState(() {});

  Future<List<Movie>> _load() async {
    final movies = await _api.fetchMovies();
    setState(() => _allMovies = movies);
    return movies;
  }

  List<Movie> get _filtered {
    if (_query.isEmpty) return _allMovies;
    final q = _query.toLowerCase();
    return _allMovies.where((m) => m.title.toLowerCase().contains(q)).toList();
  }

  void _openMovie(Movie movie) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movie: movie)));
  }

  /// Mirrors `SliverGridDelegateWithMaxCrossAxisExtent`'s own column-count
  /// and row-height formulas, so arrow-key navigation moves by exactly one
  /// visual row/column, and so a tile that's scrolled off-screen (e.g. by a
  /// mouse-wheel scroll unrelated to keyboard focus) can be found again:
  /// `GridView.builder` only ever builds items near the current scroll
  /// position, so `Scrollable.ensureVisible` can't reveal a tile that was
  /// never built in the first place — we have to scroll there ourselves
  /// first (see `_revealFocusedTile`), which means knowing where "there" is.
  void _updateGridMetrics(double maxWidth) {
    final availableWidth = maxWidth - _gridPadding * 2;
    final columns = math.max(
      1,
      (availableWidth / (_gridMaxCrossAxisExtent + _gridCrossAxisSpacing))
          .ceil(),
    );
    final usableCrossAxisExtent = math.max(
      0.0,
      availableWidth - _gridCrossAxisSpacing * (columns - 1),
    );
    final childCrossAxisExtent = usableCrossAxisExtent / columns;
    final childMainAxisExtent = childCrossAxisExtent / _gridChildAspectRatio;

    _crossAxisCount = columns;
    _rowStride = childMainAxisExtent + _gridMainAxisSpacing;
  }

  int _clampFocusIndex(int index, int length) {
    if (length == 0) return 0;
    return index.clamp(0, length - 1);
  }

  void _setFocusedIndex(int newIndex) {
    setState(() {
      _focusedTileIndex = newIndex;
    });
    _revealFocusedTile(newIndex);
  }

  /// Left/right always move by one tile, clamped to the ends of the list —
  /// there's no notion of a "boundary row" for horizontal movement.
  void _moveFocusHorizontal(int delta, int length) {
    if (length == 0) return;
    final current = _clampFocusIndex(_focusedTileIndex, length);
    _setFocusedIndex(_clampFocusIndex(current + delta, length));
  }

  /// Up/down move by a full row, but — unlike horizontal movement — do
  /// *not* clamp to the nearest edge tile when there's no row in that
  /// direction: pressing Up on the top row (or Down on the bottom row)
  /// leaves the focused tile exactly where it was, rather than jumping
  /// sideways to the first/last tile overall.
  void _moveFocusVertical(int rowDelta, int length) {
    if (length == 0 || _crossAxisCount <= 0) return;

    final current = _clampFocusIndex(_focusedTileIndex, length);
    final currentRow = current ~/ _crossAxisCount;
    final totalRows = (length / _crossAxisCount).ceil();

    if (rowDelta < 0) {
      if (currentRow == 0) return; // already the top row
      _setFocusedIndex(current - _crossAxisCount);
    } else {
      if (currentRow >= totalRows - 1) return; // already the bottom row
      // The bottom row may have fewer tiles than a full row (a "ragged"
      // last row), so moving down a column that doesn't exist there lands
      // on the last tile instead of going out of bounds.
      final newIndex = math.min(current + _crossAxisCount, length - 1);
      _setFocusedIndex(newIndex);
    }
  }

  /// Brings the newly-focused tile into view with a single, minimal,
  /// animated scroll — never more than needed, whether the tile is one row
  /// away or scrolled far off-screen (e.g. by a mouse-wheel scroll, or by
  /// reversing keyboard direction after several moves the other way).
  ///
  /// An earlier version split this into two steps — an estimate-based jump
  /// (or, in a later revision, an estimate-based animation) to get a
  /// far-off-screen tile built, followed by a separate `Scrollable
  /// .ensureVisible` for a "precise" final settle. That meant two
  /// independent position calculations that could disagree by a few pixels,
  /// and *any* disagreement made the second one perform its own extra
  /// correction — visibly landing the tile in one spot and then re-scrolling
  /// it to another. Computing the destination once, ourselves, and doing
  /// one `animateTo` removes the second calculation (and the second
  /// motion) entirely.
  Future<void> _revealFocusedTile(int index) async {
    if (!_gridScrollController.hasClients || _rowStride <= 0) return;

    final position = _gridScrollController.position;
    final tileHeight = _rowStride - _gridMainAxisSpacing;
    final targetTop = _gridPadding + (index ~/ _crossAxisCount) * _rowStride;
    final targetBottom = targetTop + tileHeight;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;

    double? destination;
    if (targetTop < viewTop) {
      // Above the viewport (even partially): align its top edge to the
      // viewport's top.
      destination = targetTop;
    } else if (targetBottom > viewBottom) {
      // Below the viewport (even partially): align its bottom edge to the
      // viewport's bottom.
      destination = targetBottom - position.viewportDimension;
    }
    if (destination == null) return; // already fully visible

    await _gridScrollController.animateTo(
      destination.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  /// Jumps focus to the search field. Only meant to be wired up on focus
  /// nodes *other* than the search field itself, so typing "s" while
  /// actually searching is never hijacked.
  KeyEventResult _handleJumpToSearch(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.keyS) {
      return KeyEventResult.ignored;
    }
    _searchFocusNode.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _handleGridKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final jumpedToSearch = _handleJumpToSearch(node, event);
    if (jumpedToSearch == KeyEventResult.handled) return jumpedToSearch;

    final movies = _filtered;
    if (movies.isEmpty) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _moveFocusHorizontal(1, movies.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _moveFocusHorizontal(-1, movies.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveFocusVertical(1, movies.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveFocusVertical(-1, movies.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.space:
        _openMovie(movies[_clampFocusIndex(_focusedTileIndex, movies.length)]);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _openRemotePairingDialog() {
    RemoteControlService.instance.requestPairingCode();
    showDialog(context: context, builder: (_) => const _RemotePairingDialog());
  }

  Future<void> _toggleAdmin() async {
    if (AdminSession.isAdmin.value) {
      AdminSession.isAdmin.value = false;
      return;
    }

    final unlocked = await showDialog<bool>(
      context: context,
      builder: (_) => _AdminPasswordDialog(api: _api),
    );
    if (unlocked == true) {
      AdminSession.isAdmin.value = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Scaffold(
        // backgroundColor: Colors.black,
        appBar: AppBar(
          // Material 3 otherwise raises the AppBar's elevation (and paints a
          // surface tint that visibly lightens it) once the grid scrolls
          // underneath. `scrolledUnderElevation: 0` alone stops the
          // elevation change; `surfaceTintColor: Colors.transparent` belts
          // it too, so no tint can be painted regardless of elevation, and
          // pinning `backgroundColor` explicitly rules out it resolving to
          // a different value than the (otherwise theme-derived) body
          // background in any state.
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Image.asset('assets/images/logo.png', height: 32),
          actions: [
            // Non-focusable, key-only: lets "S" jump to the search field
            // from either button without adding an extra Tab stop.
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _handleJumpToSearch,
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: IconButton(
                        icon: const Icon(Icons.settings_remote),
                        tooltip: 'Pair remote control',
                        onPressed: _openRemotePairingDialog,
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: AdminSession.isAdmin,
                        builder: (context, isAdmin, _) => IconButton(
                          icon: Icon(isAdmin ? Icons.lock_open : Icons.lock),
                          tooltip: isAdmin
                              ? 'Exit admin mode'
                              : 'Enter admin mode',
                          onPressed: _toggleAdmin,
                        ),
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(5),
                      child: IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh library',
                        onPressed: () =>
                            setState(() => _moviesFuture = _load()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 20, 8),
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(1),
                child: TextField(
                  focusNode: _searchFocusNode,
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search movies…',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    if (_syncingSearchFromRemote) return;
                    setState(() => _query = value);
                    _broadcastScreenState();
                  },
                ),
              ),
            ),
          ),
        ),
        body: FutureBuilder<List<Movie>>(
          future: _moviesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _buildError(snapshot.error.toString());
            }

            final movies = _filtered;
            if (movies.isEmpty) {
              return Center(
                child: Text(
                  _allMovies.isEmpty
                      ? 'No movies yet. Drop files into the backend\'s movies/ folder.'
                      : 'No movies match "$_query".',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
            }

            final focusedIndex = _clampFocusIndex(
              _focusedTileIndex,
              movies.length,
            );

            return FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: Focus(
                focusNode: _gridFocusNode,
                autofocus: true,
                onKeyEvent: _handleGridKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _updateGridMetrics(constraints.maxWidth);
                    return GridView.builder(
                      controller: _gridScrollController,
                      padding: const EdgeInsets.all(_gridPadding),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: _gridMaxCrossAxisExtent,
                            childAspectRatio: _gridChildAspectRatio,
                            crossAxisSpacing: _gridCrossAxisSpacing,
                            mainAxisSpacing: _gridMainAxisSpacing,
                          ),
                      itemCount: movies.length,
                      itemBuilder: (context, index) => _MovieTile(
                        movie: movies[index],
                        onTap: () => _openMovie(movies[index]),
                        focused:
                            _gridFocusNode.hasFocus && index == focusedIndex,
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Could not reach the backend:\n$message',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() => _moviesFuture = _load()),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _MovieTile extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;
  final bool focused;

  const _MovieTile({
    required this.movie,
    required this.onTap,
    this.focused = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      // The whole grid is one keyboard-focusable region (see
      // MovieGridScreen's _gridFocusNode); arrow keys move `focused` between
      // tiles rather than each tile being its own Tab stop.
      canRequestFocus: false,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: focused
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 3,
                      )
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: movie.posterUrl == null
                      ? PosterPlaceholder(title: movie.title)
                      : Image.network(
                          movie.posterUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              PosterPlaceholder(title: movie.title),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            movie.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (movie.year != null)
            Text(
              '${movie.year}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
        ],
      ),
    );
  }
}

/// Dialog prompting for the admin password. Pops `true` once the backend
/// confirms it's correct, `false`/`null` on cancel.
class _AdminPasswordDialog extends StatefulWidget {
  final ApiService api;

  const _AdminPasswordDialog({required this.api});

  @override
  State<_AdminPasswordDialog> createState() => _AdminPasswordDialogState();
}

class _AdminPasswordDialogState extends State<_AdminPasswordDialog> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final correct = await widget.api.checkAdminPassword(
        _passwordController.text,
      );
      if (!mounted) return;
      if (correct) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _submitting = false;
          _error = 'Incorrect password';
        });
      }
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
      title: const Text('Enter admin mode'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _passwordController,
                enabled: !_submitting,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Admin password'),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Password is required'
                    : null,
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
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
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
              : const Text('Unlock'),
        ),
      ],
    );
  }
}

/// Displays the backend-generated pairing code for linking the "Pigflix
/// Remote" companion app, and auto-closes as soon as
/// [RemoteControlService.isPaired] flips true. Unlike [_AdminPasswordDialog]
/// there's nothing to submit here — the phone does the submitting — so this
/// widget only ever displays state pushed in over the socket.
class _RemotePairingDialog extends StatefulWidget {
  const _RemotePairingDialog();

  @override
  State<_RemotePairingDialog> createState() => _RemotePairingDialogState();
}

class _RemotePairingDialogState extends State<_RemotePairingDialog> {
  @override
  void initState() {
    super.initState();
    RemoteControlService.instance.isPaired.addListener(_onPairedChange);
  }

  @override
  void dispose() {
    RemoteControlService.instance.isPaired.removeListener(_onPairedChange);
    super.dispose();
  }

  void _onPairedChange() {
    if (RemoteControlService.instance.isPaired.value && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pair remote control'),
      content: SizedBox(
        width: 280,
        child: ValueListenableBuilder<String?>(
          valueListenable: RemoteControlService.instance.pairingCode,
          builder: (context, code, _) {
            if (code == null) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating code…'),
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Enter this on the Pigflix Remote app',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Waiting for phone…'),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
