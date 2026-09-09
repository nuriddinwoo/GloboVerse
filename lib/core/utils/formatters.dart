String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999).toInt();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String initialsFor(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'GV';
  if (parts.length == 1) {
    return String.fromCharCodes(parts.first.runes.take(2)).toUpperCase();
  }
  return String.fromCharCodes([
    parts.first.runes.first,
    parts.last.runes.first,
  ]).toUpperCase();
}
