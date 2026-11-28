import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/typography.dart';
import '../services/tv_service.dart';
import 'tv_focus_wrapper.dart';

/// Shows a centered D-Pad-friendly [Dialog] when running on Android TV,
/// or a standard [showModalBottomSheet] on mobile/touch devices.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  double maxDialogWidth = 540,
}) {
  final isTv = TvScope.isTvOf(context);
  if (!isTv) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: backgroundColor,
      shape: shape,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useSafeArea: useSafeArea,
      builder: builder,
    );
  }

  final theme = Theme.of(context);
  final bg = backgroundColor ?? theme.colorScheme.surfaceContainer;
  final screenSize = MediaQuery.sizeOf(context);

  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: FocusTraversalGroup(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: screenSize.height * 0.86,
            ),
            child: Material(
              color: bg,
              shape: shape is RoundedRectangleBorder
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Color(0x1FFFFFFF), width: 1),
                    )
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Color(0x1FFFFFFF), width: 1),
                    ),
              clipBehavior: Clip.antiAlias,
              child: builder(dialogContext),
            ),
          ),
        ),
      );
    },
  );
}

/// Opens [url] externally, falling back to a D-Pad-friendly dialog with
/// a copyable URL when no browser app is installed (common on Android TV).
Future<void> launchUrlWithTvFallback(
  BuildContext context,
  String url, {
  String title = 'Open Link',
  String? description,
}) async {
  final uri = Uri.tryParse(url);
  bool launched = false;
  if (uri != null) {
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
  }
  if (launched || !context.mounted) return;

  final theme = Theme.of(context);
  final cs = theme.colorScheme;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: GoPlayType.family,
          color: cs.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (description != null && description.isNotEmpty) ...[
              Text(
                description,
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'No web browser is available on this device. Open this address on your phone or PC:',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                color: cs.onSurfaceVariant,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
              ),
              child: SelectableText(
                url,
                style: TextStyle(
                  fontFamily: GoPlayType.family,
                  color: cs.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TvFocusable(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              'COPY LINK',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                color: cs.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
        TvFocusable(
          autoFocus: true,
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(ctx).pop(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'CLOSE',
              style: TextStyle(
                fontFamily: GoPlayType.family,
                color: cs.onPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Handles D-Pad directional exits out of a single-line [TextField] so TV
/// remote users are never trapped inside a text input.
KeyEventResult handleTvTextFieldKeyEvent(
  FocusNode node,
  KeyEvent event,
  BuildContext context, {
  VoidCallback? onSubmit,
}) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final key = event.logicalKey;

  if (key == LogicalKeyboardKey.arrowDown) {
    FocusScope.of(context).focusInDirection(TraversalDirection.down);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowUp) {
    FocusScope.of(context).focusInDirection(TraversalDirection.up);
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.escape) {
    node.unfocus();
    return KeyEventResult.handled;
  }
  if ((key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.numpadEnter) &&
      onSubmit != null) {
    onSubmit();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
