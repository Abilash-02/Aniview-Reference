import 'dart:convert';
import 'dart:io';

import 'package:aniview/subtitles.dart';
import 'package:flutter_test/flutter_test.dart';

const _srt =
    '1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Hello</i> &amp; bye\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\nTwo\r\nlines\r\n';
const _vtt =
    'WEBVTT\n\n00:01.000 --> 00:02.000 align:start\nHi\n\nnote\n01:00:00.500 --> 01:00:01.000\nLate\n';
const _ass = '''[Script Info]
Title: x

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.50,0:00:03.00,Default,,0,0,0,,{\\an8}Hi, there\\Nfriend
Dialogue: 0,0:00:02.00,0:00:04.00,Sign,,0,0,0,,{\\p1}m 0 0 l 10 10{\\p0}
Dialogue: 0,0:00:02.00,0:00:04.00,Default,,0,0,0,,Over\\hlap
''';

void main() {
  test('tells a subtitle\'s format by its address, else by what\'s in it', () {
    expect(subtitleExtOf('https://x/a/en.ASS?t=1'), 'ass');
    expect(subtitleExtOf('https://x/api/subs?id=3'), isNull);
    expect(sniffSubtitle(utf8.encode('﻿WEBVTT\n')), 'vtt');
    expect(sniffSubtitle(utf8.encode(_ass)), 'ass');
    expect(sniffSubtitle(utf8.encode(_srt)), 'srt');
  });

  test('reads SRT, WebVTT and ASS cues as plain text', () {
    expect(parseCues(_srt, 'srt'), [
      (
        start: const Duration(seconds: 1),
        end: const Duration(milliseconds: 2500),
        text: 'Hello & bye',
      ),
      (
        start: const Duration(seconds: 3),
        end: const Duration(seconds: 4),
        text: 'Two\nlines',
      ),
    ]);
    expect([for (final c in parseCues(_vtt, 'vtt')) c.text], ['Hi', 'Late']);
    expect(
      parseCues(_vtt, 'vtt').last.start,
      const Duration(hours: 1, milliseconds: 500),
    );
    expect(parseCues(_ass, 'ass'), [
      (
        start: const Duration(milliseconds: 1500),
        end: const Duration(seconds: 3),
        text: 'Hi, there\nfriend',
      ),
      (
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 4),
        text: 'Over lap',
      ),
    ]);
  });

  test('labels map to language codes', () {
    expect(languageCode('English'), 'eng');
    expect(languageCode('Spanish (Latin America)'), 'spa');
    expect(languageCode('pt-BR'), 'por');
    expect(languageCode('Klingon'), 'und');
  });

  final ffmpeg = Process.runSync('which', ['ffmpeg']).exitCode == 0;
  for (final faststart in [false, true]) {
    test(
      'embeds text tracks that ffmpeg reads back, the video untouched${faststart ? ' (header first)' : ''}',
      () async {
        final dir = await Directory.systemTemp.createTemp('embed');
        addTearDown(() => dir.delete(recursive: true));
        final mp4 = '${dir.path}/ep.mp4';
        final made = await Process.run('ffmpeg', [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'testsrc=size=160x120:rate=10',
          '-f',
          'lavfi',
          '-i',
          'sine', //
          '-t', '5', '-c:v', 'libx264', '-c:a', 'aac', //
          if (faststart) ...['-movflags', '+faststart'],
          mp4,
        ]);
        expect(made.exitCode, 0, reason: '${made.stderr}');

        await embedSubtitles(mp4, [
          ('English', parseCues(_ass, 'ass')),
          ('Spanish', parseCues(_srt, 'srt')),
          ('Empty', const []),
        ]);

        final probe = await Process.run('ffprobe', [
          '-v',
          'error',
          '-show_entries',
          'stream=codec_name,codec_type:stream_tags=language',
          '-of',
          'json',
          mp4,
        ]);
        final streams = (jsonDecode('${probe.stdout}')['streams'] as List)
            .cast<Map>();
        expect(
          [for (final s in streams) s['codec_name']],
          ['h264', 'aac', 'mov_text', 'mov_text'],
        );
        expect(
          [for (final s in streams.skip(2)) s['tags']['language']],
          ['eng', 'spa'],
        );

        final srt = await Process.run('ffmpeg', [
          '-v',
          'error',
          '-i',
          mp4,
          '-map',
          '0:s:0',
          '-f',
          'srt',
          '-',
        ]);
        expect(srt.exitCode, 0, reason: '${srt.stderr}');
        final back = parseCues('${srt.stdout}', 'srt');
        expect(
          [for (final c in back) c.text],
          ['Hi, there\nfriend', 'Hi, there\nfriend\nOver lap', 'Over lap'],
        );
        expect(back.first.start, const Duration(milliseconds: 1500));
        expect(back.last.end, const Duration(seconds: 4));

        // The picture still decodes end to end.
        final decode = await Process.run('ffmpeg', [
          '-v',
          'error',
          '-i',
          mp4,
          '-map',
          '0:v',
          '-f',
          'null',
          '-',
        ]);
        expect(decode.exitCode, 0);
        expect('${decode.stderr}'.trim(), isEmpty);
      },
      skip: ffmpeg ? false : 'needs ffmpeg',
    );
  }
}
