import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/typography.dart';
import '../../../models/channel.dart';
import '../../../models/iptv_playlist.dart';
import '../../../providers/iptv_providers.dart';
import '../../../providers/theme_provider.dart';
import '../../../services/playback/playback_session.dart';

/// Quick 3-column category jump bottom sheet replicating `action_tab` (`res/F4.xml`, `context.md` §7.2).
class IptvTabJumpSheet extends ConsumerWidget {
  final List<IptvGroupedCategory> categories;
  final String activeCategoryTitle;
  final ValueChanged<int> onSelectTabIndex;

  const IptvTabJumpSheet({
    super.key,
    required this.categories,
    required this.activeCategoryTitle,
    required this.onSelectTabIndex,
  });

  static Future<void> show(
    BuildContext context, {
    required List<IptvGroupedCategory> categories,
    required String activeCategoryTitle,
    required ValueChanged<int> onSelectTabIndex,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => IptvTabJumpSheet(
        categories: categories,
        activeCategoryTitle: activeCategoryTitle,
        onSelectTabIndex: onSelectTabIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final settings = ref.watch(iptvSettingsProvider);
    final size = MediaQuery.sizeOf(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.78),
      decoration: BoxDecoration(
        color: themeMode.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: themeMode.dividerColor)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: themeMode.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Categories',
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: themeMode.onSurfaceColor,
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(iptvSettingsProvider.notifier).toggleSortCategoriesByCount();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: settings.sortCategoriesByCount
                        ? accentColor.color.withAlpha(30)
                        : themeMode.cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: settings.sortCategoriesByCount
                          ? accentColor.color
                          : themeMode.dividerColor,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        size: 15,
                        color: settings.sortCategoriesByCount
                            ? accentColor.color
                            : themeMode.onSurfaceMutedColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        settings.sortCategoriesByCount ? 'By Count' : 'Default Order',
                        style: TextStyle(
                          fontFamily: GoPlayType.family,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: settings.sortCategoriesByCount
                              ? accentColor.color
                              : themeMode.onSurfaceMutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                mainAxisExtent: 62,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final group = categories[index];
                final isSelected =
                    group.title.toLowerCase() == activeCategoryTitle.toLowerCase();
                return InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).pop();
                    onSelectTabIndex(index);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accentColor.color.withAlpha(28)
                          : themeMode.cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? accentColor.color
                            : themeMode.dividerColor,
                        width: isSelected ? 1.4 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          group.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            color: isSelected ? accentColor.color : themeMode.onSurfaceColor,
                          ),
                        ),
                        Text(
                          '${group.count}',
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? accentColor.color
                                : themeMode.onSurfaceMutedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Bookmark Category Selector Dialog (`R.layout.dialog_category_selector` / `res/CE.xml`,
/// `context.md` §7.3).
/// Returns selected categories on Confirm, `null` if cancelled via back arrow, or `['All']`
/// automatically if dismissed by outside tap/back press (matching `ILIlilIi1i.onDismiss`).
class IptvCategorySelectorDialog extends ConsumerStatefulWidget {
  final Channel channel;

  const IptvCategorySelectorDialog({super.key, required this.channel});

  static Future<List<String>?> show(BuildContext context, Channel channel) {
    bool cancelledViaBackIcon = false;
    return showDialog<List<String>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          backgroundColor: theme.cardColor,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.dividerColor),
          ),
          child: _CategorySelectorWrapper(
            channel: channel,
            onCancelBack: () {
              cancelledViaBackIcon = true;
              Navigator.of(ctx).pop(const <String>[]);
            },
            onConfirm: (selected) {
              Navigator.of(ctx).pop(selected);
            },
          ),
        );
      },
    ).then((result) {
      if (cancelledViaBackIcon) return null;
      // Outside/system-back dismissal defaults to auto-save in ['All'] (`context.md` §7.3)
      if (result == null) return const ['All'];
      if (result.isEmpty) return null;
      return result;
    });
  }

  @override
  ConsumerState<IptvCategorySelectorDialog> createState() =>
      _IptvCategorySelectorDialogState();
}

