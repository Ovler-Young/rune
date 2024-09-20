import 'package:fluent_ui/fluent_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../messages/playback.pb.dart';

class PlayPauseButton extends StatelessWidget {
  final bool disabled;

  final String state;

  const PlayPauseButton(
      {required this.disabled, required this.state, super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: disabled
          ? null
          : () {
              switch (state) {
                case "Paused":
                case "Stopped":
                  PlayRequest().sendSignalToRust(); // GENERATED
                  break;
                case "Playing":
                  PauseRequest().sendSignalToRust(); // GENERATED
                  break;
              }
            },
      icon: state == "Playing"
          ? const Icon(Symbols.pause)
          : const Icon(Symbols.play_arrow),
    );
  }
}