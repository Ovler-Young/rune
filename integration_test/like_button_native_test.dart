import 'dart:io';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:rune/bindings/bindings.dart';
import 'package:rune/main.dart' as app;
import 'package:rune/providers/status.dart';
import 'package:rune/screens/home/widgets/welcome.dart';
import 'package:rune/utils/api/fetch_media_files.dart';
import 'package:rune/utils/api/get_liked.dart';
import 'package:rune/utils/api/request_failure.dart';
import 'package:rune/utils/api/set_liked.dart';
import 'package:rune/utils/playing_item.dart';
import 'package:rune/widgets/playback_controller/like_button.dart';
import 'package:rune/widgets/playback_controller/next_button.dart';
import 'package:rune/widgets/playback_controller/playback_controller.dart';
import 'package:rune/widgets/playback_controller/previous_button.dart';

import 'e2e_library_flow_test.dart' as lifecycle;

// Run in isolated app storage with E2E_LIBRARY_A pointing to two playable
// tracks titled A Late and B Synced. Native audio output must be available.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native late A response preserves B heart and pointer tap', (
    tester,
  ) async {
    app.main(const []);
    await lifecycle.waitFor(
      tester,
      () => find.byType(FluentApp).evaluate().isNotEmpty,
      description: 'application startup',
    );
    await lifecycle.pumpFor(tester, const Duration(seconds: 2));
    if (find.byType(WelcomePage).evaluate().isNotEmpty) {
      await lifecycle.addLibrary(
        tester,
        Platform.environment['E2E_LIBRARY_A']!,
        expectLibraryHome: true,
      );
    }
    await lifecycle.waitFor(
      tester,
      () => find.byType(PlaybackController).evaluate().isNotEmpty,
      description: 'the fixture library to open',
    );
    await lifecycle.openTracks(tester);
    final media = await fetchMediaFiles(0, 25);
    final trackA = media.singleWhere((track) => track.title == 'A Late');
    final trackB = media.singleWhere((track) => track.title == 'B Synced');
    final a = PlayingItem.libraryItem(
      libraryId: trackA.libraryId,
      fileUuid: trackA.track,
    );
    final b = PlayingItem.libraryItem(
      libraryId: trackB.libraryId,
      fileUuid: trackB.track,
    );
    expect(a, isNot(b));
    expect(await setLiked(a, true), isTrue);
    expect(await setLiked(b, false), isFalse);

    final original = assignRustSignal['GetLikedResponse']!;
    Uint8List? heldMessage;
    Uint8List? heldBinary;
    bool? heldLiked;
    var holdA = false;
    var bRead = false;
    assignRustSignal['GetLikedResponse'] = (message, binary) {
      final response = GetLikedResponse.bincodeDeserialize(message);
      final item = PlayingItem.fromRequest(response.item);
      if (holdA && item == a) {
        if (heldMessage != null) throw StateError('Duplicate held A response');
        heldLiked = response.liked;
        heldMessage = Uint8List.fromList(message);
        heldBinary = Uint8List.fromList(binary);
      } else {
        if (item == b) bRead = true;
        original(message, binary);
      }
    };
    addTearDown(() => assignRustSignal['GetLikedResponse'] = original);

    final context = tester.element(find.byType(PlaybackController));
    final status = context.read<PlaybackStatusProvider>();
    final load = LoadResolvedItemsRequest(
      items: await playingItemRefs([a, b]),
      startIndex: 1,
      mode: PlaylistOperateMode.replace,
      play: LoadPlay.pause,
    );
    await awaitResponse(
      'LoadResolvedItemsRequest',
      LoadResolvedItemsResponse.rustSignalStream,
      responseCallId: (response) => response.message.callId?.toInt(),
      send: (callId) => load.copyWith(callId: () => callId).sendSignalToRust(),
    );
    await lifecycle.waitFor(
      tester,
      () => status.playingItem == b && status.playbackStatus.ready,
      description: 'B to be queued and ready',
    );
    await tester.pump();
    holdA = true;
    await tester.tap(find.byType(PreviousButton));
    await lifecycle.waitFor(
      tester,
      () =>
          status.playingItem == a &&
          status.playbackStatus.ready &&
          heldMessage != null,
      description: 'A selected by pointer with its real response held',
    );
    expect(heldLiked, isTrue);
    final like = find.byType(LikeButton);
    final state = tester.state(like);
    bRead = false;
    await tester.pump();
    await tester.tap(find.byType(NextButton));
    await lifecycle.waitFor(
      tester,
      () => status.playingItem == b && status.playbackStatus.ready && bRead,
      description: 'B selected by pointer and its native like read completed',
    );
    await tester.pump();
    expect(tester.state(like), same(state));
    expect(tester.widget<LikeButton>(like).item, b);
    final heart = find.descendant(
      of: like,
      matching: find.byIcon(Symbols.favorite),
    );
    expect(tester.widget<Icon>(heart).fill, 0);

    // Deliver the exact native response that was held, through its real handler.
    holdA = false;
    original(heldMessage!, heldBinary!);
    await lifecycle.pumpFor(tester, const Duration(milliseconds: 700));
    expect(tester.state(like), same(state));
    expect(tester.widget<LikeButton>(like).item, b);
    expect(tester.widget<Icon>(heart).fill, 0);
    expect(like.hitTestable(), findsOneWidget);
    await tester.tap(like);
    await lifecycle.waitFor(
      tester,
      () => tester.widget<Icon>(heart).fill == 1,
      description: 'B heart to fill after its pointer tap',
    );
    // Poll the native API: optimistic paint alone does not prove persistence.
    var persistedB = false;
    for (var attempt = 0; attempt < 40 && !persistedB; attempt++) {
      persistedB = await getLiked(b);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(persistedB, isTrue);
    expect(await getLiked(a), isTrue);
    debugPrint(
      'Native pointer scenario passed: held A=true; B remained false; '
      'B tap persisted true; A stayed true.',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
