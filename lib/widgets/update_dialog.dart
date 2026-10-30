import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/typography.dart';
import '../models/app_theme_options.dart';
import '../providers/theme_provider.dart';
import '../providers/update_notifier.dart';

class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false, // Must not dismiss by clicking outside
      builder: (context) => const UpdateDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateState = ref.watch(updateProvider);
    final notifier = ref.read(updateProvider.notifier);
    final isForce = updateState.isForceUpdate;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final themeMode = ref.watch(activeThemeModeProvider);

    // Use PopScope to prevent back button dismissals on force update
    return PopScope(
      canPop: !isForce,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
        // GPU-safe: no BackdropFilter (crashes budget TV GPUs like Mali-G31)
        child: Container(
          decoration: BoxDecoration(
            color: themeMode.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: isForce ? cs.error : cs.primary,
                      ),
                      child: Icon(
                        Icons.system_update_rounded,
                        color: isForce ? cs.onError : cs.onPrimary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isForce ? 'CRITICAL UPDATE' : 'UPDATE AVAILABLE',
                            style: TextStyle(
                              fontFamily: GoPlayType.family,
                              fontSize: GoPlayType.md,
                              fontWeight: FontWeight.w800,
                              color: isForce ? cs.error : cs.primary,
                              height: GoPlayType.leadingSnug,
                              letterSpacing: 1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isForce ? 'You must update to continue' : 'A new version is ready',
                            style: GoPlayType.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                Container(
                  margin: const EdgeInsets.symmetric(vertical: 20),
                  height: 1,
                  color: themeMode.dividerColor,
                ),

                // Dynamic Body based on download/check status
                _buildDialogBody(context, updateState, cs),

                const SizedBox(height: 24),

                // Action Buttons
                _buildActionButtons(context, updateState, notifier, cs, themeMode),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogBody(BuildContext context, UpdateState state, ColorScheme cs) {
    switch (state.status) {
      case UpdateStatus.downloading:
        return Column(
          children: [
            Text(
              'Downloading update package...',
              style: GoPlayType.body.copyWith(
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: state.downloadProgress,
                backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(state.downloadProgress * 100).toStringAsFixed(0)}%',
                  style: GoPlayType.labelSmall.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                  maxLines: 1,
                ),
                Text(
                  'Please keep the app open',
                  style: GoPlayType.inter(
                    fontSize: GoPlayType.xs,
                    height: GoPlayType.leadingSnug,
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        );

      case UpdateStatus.installing:
        return Column(
          children: [
            SizedBox(
              height: 36,
              width: 36,
              child: CircularProgressIndicator(
                color: cs.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Launching package installer...',
              textAlign: TextAlign.center,
              style: GoPlayType.body.copyWith(
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
          ],
        );

      case UpdateStatus.downloadFailed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline_rounded, color: cs.error, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Download Failed',
                  style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.w700,
                    fontSize: GoPlayType.base,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                state.errorMessage ??
                    'An unexpected network error occurred while downloading the APK file. Please check your connection.',
                style: GoPlayType.bodySmall.copyWith(
                  color: cs.onSurface,
                ),
                // errorMessage comes off the wire and can be arbitrarily long.
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );

      default:
        // Shows details (release notes & version metadata)
        final info = state.updateInfo;
        if (info == null) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Versions and dates info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoTile('CURRENT', state.currentVersion, cs),
                _buildInfoTile('LATEST', info.latestVersion, cs, isHighlight: true),
                _buildInfoTile(
                  'PUBLISHED',
                  DateFormat('MMM dd, yyyy').format(info.publishedAt),
                  cs,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Release Notes Header
            Text(
              'WHAT\'S NEW',
              style: GoPlayType.meta.copyWith(
                color: cs.onSurfaceVariant,
                letterSpacing: GoPlayType.trackingWide,
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 8),

            // Release Notes list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 130),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: info.releaseNotes.map((note) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '• ',
                              style: TextStyle(
                                fontFamily: GoPlayType.family,
                                color: cs.primary,
                                fontSize: GoPlayType.base,
                                fontWeight: FontWeight.w700,
                                height: GoPlayType.leadingBody,
                              ),
                            ),
                            Expanded(
                              // Release notes are server-supplied and of
                              // unbounded length; cap them so a long note
                              // cannot blow out the 130px scroll region.
                              child: Text(
                                note,
                                style: GoPlayType.body.copyWith(
                                  color: cs.onSurface,
                                ),
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildInfoTile(String label, String value, ColorScheme cs, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoPlayType.meta.copyWith(
            color: cs.onSurfaceVariant,
            letterSpacing: 0.5,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoPlayType.inter(
            fontSize: GoPlayType.base,
            fontWeight: FontWeight.w800,
            height: GoPlayType.leadingSnug,
            color: isHighlight ? cs.primary : cs.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    UpdateState state,
    UpdateNotifier notifier,
    ColorScheme cs,
    AppThemeMode themeMode,
  ) {
    final isForce = state.isForceUpdate;

    if (state.status == UpdateStatus.downloading) {
      return TextButton.icon(
        onPressed: () {
          notifier.cancelDownload();
        },
        icon: Icon(Icons.cancel_rounded, color: cs.error, size: 18),
        label: const Text('CANCEL DOWNLOAD'),
        style: TextButton.styleFrom(
          foregroundColor: cs.error,
          backgroundColor: cs.error.withValues(alpha: 0.12),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontFamily: GoPlayType.family,
            fontSize: GoPlayType.sm,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    if (state.status == UpdateStatus.installing) {
      return const SizedBox.shrink(); // Prevent actions during installation request
    }

    if (state.status == UpdateStatus.downloadFailed) {
      return Row(
        children: [
          if (!isForce)
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  notifier.resetStatus();
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeMode.surfaceContainerHigh,
                  foregroundColor: cs.onSurfaceVariant,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: GoPlayType.base,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                child: const Text('LATER'),
              ),
            ),
          if (!isForce) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                notifier.retryDownload();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                elevation: 0,
                shadowColor: Colors.transparent,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: GoPlayType.base,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              child: const Text('RETRY DOWNLOAD'),
            ),
          ),
        ],
      );
    }

    if (state.status == UpdateStatus.downloadSuccess) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.errorMessage != null) ...[
            Text(
              state.errorMessage!,
              style: GoPlayType.bodySmall.copyWith(color: cs.error),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              if (!isForce)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      notifier.resetStatus();
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeMode.surfaceContainerHigh,
                      foregroundColor: cs.onSurfaceVariant,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: GoPlayType.base,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    child: const Text('LATER'),
                  ),
                ),
              if (!isForce) const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    notifier.installApk();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                      fontFamily: GoPlayType.family,
                      fontSize: GoPlayType.base,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  child: const Text('INSTALL NOW'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // Default Update Available buttons
    return Row(
      children: [
        if (!isForce)
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: themeMode.surfaceContainerHigh,
                foregroundColor: cs.onSurfaceVariant,
                elevation: 0,
                shadowColor: Colors.transparent,
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                  fontFamily: GoPlayType.family,
                  fontSize: GoPlayType.base,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              child: const Text('LATER'),
            ),
          ),
        if (!isForce) const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            autofocus: true, // TV remote: auto-focus primary action
            onPressed: () {
              notifier.startDownload();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              elevation: 0,
              shadowColor: Colors.transparent,
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                fontFamily: GoPlayType.family,
                fontSize: GoPlayType.base,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            child: const Text('UPDATE NOW'),
          ),
        ),
      ],
    );
  }
}
