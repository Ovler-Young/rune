import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../bindings/bindings.dart';
import '../../providers/library_open_state.dart';
import '../../utils/api/request_failure.dart';
import '../../utils/playing_item.dart';
import '../../widgets/playback_controller/like_button.dart';

void main() {
  // The track is gone from its library, or the item has no liked state (such
  // as an independent file). Either failure reaches the global handler, which
  // shows its localized message.
  for (final (kind, recoveryFails) in [
    (RequestErrorKind.notFound, false),
    (RequestErrorKind.invalidInput, false),
    (RequestErrorKind.invalidInput, true),
  ]) {
    testWidgets(
      'a like refused as $kind reaches the global handler with recovery failure=$recoveryFails',
      (tester) async {
        final failure = RequestFailure('SetLikedRequest', kind, 'refused');
        var reads = 0;
        await tester.pumpWidget(
          ChangeNotifierProvider<LibraryOpenStateProvider>(
            create: (_) => _LibraryOpenStateProvider(),
            child: FluentApp(
              home: LikeButton(
                item: const PlayingItem.libraryItem(
                  libraryId: 'library-uuid',
                  fileUuid: 'file-uuid',
                ),
                fetchLikedStatus: (_) async {
                  if (++reads > 1 && recoveryFails) {
                    throw StateError('recovery read failed');
                  }
                  return true;
                },
                setLikedStatus: (_, _) async => throw failure,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // The button starts the request without awaiting it, so a failure it
        // does not catch is an uncaught error of the zone that tapped it. In the
        // app that is the root zone, whose handler shows the failure.
        final escaped = <Object>[];
        await runZonedGuarded(() async {
          await tester.tap(find.byIcon(Symbols.favorite));
          await tester.pumpAndSettle();
        }, (error, _) => escaped.add(error));
        expect(escaped, [same(failure)]);
        if (!recoveryFails) {
          expect(tester.widget<Icon>(find.byIcon(Symbols.favorite)).fill, 1);
        }
      },
    );
  }
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
