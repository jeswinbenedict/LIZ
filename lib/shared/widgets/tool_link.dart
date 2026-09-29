import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/link.dart';

import '../models/tool.dart';

/// The address of a tool's page: `/tools/elevenlabs`.
///
/// A slug reads as a place and survives being pasted into a chat; the UUID it
/// replaced (`/#/tool/c41c48aa-…`) did neither. `/tool/<id>` still resolves,
/// for links already shared and for notifications that carry only an id.
String toolPath(Tool tool) => tool.slug.isEmpty
    ? '/tool/${tool.id}'
    : '/tools/${Uri.encodeComponent(tool.slug)}';

/// Makes a tool card a real link on the web: an `<a>` the browser knows
/// about, so it can be opened in a new tab, middle-clicked, or copied, and
/// shows its address on hover.
///
/// A plain click still pushes onto the app's own stack, so Back returns to
/// the list where it was. Following the link instead would replace the whole
/// stack and lose the reader's place. With Cmd, Ctrl or Shift held, the
/// browser does what it normally does with a link.
class ToolLink extends StatelessWidget {
  const ToolLink({
    super.key,
    required this.tool,
    required this.builder,
    this.replace = false,
  });

  final Tool tool;

  /// Builds the tappable surface. Call `open` from its tap handler.
  final Widget Function(BuildContext context, VoidCallback open) builder;

  /// Replace the current page rather than push, for hopping between related
  /// tools without building a deep back stack.
  final bool replace;

  @override
  Widget build(BuildContext context) {
    final path = toolPath(tool);
    return Link(
      uri: Uri(path: path),
      builder: (context, follow) => builder(context, () {
        final keys = HardwareKeyboard.instance;
        final newTab =
            keys.isMetaPressed || keys.isControlPressed || keys.isShiftPressed;
        if (newTab && follow != null) {
          follow();
        } else if (replace) {
          context.replace(path);
        } else {
          context.push(path);
        }
      }),
    );
  }
}
