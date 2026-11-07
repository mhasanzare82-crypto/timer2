class TimeFormatter {
  static String format(int totalSeconds) {
    final seconds = totalSeconds < 0 ? 0 : totalSeconds;

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '$hours ساعت و $minutes دقیقه';
    }

    if (minutes > 0) {
      return '$minutes دقیقه و $remainingSeconds ثانیه';
    }

    return '$remainingSeconds ثانیه';
  }

  static String clock(int totalSeconds) {
    final seconds = totalSeconds < 0 ? 0 : totalSeconds;

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
