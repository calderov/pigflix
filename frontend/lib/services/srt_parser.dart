import 'package:chewie/chewie.dart';

final RegExp _timeRange = RegExp(
  r'(\d{2}):(\d{2}):(\d{2})[,.](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[,.](\d{3})',
);

/// Parses the SubRip (.srt) subtitle format into chewie's [Subtitle] cues.
/// Cues are separated by blank lines; within a cue, whichever line matches
/// a "start --> end" timestamp marks where the index line ends and the cue
/// text begins, so a missing/garbled index line doesn't break parsing.
List<Subtitle> parseSrt(String content) {
  final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final blocks = normalized.split(RegExp(r'\n\s*\n'));
  final cues = <Subtitle>[];

  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.isEmpty) continue;

    final timeLineIndex = lines.indexWhere((l) => _timeRange.hasMatch(l));
    if (timeLineIndex == -1) continue;

    final match = _timeRange.firstMatch(lines[timeLineIndex])!;
    Duration toDuration(int group) => Duration(
      hours: int.parse(match.group(group)!),
      minutes: int.parse(match.group(group + 1)!),
      seconds: int.parse(match.group(group + 2)!),
      milliseconds: int.parse(match.group(group + 3)!),
    );

    final text = lines.sublist(timeLineIndex + 1).join('\n').trim();
    if (text.isEmpty) continue;

    cues.add(
      Subtitle(
        index: cues.length,
        start: toDuration(1),
        end: toDuration(5),
        text: text,
      ),
    );
  }

  return cues;
}
