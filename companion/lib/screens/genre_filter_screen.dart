import 'package:flutter/material.dart';

import '../services/remote_ws_service.dart';
import '../utils/haptics.dart';

/// Mirrors the "Filter by genre" dialog on the web frontend's grid screen
/// (see `frontend/lib/screens/movie_grid_screen.dart`'s `_GenreFilterDialog`),
/// as a full screen rather than a dialog. "Clear filters" and "OK" both
/// apply a genre selection to the paired display and pop back to the d-pad
/// screen; "Back" (and the system back gesture) pops without sending
/// anything, leaving whatever filter was already applied untouched — same
/// "dismissed" semantics as tapping outside the web dialog.
class GenreFilterScreen extends StatefulWidget {
  const GenreFilterScreen({super.key});

  @override
  State<GenreFilterScreen> createState() => _GenreFilterScreenState();
}

class _GenreFilterScreenState extends State<GenreFilterScreen> {
  late final Set<String> _draft = {
    ...RemoteWsService.instance.selectedGenres.value,
  };

  void _apply(Set<String> genres) {
    tapHaptic();
    RemoteWsService.instance.sendGenreFilter(genres);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Filter by genre')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: RemoteWsService.instance.availableGenres,
                  builder: (context, genres, _) {
                    if (genres.isEmpty) {
                      return const Center(
                        child: Text('No genres available yet.'),
                      );
                    }
                    return ListView(
                      children: [
                        for (final genre in genres)
                          CheckboxListTile(
                            title: Text(genre),
                            value: _draft.contains(genre),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (checked) {
                              tapHaptic();
                              setState(() {
                                if (checked ?? false) {
                                  _draft.add(genre);
                                } else {
                                  _draft.remove(genre);
                                }
                              });
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _apply(const {}),
                      child: const Text('Clear filters'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _apply(_draft),
                      child: const Text('OK'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    tapHaptic();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
