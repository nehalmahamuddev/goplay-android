import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Central catalog of modern SVG icon asset identifiers for the IPTV screen
/// sourced via allsvgicons MCP (Lucide / Tabler premium icons).
abstract final class IptvSvgIcons {
  static const String search = 'search';
  static const String help = 'help';
  static const String microchip = 'microchip';
  static const String sliders = 'sliders';
  static const String tv = 'tv';
  static const String settings = 'settings';
  static const String telegram = 'telegram';
  static const String dragHandle = 'drag_handle';
  static const String link = 'link';
  static const String moreVertical = 'more_vertical';
  static const String menu = 'menu';
  static const String refresh = 'refresh';
  static const String edit = 'edit';
  static const String copy = 'copy';
  static const String download = 'download';
  static const String epg = 'epg';
  static const String info = 'info';
  static const String delete = 'delete';
  static const String plus = 'plus';
  static const String check = 'check';
  static const String close = 'close';
  static const String tvPlay = 'tv_play';
  static const String playlistPlay = 'playlist_play';
  static const String addPlaylist = 'add_playlist';
  static const String videoLink = 'video_link';
  static const String folderOpen = 'folder_open';
  static const String monitor = 'monitor';
  static const String laptop = 'laptop';
  static const String chevronRight = 'chevron_right';
  static const String arrowLeft = 'arrow_left';
  static const String layoutGrid = 'layout_grid';
  static const String layoutList = 'layout_list';
  static const String heart = 'heart';
  static const String heartFilled = 'heart_filled';
  static const String play = 'play';
  static const String share = 'share';
  static const String sort = 'sort';
  static const String checkSquare = 'check_square';
}

/// Renders a modern vector SVG icon from `assets/icons/iptv/`.
class IptvSvgIcon extends StatelessWidget {
  final String icon;
  final double size;
  final Color? color;
  final String? semanticsLabel;

  const IptvSvgIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/iptv/$icon.svg',
      width: size,
      height: size,
      semanticsLabel: semanticsLabel,
      colorFilter: color != null ? ColorFilter.mode(color!, BlendMode.srcIn) : null,
    );
  }
}
