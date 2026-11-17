import '../../bindings/bindings.dart';
import '../../utils/api/request_failure.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../providers/library_open_state.dart';
import '../../providers/request_capabilities.dart';
import '../capability_gate.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../utils/playing_item.dart';
import '../../utils/api/get_liked.dart';
import '../../utils/api/set_liked.dart';

import '../rune_clickable.dart';

class LikeButton extends StatefulWidget {
  final PlayingItem? item;
  final Future<bool> Function(PlayingItem item)? fetchLikedStatus;
  final Future<bool> Function(PlayingItem item, bool liked)? setLikedStatus;

  const LikeButton({
    required this.item,
    this.fetchLikedStatus,
    this.setLikedStatus,
    super.key,
  });

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> {
  bool liked = false;
  bool _statusReady = false;
  late PlayingItem? item;
  int _requestGeneration = 0;
  final Map<PlayingItem, Future<bool>> _pendingWrites = {};

  @override
  void initState() {
    super.initState();
    item = widget.item;
    _fetchLikedStatus();
  }

  @override
  void didUpdateWidget(covariant LikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item != widget.item) {
      item = widget.item;
      liked = false;
      _fetchLikedStatus();
    }
  }

  Future<void> _fetchLikedStatus() async {
    final generation = ++_requestGeneration;
    final requestItem = item;
    _statusReady = false;
    if (requestItem == null) return;

    try {
      final isLiked =
          await (widget.fetchLikedStatus?.call(requestItem) ??
              getLiked(requestItem));
      if (mounted && generation == _requestGeneration) {
        setState(() {
          liked = isLiked;
          _statusReady = !_pendingWrites.containsKey(requestItem);
        });
      }
    } on RequestFailure catch (error) {
      if (error.kind != RequestErrorKind.notFound &&
          error.kind != RequestErrorKind.unavailable) {
        rethrow;
      }
    }
  }

  Future<void> _toggleLikedStatus() async {
    final requestItem = item;
    if (requestItem == null || !_statusReady) return;
    final generation = ++_requestGeneration;
    final desired = !liked;
    setState(() => liked = desired);

    // Keep rapid taps in order even when native requests finish at different times.
    final previous = _pendingWrites[requestItem];
    final write = previous == null
        ? Future<bool>.sync(
            () => (widget.setLikedStatus ?? setLiked)(requestItem, desired),
          )
        : previous.then(
            (_) => (widget.setLikedStatus ?? setLiked)(requestItem, desired),
            onError: (Object _, StackTrace _) =>
                (widget.setLikedStatus ?? setLiked)(requestItem, desired),
          );
    _pendingWrites[requestItem] = write;
    var failed = false;
    try {
      final committed = await write;
      if (mounted && generation == _requestGeneration) {
        setState(() => liked = committed);
      }
    } catch (_) {
      failed = true;
      rethrow;
    } finally {
      if (identical(_pendingWrites[requestItem], write)) {
        _pendingWrites.remove(requestItem);
        if (mounted &&
            item == requestItem &&
            (failed || generation != _requestGeneration)) {
          // Returning to an item may have read it before this write committed.
          await _fetchLikedStatus();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (item == null ||
        context.watch<LibraryOpenStateProvider>().isReadOnlyReplica) {
      return const SizedBox.shrink();
    }
    return CapabilityGate(
      capability: capabilityForRequest(
        context,
        (capabilities) => capabilities.setLikedRequest,
      ),
      child: RuneClickable(
        onPressed: !_statusReady
            ? null
            : () {
                _toggleLikedStatus();
              },
        iconSize: 13,
        padding: 0,
        isTiny: true,
        child: Icon(Symbols.favorite, fill: liked ? 1 : 0),
      ),
    );
  }
}