class _CategorySelectorWrapper extends StatelessWidget {
  final Channel channel;
  final VoidCallback onCancelBack;
  final ValueChanged<List<String>> onConfirm;

  const _CategorySelectorWrapper({
    required this.channel,
    required this.onCancelBack,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return _IptvCategorySelectorBody(
      channel: channel,
      onCancelBack: onCancelBack,
      onConfirm: onConfirm,
    );
  }
}

class _IptvCategorySelectorDialogState
    extends ConsumerState<IptvCategorySelectorDialog> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _IptvCategorySelectorBody extends ConsumerStatefulWidget {
  final Channel channel;
  final VoidCallback onCancelBack;
  final ValueChanged<List<String>> onConfirm;

  const _IptvCategorySelectorBody({
    required this.channel,
    required this.onCancelBack,
    required this.onConfirm,
  });

  @override
  ConsumerState<_IptvCategorySelectorBody> createState() =>
      _IptvCategorySelectorBodyState();
}

class _IptvCategorySelectorBodyState
    extends ConsumerState<_IptvCategorySelectorBody> {
  final Set<String> _selected = <String>{'All'};
  bool _rememberChoice = false;
  final _newCategoryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(iptvSettingsProvider);
    _rememberChoice = settings.rememberBookmarkChoice;
    _selected.addAll(settings.rememberedCategories);
  }

  @override
  void dispose() {
    _newCategoryController.dispose();
    super.dispose();
  }

