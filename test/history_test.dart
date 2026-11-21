import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuejian/history/reading_history.dart';
import 'package:yuejian/models/local_book.dart';
import 'package:yuejian/screens/history_screen.dart';
import 'package:yuejian/cloud/library_sync.dart';

LocalBook book(String id) => LocalBook(
  id: id,
  title: id,
  author: '作者',
  format: 'txt',
  sections: [const BookSection('一', '正文。'), const BookSection('二', '正文。')],
);
void main() {
  test(
    'history persists time and completion independently of reading position',
    () async {
      SharedPreferences.setMockInitialValues({});
      final h = ReadingHistory();
      await h.load();
      final b = book('在读');
      h.add(b, const Duration(minutes: 12));
      h.complete(b);
      await h.save();
      final restored = ReadingHistory();
      await restored.load();
      expect(restored.record(b).milliseconds, 720000);
      expect(restored.record(b).completed, true);
      expect(b.offset, 0);
      restored.complete(b, value: false);
      await restored.save();
    },
  );
  test(
    'furthest progress ignores timestamp and compares audio only at same text',
    () {
      final b = book('b')
        ..locate(1, 1)
        ..audioOffsetMs = 1000;
      expect(LibrarySync.isAhead(0, 3, 90000, b), false);
      expect(LibrarySync.isAhead(1, 0, 90000, b), false);
      expect(LibrarySync.isAhead(1, 1, 2000, b), true);
      expect(LibrarySync.isAhead(1, 1, 500, b), false);
      expect(LibrarySync.isAhead(1, 2, 0, b), true);
    },
  );
  testWidgets('history separates reading, finished and unread lists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final h = ReadingHistory();
    await h.load();
    final reading = book('正在看'), unread = book('还没看'), done = book('看完了');
    h.add(reading, const Duration(minutes: 2));
    h.complete(done);
    await h.save();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryPanel(
            books: [reading, unread, done],
            history: h,
            open: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('正在看'), findsOneWidget);
    expect(find.text('看完了'), findsNothing);
    await tester.tap(find.text('未读').last);
    await tester.pumpAndSettle();
    expect(find.text('还没看'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
