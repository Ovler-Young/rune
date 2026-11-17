import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../bindings/bindings.dart';
import '../../providers/library_open_state.dart';
import '../../utils/playing_item.dart';
import '../../widgets/playback_controller/like_button.dart';

const a = PlayingItem.libraryItem(libraryId: 'library', fileUuid: 'a');
const b = PlayingItem.libraryItem(libraryId: 'library', fileUuid: 'b');

void main() {
  for (final returnToA in [false, true]) {
    for (final pendingToggle in [false, true]) {
      testWidgets(
        'late ${pendingToggle ? "toggle" : "read"} after ${returnToA ? "A-B-A" : "A-B"} preserves current heart and tap',
        (tester) async {
          final pending = Completer<bool>();
          final writes = <(PlayingItem, bool)>[];
          final persisted = <PlayingItem, bool>{a: false, b: false};
          var reads = 0;
          var holdToggle = pendingToggle;
          Future<bool> fetch(PlayingItem item) {
            if (++reads == 1 && !pendingToggle) return pending.future;
            return Future.value(persisted[item]!);
          }

          Future<bool> toggle(PlayingItem item, bool liked) async {
            writes.add((item, liked));
            if (holdToggle) {
              holdToggle = false;
              await pending.future;
              // Another writer has already changed the persisted value.
              persisted[item] = false;
              return liked;
            }
            persisted[item] = liked;
            return liked;
          }

          Future<void> show(PlayingItem item) async {
            await tester.pumpWidget(
              ChangeNotifierProvider<LibraryOpenStateProvider>(
                create: (_) => _LibraryOpenStateProvider(),
                child: FluentApp(
                  home: LikeButton(
                    item: item,
                    fetchLikedStatus: fetch,
                    setLikedStatus: toggle,
                  ),
                ),
              ),
            );
            await tester.pump();
          }

          await show(a);
          final originalState = tester.state(find.byType(LikeButton));
          if (pendingToggle) {
            await tester.tap(find.byIcon(Symbols.favorite));
            await tester.pump();
            expect(writes, [(a, true)]);
          }
          await show(b);
          if (returnToA) await show(a);
          expect(tester.state(find.byType(LikeButton)), same(originalState));
          expect(tester.widget<Icon>(find.byIcon(Symbols.favorite)).fill, 0);

          if (returnToA && pendingToggle) {
            final before = writes.length;
            await tester.tap(find.byIcon(Symbols.favorite));
            expect(writes.length, before);
          }
          pending.complete(true);
          await tester.pump();
          expect(tester.widget<Icon>(find.byIcon(Symbols.favorite)).fill, 0);
          await tester.tap(find.byIcon(Symbols.favorite));
          await tester.pump();
          expect(writes.last, (returnToA ? a : b, true));
          expect(tester.widget<Icon>(find.byIcon(Symbols.favorite)).fill, 1);
        },
      );
    }
  }

  testWidgets('waits for initial state and serializes rapid tap intent', (
    tester,
  ) async {
    final read = Completer<bool>();
    final firstWrite = Completer<bool>();
    final writes = <bool>[];
    var persisted = true;
    await tester.pumpWidget(
      ChangeNotifierProvider<LibraryOpenStateProvider>(
        create: (_) => _LibraryOpenStateProvider(),
        child: FluentApp(
          home: LikeButton(
            item: a,
            fetchLikedStatus: (_) => read.future,
            setLikedStatus: (_, liked) async {
              writes.add(liked);
              if (writes.length == 1) await firstWrite.future;
              persisted = liked;
              return liked;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Symbols.favorite));
    await tester.pump();
    expect(writes, isEmpty);
    read.complete(true);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Symbols.favorite));
    await tester.pump();
    expect(tester.widget<Icon>(find.byIcon(Symbols.favorite)).fill, 0);
    await tester.tap(find.byIcon(Symbols.favorite));
    await tester.pump();
    expect(writes, [false]);
    expect(tester.widget<Icon>(find.byIcon(Symbols.favorite)).fill, 1);
    firstWrite.complete(false);
    await tester.pump();
    expect(writes, [false, true]);
    expect(persisted, isTrue);
    await tester.tap(find.byIcon(Symbols.favorite));
    await tester.pump();
    expect(writes, [false, true, false]);
    expect(persisted, isFalse);
    expect(tester.widget<Icon>(find.byIcon(Symbols.favorite)).fill, 0);
  });

  testWidgets(
    'failed latest write restores persisted state after queued taps',
    (tester) async {
      final firstWrite = Completer<bool>();
      final failure = StateError('write failed');
      final writes = <bool>[];
      var persisted = false;
      await tester.pumpWidget(
        ChangeNotifierProvider<LibraryOpenStateProvider>(
          create: (_) => _LibraryOpenStateProvider(),
          child: FluentApp(
            home: LikeButton(
              item: a,
              fetchLikedStatus: (_) async => persisted,
              setLikedStatus: (_, liked) async {
                writes.add(liked);
                if (writes.length == 1) {
                  await firstWrite.future;
                  return persisted = liked;
                }
                throw failure;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final escaped = <Object>[];
      await runZonedGuarded(() async {
        await tester.tap(find.byIcon(Symbols.favorite));
        await tester.pump();
        await tester.tap(find.byIcon(Symbols.favorite));
        await tester.pump();
        firstWrite.complete(true);
        await tester.pumpAndSettle();
      }, (error, _) => escaped.add(error));
      expect(escaped, [same(failure)]);
      expect(writes, [true, false]);
      expect(persisted, isTrue);
      expect(tester.widget<Icon>(find.byIcon(Symbols.favorite)).fill, 1);
    },
  );
}

class _LibraryOpenStateProvider extends ChangeNotifier
    implements LibraryOpenStateProvider {
  @override
  bool get isReadOnlyReplica => false;

  @override
  LibraryRecordSummary? get openRecord => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
