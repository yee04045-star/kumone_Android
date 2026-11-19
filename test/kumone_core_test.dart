import 'package:flutter_test/flutter_test.dart';
import 'package:kumone_flutter/core/api/netease_crypto.dart';
import 'package:kumone_flutter/core/models/lyrics.dart';
import 'package:kumone_flutter/core/models/models.dart';

void main() {
  test('LRC parser preserves chronological lyrics', () {
    final parsed = LyricsParser.parse(
      '[00:02.00]second\n[00:01.25]first\n[00:03.50]third',
    );
    expect(parsed.lines.map((e) => e.text).toList(), ['first', 'second', 'third']);
    expect(parsed.activeIndex(const Duration(milliseconds: 3200)), 1);
  });


  test('YRC parser keeps per-word timing for karaoke', () {
    final parsed = LyricsParser.parse(
      null,
      yrc: '[1000,1200](1000,500,0)君(1500,500,0)の\n[2500,500](2500,250,0)歌',
    );
    expect(parsed.lines.length, 2);
    expect(parsed.lines.first.text, '君の');
    expect(parsed.lines.first.words.length, 2);
    expect(parsed.lines.first.words[0].startMs, 1000);
    expect(parsed.lines.first.words[0].endMs, 1500);
    expect(parsed.lines.first.words[1].startMs, 1500);
    expect(parsed.lines.first.words[1].endMs, 2000);
  });

  test('YRC is preferred and secondary lyrics align by timestamp', () {
    final parsed = LyricsParser.parse(
      '[00:01.00]君の歌',
      yrc: '[1005,1000](1005,500,0)君(1505,500,0)の歌',
      ytlrc: '[00:01.01]Your song',
      yromalrc: '[00:01.02]Kimi no uta',
    );
    expect(parsed.lines.single.text, '君の歌');
    expect(parsed.lines.single.words, isNotEmpty);
    expect(parsed.lines.single.translation, 'Your song');
    expect(parsed.lines.single.romaji, 'Kimi no uta');
  });

  test('Chinese lyrics are not treated as Japanese for enrichment', () async {
    const parsed = ParsedLyrics([
      LyricLine(startMs: 0, text: '春风吹过山岗'),
      LyricLine(startMs: 1000, text: '江南烟雨朦胧'),
      LyricLine(startMs: 2000, text: '你说故事很长'),
    ]);
    final enriched = await LyricsParser.enrichJapanese(parsed);
    expect(enriched.lines.every((line) => line.romaji == null), isTrue);
    expect(enriched.lines.every((line) => line.furigana.isEmpty), isTrue);
  });

  test('track model accepts standard NetEase JSON shape', () {
    final track = Track.fromJson({
      'id': 123,
      'name': 'Song',
      'ar': [
        {'id': 8, 'name': 'Artist'},
      ],
      'al': {
        'id': 9,
        'name': 'Album',
        'picUrl': 'https://example.com/a.jpg',
      },
      'dt': 210000,
      'alia': ['Alias'],
    });
    expect(track.id, 123);
    expect(track.artistNames, 'Artist');
    expect(track.duration, const Duration(minutes: 3, seconds: 30));
    expect(track.subtitle, 'Alias');
  });

  test('Kumone crypto produces deterministic transport payloads', () {
    final first = NeteaseCrypto.weapi({'hello': 'world'});
    final second = NeteaseCrypto.weapi({'hello': 'world'});
    expect(first, second);
    expect(first['params'], isNotEmpty);
    expect(first['encSecKey'], isNotEmpty);

    final eapi = NeteaseCrypto.eapi('/api/test', {'id': 1});
    expect(eapi['params'], matches(RegExp(r'^[0-9A-F]+$')));
  });
}
