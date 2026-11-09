import 'package:aniview/history.dart';
import 'package:aniview/playback.dart';
import 'package:aniview/settings.dart';
import 'package:aniview/sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _show = {
  'id': 100,
  'title': {'userPreferred': 'Test Anime'},
  'coverImage': {'extraLarge': 'https://example.com/poster.jpg'},
};

const _duration = Duration(minutes: 24);

List<Episode> _episodes() => const [
  Episode(1, title: 'Episode One', ref: 'ep-1', thumbnail: 'https://example.com/ep1.jpg'),
  Episode(2, title: 'Episode Two', ref: 'ep-2', thumbnail: 'https://example.com/ep2.jpg'),
];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
  });

  group('Continue Watching 12-Second Rule & Progress', () {
    test('1. Watch for 5 seconds — no entry', () async {
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 5),
        duration: _duration,
        dub: false,
      );
      final records = await WatchHistory.continueWatching();
      expect(records, isEmpty);
      expect(await WatchHistory.all(), isEmpty);
    });

    test('2. Watch for 11 seconds — no entry', () async {
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 11),
        duration: _duration,
        dub: false,
      );
      final records = await WatchHistory.continueWatching();
      expect(records, isEmpty);
      expect(await WatchHistory.all(), isEmpty);
    });

    test('3. Watch for 12 seconds — entry appears', () async {
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 12),
        duration: _duration,
        dub: false,
      );
      final records = await WatchHistory.continueWatching();
      expect(records, hasLength(1));
      final entry = records.first;
      expect(entry.show.title, 'Test Anime');
      expect(entry.episode, 1);
      expect(entry.position, const Duration(seconds: 12));
      expect(entry.duration, _duration);
      expect(entry.episodeTitle, 'Episode One');
      expect(entry.episodeThumbnail, 'https://example.com/ep1.jpg');
    });

    test('4. Continue watching — progress updates', () async {
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 12),
        duration: _duration,
        dub: false,
      );
      expect((await WatchHistory.continueWatching()).first.position, const Duration(seconds: 12));

      // Continues to 60 seconds
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 60),
        duration: _duration,
        dub: false,
      );
      final records = await WatchHistory.continueWatching();
      expect(records, hasLength(1));
      expect(records.first.position, const Duration(seconds: 60));
    });

    test('5. Exit player — entry remains', () async {
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 45),
        duration: _duration,
        dub: false,
      );
      // Simulated player exit: history is re-queried
      final records = await WatchHistory.continueWatching();
      expect(records, hasLength(1));
      expect(records.first.episode, 1);
      expect(records.first.position, const Duration(seconds: 45));
    });

    test('6. Restart app — entry persists', () async {
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 50),
        duration: _duration,
        dub: false,
      );

      // Simulate app restart: re-read from SharedPreferences
      final reloaded = await WatchHistory.continueWatching();
      expect(reloaded, hasLength(1));
      expect(reloaded.first.position, const Duration(seconds: 50));
      expect(reloaded.first.show.title, 'Test Anime');
    });

    test('7. Tap entry — correct episode resumes', () async {
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 120),
        duration: _duration,
        dub: false,
      );
      final resumePoint = await WatchHistory.resumePoint(_show, 1);
      expect(resumePoint, const Duration(seconds: 120));
      // Non-matching episode does not resume from EP 1's position
      expect(await WatchHistory.resumePoint(_show, 2), isNull);
    });

    test('8. Watch the same episode again — no duplicate', () async {
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 15),
        duration: _duration,
        dub: false,
      );
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 35),
        duration: _duration,
        dub: false,
      );
      final records = await WatchHistory.continueWatching();
      expect(records, hasLength(1)); // strict single entry
      expect(records.first.position, const Duration(seconds: 35));
    });

    test('9. Complete episode — remove from unfinished Continue Watching', () async {
      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: const Duration(seconds: 15),
        duration: _duration,
        dub: false,
      );
      expect(await WatchHistory.continueWatching(), hasLength(1));

      // Episode reaches finished threshold (85% default = 20.4 mins of 24 mins)
      const completedPos = Duration(minutes: 22);
      expect(WatchHistory.finished(completedPos, _duration), isTrue);

      await WatchHistory.played(
        _show,
        source: 'TestSite',
        episodes: _episodes(),
        index: 0,
        position: completedPos,
        duration: _duration,
        dub: false,
      );
      expect(await WatchHistory.continueWatching(), isEmpty);
    });

    test('PlaybackSession dueForSave strictly follows 12-second rule', () {
      final session = PlaybackSession(_episodes(), 0);
      expect(session.dueForSave(const Duration(seconds: 5)), isFalse);
      expect(session.dueForSave(const Duration(seconds: 11)), isFalse);
      expect(session.dueForSave(const Duration(seconds: 12)), isTrue);
      // Immediately after 12s, does not save before 10s step
      expect(session.dueForSave(const Duration(seconds: 15)), isFalse);
      // At 22s (12 + 10), saves
      expect(session.dueForSave(const Duration(seconds: 22)), isTrue);
    });
  });
}
