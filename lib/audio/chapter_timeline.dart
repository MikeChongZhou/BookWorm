import 'dart:math' as math;

class SpeechSpan {
  final int start, end;
  const SpeechSpan(this.start, this.end);
}

/// Sentence offsets are shared by speech, highlighting, time seeking and pages.
class ChapterTimeline {
  final String text;
  late final List<SpeechSpan> sentences = _sentences(text);
  late final List<SpeechSpan> chunks = _chunks(sentences);
  final Map<int, Duration> measured = {};
  ChapterTimeline(this.text);

  static List<SpeechSpan> _sentences(String text) {
    final result = <SpeechSpan>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (!'。！？!?；;\n.'.contains(c)) continue;
      if (c == '.' &&
          i > 0 &&
          i + 1 < text.length &&
          RegExp(r'\d').hasMatch(text[i - 1]) &&
          RegExp(r'\d').hasMatch(text[i + 1])) {
        continue;
      }
      var end = i + 1;
      while (end < text.length && '”’」』"\n\r'.contains(text[end])) {
        end++;
      }
      if (text.substring(start, end).trim().isNotEmpty) {
        result.add(SpeechSpan(start, end));
      }
      start = end;
      i = end - 1;
    }
    if (start < text.length) result.add(SpeechSpan(start, text.length));
    return result;
  }

  List<SpeechSpan> _chunks(List<SpeechSpan> sentences) {
    final result = <SpeechSpan>[];
    for (final sentence in sentences) {
      var start = sentence.start;
      while (start < sentence.end) {
        var end = math.min(start + 160, sentence.end);
        if (end < sentence.end) {
          final cut = text.lastIndexOf(RegExp(r'[，,：:、\s]'), end - 1);
          if (cut > start + 40) end = cut + 1;
          final unit = text.codeUnitAt(end - 1);
          if (unit >= 0xd800 && unit <= 0xdbff) end--;
        }
        result.add(SpeechSpan(start, end));
        start = end;
      }
    }
    return result;
  }

  SpeechSpan sentenceAt(int offset) => sentences.firstWhere(
    (s) => offset < s.end,
    orElse: () => sentences.isEmpty ? const SpeechSpan(0, 0) : sentences.last,
  );
  SpeechSpan chunkAt(int offset) => chunks.firstWhere(
    (s) => offset < s.end,
    orElse: () => chunks.isEmpty ? const SpeechSpan(0, 0) : chunks.last,
  );
  Duration lengthOf(SpeechSpan chunk) =>
      measured[chunk.start] ?? estimate(text.substring(chunk.start, chunk.end));
  static Duration estimate(String text) {
    final chinese = RegExp(r'[\u3400-\u9fff]').allMatches(text).length;
    final other = text.replaceAll(RegExp(r'[\u3400-\u9fff\s]'), '').length;
    return Duration(
      milliseconds: math.max(300, (chinese / 4.2 + other / 12) * 1000).round(),
    );
  }

  Duration timeAt(int offset) {
    var milliseconds = 0;
    for (final chunk in chunks) {
      if (offset >= chunk.end) {
        milliseconds += lengthOf(chunk).inMilliseconds;
      } else {
        milliseconds +=
            (lengthOf(chunk).inMilliseconds *
                    ((offset - chunk.start).clamp(0, chunk.end - chunk.start) /
                        (chunk.end - chunk.start)))
                .round();
        break;
      }
    }
    return Duration(milliseconds: milliseconds);
  }

  Duration get duration => timeAt(text.length);
  bool get exact => chunks.every((s) => measured.containsKey(s.start));
  (SpeechSpan, Duration) atTime(Duration time) {
    var remaining = time.inMilliseconds.clamp(0, duration.inMilliseconds);
    for (final chunk in chunks) {
      final length = lengthOf(chunk).inMilliseconds;
      if (remaining < length) return (chunk, Duration(milliseconds: remaining));
      remaining -= length;
    }
    final last = chunks.isEmpty ? const SpeechSpan(0, 0) : chunks.last;
    return (last, lengthOf(last));
  }
}
