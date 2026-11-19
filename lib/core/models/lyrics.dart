import 'package:jp_transliterate/jp_transliterate.dart';

class LyricWord {
  final String text;
  final int startMs;
  final int endMs;
  const LyricWord(this.text, this.startMs, this.endMs);
}

class FuriganaSegment {
  final String text;
  final String? reading;
  const FuriganaSegment(this.text, [this.reading]);
}

class LyricLine {
  final int startMs;
  final String text;
  final List<LyricWord> words;
  final String? translation;
  final String? romaji;
  final List<FuriganaSegment> furigana;

  const LyricLine({
    required this.startMs,
    required this.text,
    this.words = const [],
    this.translation,
    this.romaji,
    this.furigana = const [],
  });

  LyricLine copyWith({
    int? startMs,
    String? text,
    List<LyricWord>? words,
    String? translation,
    String? romaji,
    List<FuriganaSegment>? furigana,
  }) => LyricLine(
    startMs: startMs ?? this.startMs,
    text: text ?? this.text,
    words: words ?? this.words,
    translation: translation ?? this.translation,
    romaji: romaji ?? this.romaji,
    furigana: furigana ?? this.furigana,
  );
}

class ParsedLyrics {
  final List<LyricLine> lines;
  final bool instrumental;

  const ParsedLyrics(this.lines, {this.instrumental = false});

  int? activeIndex(Duration position) {
    if (lines.isEmpty) return null;
    final ms = position.inMilliseconds;
    var lo = 0;
    var hi = lines.length - 1;
    var ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].startMs <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }
}

class LyricsParser {
  static final _lrc = RegExp(r'\[(\d+):(\d{1,2})(?:[\.:](\d{1,3}))?\]');
  static final _yrcHead = RegExp(r'^\[(\d+),(\d+)\]');
  static final _yrcWord = RegExp(r'\((\d+),(\d+),\d+\)([^\(]*)');