  Future<void> _showManageCategoriesDialog() async {
    final themeMode = ref.read(activeThemeModeProvider);
    final accentColor = ref.read(activeAccentColorProvider);

    await showDialog<void>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final cats = ref.watch(iptvSettingsProvider).bookmarkCategories;
          return AlertDialog(
            backgroundColor: themeMode.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: themeMode.dividerColor),
            ),
            title: Text(
              'Manage Bookmark Categories',
              style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newCategoryController,
                          style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'New category name',
                            hintStyle: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 12),
                            isDense: true,
                            filled: true,
                            fillColor: themeMode.cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: themeMode.dividerColor),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.add_circle_rounded, color: accentColor.color),
                        onPressed: () {
                          final name = _newCategoryController.text.trim();
                          if (name.isNotEmpty) {
                            ref.read(iptvSettingsProvider.notifier).addBookmarkCategory(name);
                            _newCategoryController.clear();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: cats.length,
                      itemBuilder: (c, i) {
                        final cat = cats[i];
                        final isAll = cat.toLowerCase() == 'all';
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(cat, style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 13.5)),
                          trailing: isAll
                              ? Icon(Icons.lock_outline_rounded, size: 16, color: themeMode.onSurfaceMutedColor)
                              : IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      size: 18, color: Color(0xFFFF6B6B)),
                                  onPressed: () {
                                    ref.read(iptvSettingsProvider.notifier).removeBookmarkCategory(cat);
                                    _selected.remove(cat);
                                  },
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('DONE', style: TextStyle(color: accentColor.color)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final categories = ref.watch(iptvSettingsProvider).bookmarkCategories;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: themeMode.onSurfaceColor, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: widget.onCancelBack,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Save "${widget.channel.name}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: themeMode.onSurfaceColor,
                  ),
                ),
              ),
              TextButton(
                onPressed: _showManageCategoriesDialog,
                child: Text(
                  'Manage',
                  style: TextStyle(color: accentColor.color, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final cat = categories[i];
                final isAll = cat.toLowerCase() == 'all';
                final checked = isAll || _selected.contains(cat);
                return CheckboxListTile(
                  value: checked,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: accentColor.color,
                  checkColor: accentColor.onAccentColor,
                  title: Text(
                    cat,
                    style: TextStyle(color: themeMode.onSurfaceColor, fontSize: 13.5),
                  ),
                  onChanged: isAll
                      ? null
                      : (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(cat);
                            } else {
                              _selected.remove(cat);
                            }
                          });
                        },
                );
              },
            ),
          ),
          Divider(color: themeMode.dividerColor),
          InkWell(
            onTap: () => setState(() => _rememberChoice = !_rememberChoice),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Checkbox(
                  value: _rememberChoice,
                  activeColor: accentColor.color,
                  checkColor: accentColor.onAccentColor,
                  onChanged: (v) => setState(() => _rememberChoice = v ?? false),
                ),
                Expanded(
                  child: Text(
                    'Remember my choice next time',
                    style: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              final list = _selected.toList();
              if (!list.any((e) => e.toLowerCase() == 'all')) {
                list.add('All');
              }
              await ref.read(iptvSettingsProvider.notifier).saveBookmarkChoice(
                    remember: _rememberChoice,
                    categories: list,
                  );
              widget.onConfirm(list);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor.color,
              foregroundColor: accentColor.onAccentColor,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'CONFIRM',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Long-press `EpgInfoBottomSheet` (`R.layout.dialog_epg_info_bottom_sheet` / `res/2o.xml`,
/// `context.md` §8.2) constrained to 70% max screen height, showing Upcoming/Live before Past
/// programmes along with full stream metadata & playback actions.
class IptvEpgInfoBottomSheet extends ConsumerWidget {
  final Channel channel;
  final List<IptvEpgProgramme> programmes;
  final VoidCallback onPlay;

  const IptvEpgInfoBottomSheet({
    super.key,
    required this.channel,
    required this.programmes,
    required this.onPlay,
  });

  static Future<void> show(
    BuildContext context, {
    required Channel channel,
    required List<IptvEpgProgramme> programmes,
    required VoidCallback onPlay,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => IptvEpgInfoBottomSheet(
        channel: channel,
        programmes: programmes,
        onPlay: onPlay,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final now = DateTime.now();
    final timeFmt = DateFormat('HH:mm');
    final size = MediaQuery.sizeOf(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    // Partition upcoming/live programmes before past programmes (`context.md` §8.2)
    final upcoming = programmes.where((p) => p.isUpcomingAt(now)).toList();
    final past = programmes.where((p) => !p.isUpcomingAt(now)).toList();
    final ordered = [...upcoming, ...past];

    return Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.70),
      decoration: BoxDecoration(
        color: themeMode.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: themeMode.dividerColor)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: themeMode.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(4),
                child: channel.logo != null && channel.logo!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: channel.logo!,
                        fit: BoxFit.contain,
                        errorWidget: (_, _, _) => Center(
                          child: Text(
                            channel.initials,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          channel.initials,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: themeMode.onSurfaceColor,
                      ),
                    ),
                    Text(
                      'Item information • ${channel.category ?? "Undefined"}',
                      style: TextStyle(
                        fontFamily: GoPlayType.family,
                        fontSize: 12,
                        color: themeMode.onSurfaceMutedColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.info_outline_rounded, color: accentColor.color),
                tooltip: 'Channel Metadata',
                onPressed: () {
                  Navigator.of(context).pop();
                  IptvChannelInfoListSheet.show(context, channel);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: themeMode.dividerColor),
          const SizedBox(height: 10),

          Flexible(
            child: ordered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tv_off_rounded,
                            color: themeMode.onSurfaceMutedColor, size: 34),
                        const SizedBox(height: 8),
                        Text(
                          'No TV guide available',
                          style: TextStyle(
                            fontFamily: GoPlayType.family,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: themeMode.onSurfaceMutedColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          channel.streamUrl,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: themeMode.onSurfaceMutedColor.withAlpha(140),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: ordered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final p = ordered[idx];
                      final isLive = p.isLiveAt(now);
                      final isUpcoming = !isLive && p.isUpcomingAt(now);
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isLive
                              ? const Color(0xFF1A2622)
                              : themeMode.cardColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isLive
                                ? const Color(0xFF32D74B)
                                : themeMode.dividerColor,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isLive
                                        ? const Color(0x2232D74B)
                                        : isUpcoming
                                            ? const Color(0x22FFD54F)
                                            : themeMode.dividerColor.withAlpha(80),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${timeFmt.format(p.startTime)} - ${timeFmt.format(p.stopTime)}',
                                    style: TextStyle(
                                      fontFamily: GoPlayType.family,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: isLive
                                          ? const Color(0xFF32D74B)
                                          : isUpcoming
                                              ? const Color(0xFFFFD54F)
                                              : themeMode.onSurfaceMutedColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isLive)
                                  const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF32D74B),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              p.title,
                              style: TextStyle(
                                fontFamily: GoPlayType.family,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: themeMode.onSurfaceColor,
                              ),
                            ),
                            if (p.description != null && p.description!.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                p.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: themeMode.onSurfaceMutedColor,
                                ),
                              ),
                            ],
                            if (isLive) ...[
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: p.progressAt(now),
                                  minHeight: 3,
                                  backgroundColor: themeMode.dividerColor,
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF32D74B),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: channel.streamUrl));
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Stream URL copied to clipboard'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('COPY URL'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: themeMode.onSurfaceColor,
                    side: BorderSide(color: themeMode.dividerColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onPlay();
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('PLAY NOW'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor.color,
                    foregroundColor: accentColor.onAccentColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Raw channel metadata sheet replicating `R.layout.dialog_info_list` (`res/RQ.xml` + `res/M-.xml`),
/// launched from the `@id/infoItems` button in List view (`context.md` §6.1).
class IptvChannelInfoListSheet extends ConsumerWidget {
  final Channel channel;

  const IptvChannelInfoListSheet({super.key, required this.channel});

  static Future<void> show(BuildContext context, Channel channel) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => IptvChannelInfoListSheet(channel: channel),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final entries = <MapEntry<String, String>>[
      MapEntry('Title', channel.name),
      MapEntry('Group', channel.category ?? 'Undefined'),
      if (channel.tvgId != null && channel.tvgId!.isNotEmpty)
        MapEntry('TVG ID', channel.tvgId!),
      if (channel.tvgUrl != null && channel.tvgUrl!.isNotEmpty)
        MapEntry('TVG URL', channel.tvgUrl!),
      MapEntry('Stream URL', channel.streamUrl),
      if (channel.hasDrm) ...[
        MapEntry('DRM Scheme', channel.drm!.type.name),
        if (channel.drm?.manifestType != null)
          MapEntry('Manifest Type', channel.drm!.manifestType!),
        if (channel.drm?.kid != null) MapEntry('Key ID (KID)', channel.drm!.kid!),
        if (channel.drm?.key != null) MapEntry('DRM Key', channel.drm!.key!),
        if (channel.drm?.licenseUrl != null)
          MapEntry('License URL', channel.drm!.licenseUrl!),
      ],
      for (final h in channel.headers.entries)
        MapEntry('Header: ${h.key}', h.value.toString()),
    ];

    final size = MediaQuery.sizeOf(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.72),
      decoration: BoxDecoration(
        color: themeMode.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: themeMode.dividerColor)),
      ),
      padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: themeMode.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Stream Information',
            style: TextStyle(
              fontFamily: GoPlayType.family,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: themeMode.onSurfaceColor,
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: entries.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: themeMode.dividerColor),
              itemBuilder: (context, idx) {
                final item = entries[idx];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 105,
                        child: Text(
                          item.key,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: themeMode.onSurfaceMutedColor,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          item.value,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: themeMode.onSurfaceColor,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.copy_rounded,
                            size: 16, color: accentColor.color),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: item.value));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${item.key} copied'),
                                duration: const Duration(seconds: 1),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Bookmarks viewer & category filter sheet accessible from the `/iptv` page.
class IptvBookmarksSheet extends ConsumerStatefulWidget {
  final Future<void> Function(Channel ch, List<Channel> scope) onPlayChannel;

  const IptvBookmarksSheet({super.key, required this.onPlayChannel});

  static Future<void> show(
    BuildContext context, {
    required Future<void> Function(Channel ch, List<Channel> scope) onPlayChannel,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => IptvBookmarksSheet(onPlayChannel: onPlayChannel),
    );
  }

  @override
  ConsumerState<IptvBookmarksSheet> createState() => _IptvBookmarksSheetState();
}

class _IptvBookmarksSheetState extends ConsumerState<IptvBookmarksSheet> {
  String _selectedCat = 'All';

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(activeThemeModeProvider);
    final accentColor = ref.watch(activeAccentColorProvider);
    final bookmarksMap = ref.watch(iptvBookmarksProvider);
    final categories = ref.watch(iptvSettingsProvider).bookmarkCategories;
    final items = bookmarksMap.values.where((b) {
      if (_selectedCat.toLowerCase() == 'all') return true;
      return b.categories.any((c) => c.toLowerCase() == _selectedCat.toLowerCase());
    }).toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));

    final size = MediaQuery.sizeOf(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: size.height * 0.80),
      decoration: BoxDecoration(
        color: themeMode.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: themeMode.dividerColor)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: themeMode.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Icon(Icons.bookmarks_rounded, color: accentColor.color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bookmarked Channels (${bookmarksMap.length})',
                  style: TextStyle(
                    fontFamily: GoPlayType.family,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: themeMode.onSurfaceColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final cat = categories[idx];
                final selected = cat.toLowerCase() == _selectedCat.toLowerCase();
                return ChoiceChip(
                  label: Text(cat),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedCat = cat),
                  selectedColor: accentColor.color,
                  backgroundColor: themeMode.cardColor,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? accentColor.onAccentColor : themeMode.onSurfaceMutedColor,
                  ),
                  side: BorderSide(
                    color: selected ? accentColor.color : themeMode.dividerColor,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Text(
                        'No bookmarked IPTV channels yet.\nTap the heart icon on any channel to save it here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: themeMode.onSurfaceMutedColor, fontSize: 13),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final bm = items[idx];
                      final ch = bm.channel;
                      final scope = items.map((e) => e.channel).toList();
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onPlayChannel(ch, scope);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: themeMode.cardColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: themeMode.dividerColor),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.all(4),
                                child: ch.logo != null && ch.logo!.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: ch.logo!,
                                        fit: BoxFit.contain,
                                        errorWidget: (_, _, _) => Center(
                                          child: Text(
                                            ch.initials,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          ch.initials,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ch.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: themeMode.onSurfaceColor,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${bm.playlistName} • ${bm.categories.join(", ")}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: themeMode.onSurfaceMutedColor,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Color(0xFFFF6B6B),
                                  size: 20,
                                ),
                                onPressed: () => ref
                                    .read(iptvBookmarksProvider.notifier)
                                    .removeBookmark(ch.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shared channel launcher helper for IPTV screens — resolves lazy Stalker /
/// remote ClearKey JSON endpoints before pushing `PlayerScreen` cleanly.
Future<void> launchIptvChannelPlayback(
  BuildContext context,
  WidgetRef ref, {
  required Channel channel,
  required List<Channel> scopeChannels,
}) async {
  HapticFeedback.selectionClick();
  final service = ref.read(iptvServiceProvider);

  if (PlaybackSessionCoordinator.needsIptvResolution(channel) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connecting to "${channel.name}"...'),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  final args = await const PlaybackSessionCoordinator().prepareIptvLaunch(
    channel,
    scopeChannels: scopeChannels,
    iptvService: service,
  );
  if (!context.mounted) return;

  await context.push(args.routeLocation, extra: args.toExtra());
}