  static List<LyricLine> _parseLrc(String? source) {
    if (source == null || source.trim().isEmpty) return const [];
    final out = <LyricLine>[];
    for (final raw in source.split(RegExp(r'\r?\n'))) {
      final line = raw.trimRight();
      final matches = _lrc.allMatches(line).toList(growable: false);
      if (matches.isEmpty) continue;
      final text = line.substring(matches.last.end).trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final min = int.tryParse(m.group(1)!) ?? 0;
        final sec = int.tryParse(m.group(2)!) ?? 0;
        final fraction = m.group(3);
        var fractionMs = 0;
        if (fraction != null && fraction.isNotEmpty) {
          final value = int.tryParse(fraction) ?? 0;
          final scale = fraction.length == 1 ? 100 : fraction.length == 2 ? 10 : 1;
          fractionMs = value * scale;
        }
        out.add(LyricLine(startMs: min * 60000 + sec * 1000 + fractionMs, text: text));
      }
    }
    out.sort((a,b)=>a.startMs.compareTo(b.startMs));
    return out;
  }

  static List<LyricLine> _parseYrc(String? source) {
    if (source == null || source.trim().isEmpty) return const [];
    final out = <LyricLine>[];
    for (final raw in source.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      final head = _yrcHead.firstMatch(line);
      if (head == null) continue;
      final start = int.tryParse(head.group(1)!) ?? 0;
      final words = <LyricWord>[];
      for (final m in _yrcWord.allMatches(line.substring(head.end))) {
        final wordStart = int.tryParse(m.group(1)!) ?? start;
        final dur = int.tryParse(m.group(2)!) ?? 0;
        final text = m.group(3) ?? '';
        if (text.isNotEmpty) words.add(LyricWord(text, wordStart, wordStart + dur));
      }
      final text = words.map((e)=>e.text).join().trim();
      if (text.isNotEmpty && words.isNotEmpty) {
        out.add(LyricLine(startMs: start, text: text, words: words));
      }
    }
    out.sort((a,b)=>a.startMs.compareTo(b.startMs));
    return out;
  }

  static void _mergeSecondary(List<LyricLine> target, List<LyricLine> secondary) {
    if (target.isEmpty || secondary.isEmpty) return;
    var cursor = 0;
    for (var i = 0; i < target.length; i++) {
      while (cursor + 1 < secondary.length &&
          (secondary[cursor + 1].startMs - target[i].startMs).abs() <=
              (secondary[cursor].startMs - target[i].startMs).abs()) {
        cursor++;
      }
      if ((secondary[cursor].startMs - target[i].startMs).abs() <= 350) {
        target[i] = target[i].copyWith(translation: secondary[cursor].text);
      }
    }
  }

  static ParsedLyrics parse(String? lrc, {String? tlyric, String? ytlrc, String? yrc, String? romalrc, String? yromalrc}) {
    final lrcLines = _parseLrc(lrc);
    final yrcLines = _parseYrc(yrc);
    final lines = yrcLines.isNotEmpty ? [...yrcLines] : [...lrcLines];
    var instrumental = false;
    if (lines.length <= 10 && lines.any((e)=>e.text.contains('纯音乐，请欣赏'))) {
      instrumental = true;
      lines.removeWhere((e)=>e.text.contains('纯音乐，请欣赏'));
    }
    _mergeSecondary(lines, _parseLrc(yrcLines.isNotEmpty ? (ytlrc ?? tlyric) : (ytlrc ?? tlyric)));
    // If line-level translation timestamps do not align, try the normal lrc too.
    if (lines.any((e)=>e.translation == null) && ytlrc != null) _mergeSecondary(lines, _parseLrc(tlyric));
    final roman = _parseLrc(yromalrc ?? romalrc);
    if (roman.isNotEmpty) {
      for (var i = 0; i < lines.length; i++) {
        var best = 0;
        var bestDelta = 1 << 30;
        for (var j = 0; j < roman.length; j++) {
          final d = (roman[j].startMs - lines[i].startMs).abs();
          if (d < bestDelta) { bestDelta = d; best = j; }
        }
        if (bestDelta <= 350) lines[i] = lines[i].copyWith(romaji: roman[best].text);
      }
    }
    return ParsedLyrics(lines, instrumental: instrumental);
  }

  static bool _containsKanji(String text) => text.runes.any((r)=>r >= 0x4E00 && r <= 0x9FFF);
  static bool _containsKana(String text) => text.runes.any((r)=>
      (r >= 0x3040 && r <= 0x30FF) || (r >= 0xFF66 && r <= 0xFF9D));

  /// Adds offline Japanese romaji + furigana using the Android/iOS native
  /// tokenizer exposed by jp_transliterate. Network-provided romaji remains the
  /// preferred source; native transliteration is only a fallback.
  static Future<ParsedLyrics> enrichJapanese(ParsedLyrics parsed) async {
    if (parsed.lines.isEmpty) return parsed;

    // Match the iOS client's guard: only run Japanese transliteration when the
    // lyric body as a whole looks Japanese. This prevents Chinese lyrics with
    // a few shared CJK characters from receiving bogus Japanese readings.
    final nonEmpty = parsed.lines
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (nonEmpty.isEmpty) return parsed;
    final kanaLines = nonEmpty.where(_containsKana).length;
    final japanese = kanaLines >= 3 || kanaLines / nonEmpty.length >= 0.20;
    if (!japanese) return parsed;

    final out = <LyricLine>[];
    final romajiCache = <String, String?>{};
    final furiganaCache = <String, List<FuriganaSegment>>{};

    for (final line in parsed.lines) {
      if (!_containsKanji(line.text) && !_containsKana(line.text)) {
        out.add(line);
        continue;
      }
      try {
        String? generatedRomaji = line.romaji;
        var segments = line.furigana;

        if (_containsKanji(line.text)) {
          final cachedRomaji = romajiCache[line.text];
          if (cachedRomaji != null || romajiCache.containsKey(line.text)) {
            if (generatedRomaji?.trim().isEmpty ?? true) generatedRomaji = cachedRomaji;
          } else {
            final data = await JpTransliterate.transliterate(kanji: line.text);
            final value = data.romaji.trim();
            romajiCache[line.text] = value.isEmpty ? null : value;
            if (generatedRomaji?.trim().isEmpty ?? true) generatedRomaji = value.isEmpty ? null : value;
          }

          if (furiganaCache.containsKey(line.text)) {
            segments = furiganaCache[line.text]!;
          } else {
            final words = await JpTransliterate.transliterateWords(kanji: line.text);
            final candidate = <FuriganaSegment>[];
            for (final item in words) {
              final surface = item.kanji;
              if (surface.isEmpty) continue;
              final reading = item.hiragana;
              candidate.add(FuriganaSegment(
                surface,
                reading != surface && reading.isNotEmpty ? reading : null,
              ));
            }
            final sourceNormalized = line.text.replaceAll(RegExp(r'\s+'), '');
            final candidateNormalized = candidate
                .map((e) => e.text)
                .join()
                .replaceAll(RegExp(r'\s+'), '');
            if (candidate.isNotEmpty && candidateNormalized == sourceNormalized) {
              furiganaCache[line.text] = candidate;
              segments = candidate;
            } else {
              furiganaCache[line.text] = const [];
            }
          }
        }

        if ((generatedRomaji == null || generatedRomaji.trim().isEmpty) && _containsKana(line.text)) {
          final cacheKey = 'kana:${line.text}';
          if (romajiCache.containsKey(cacheKey)) {
            generatedRomaji = romajiCache[cacheKey];
          } else {
            final kata = JpTransliterate.hiraganaToKatakana(line.text);
            final value = await JpTransliterate.katakanaToRomaji(katakana: kata);
            generatedRomaji = value.trim().isEmpty ? null : value.trim();
            romajiCache[cacheKey] = generatedRomaji;
          }
        }
        out.add(line.copyWith(romaji: generatedRomaji, furigana: segments));
      } catch (_) {
        // A plugin/transliteration failure must never make ordinary lyrics
        // unusable. Keep the server-provided lyric untouched.
        out.add(line);
      }
    }
    return ParsedLyrics(out, instrumental: parsed.instrumental);
  }
}
