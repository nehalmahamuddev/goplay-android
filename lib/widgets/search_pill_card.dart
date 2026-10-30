import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/theme.dart';
import '../core/typography.dart';

/// Exact upstream vector SVG from D:\Poject\upstream\app\src\main\res\drawable\search_icon.xml
const String _kUpstreamSearchSvg = '''
<svg viewBox="0 0 850 850" width="24" height="24" xmlns="http://www.w3.org/2000/svg">
  <path d="M 425.2 172.91 C 363.2 172.91 303.676 197.566 259.836 241.406 C 215.996 285.246 191.34 344.77 191.34 406.77 C 191.34 468.77 215.996 528.294 259.836 572.134 C 303.676 615.974 363.2 640.63 425.2 640.63 C 487.2 640.63 546.724 615.974 590.564 572.134 C 634.404 528.294 659.06 468.77 659.06 406.77 C 659.06 344.77 634.404 285.246 590.564 241.406 C 546.724 197.566 487.2 172.91 425.2 172.91 Z" fill="none" stroke="#ffffff" stroke-width="60" stroke-miterlimit="10"/>
  <path d="M 583.631 547.663 L 583.624 547.67 C 587.388 543.906 592.078 541.198 597.22 539.82 C 602.363 538.442 607.778 538.442 612.92 539.82 C 618.063 541.198 622.752 543.906 626.517 547.67 L 719.049 640.202 C 722.813 643.966 725.521 648.656 726.899 653.798 C 728.277 658.941 728.277 664.356 726.899 669.498 C 725.521 674.641 722.813 679.331 719.049 683.095 L 719.056 683.088 C 713.37 688.774 705.65 691.971 697.609 691.971 C 689.568 691.971 681.849 688.774 676.163 683.088 L 583.631 590.556 C 577.945 584.87 574.747 577.15 574.747 569.109 C 574.747 561.068 577.945 553.349 583.631 547.663" fill="#ffffff" stroke-width="1"/>
</svg>
''';

/// Upstream-styled search pill card component modeled after the library/folder search bar.
///
/// Specifications matching upstream (`fragment_library.xml` & `search_background.xml`):
/// - Height: 40dp
/// - Stadium border radius: 20dp
/// - Margins: 10dp
/// - Clean borderless surface container using global theme background color (cs.surface)
/// - Embedded search icon, clear button (✕), and filter list button with active indicator
/// - Entire pill is interactive and tap-to-focus responsive
class SearchPillCard extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final bool isFilterActive;
  final VoidCallback? onFilterTap;
  final Widget? leading;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final Color? fillColor;
  final Color? cursorColor;
  final String? filterTooltip;

  const SearchPillCard({
    super.key,
    required this.controller,
    required this.hintText,
    this.isFilterActive = false,
    this.onFilterTap,
    this.leading,
    this.onChanged,
    this.onClear,
    this.focusNode,
    this.height = 40.0,
    this.borderRadius = 20.0,
    this.margin,
    this.fillColor,
    this.cursorColor,
    this.filterTooltip,
  });

  @override
  State<SearchPillCard> createState() => _SearchPillCardState();
}

class _SearchPillCardState extends State<SearchPillCard> {
  FocusNode? _internalFocusNode;

  FocusNode get _effectiveFocusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void dispose() {
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveMargin = widget.margin ??
        EdgeInsets.fromLTRB(widget.leading != null ? 8 : 10, 6, 10, 8);

    return Padding(
      padding: effectiveMargin,
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: 4),
          ],
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _effectiveFocusNode.requestFocus(),
              child: Container(
                height: widget.height,
                decoration: BoxDecoration(
                  color: widget.fillColor ?? cs.surface,
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 10),
                    SvgPicture.string(
                      _kUpstreamSearchSvg,
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        cs.onSurfaceVariant.withValues(alpha: 0.7),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _effectiveFocusNode,
                        textInputAction: TextInputAction.search,
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: widget.onChanged,
                        cursorColor: widget.cursorColor ?? GoPlayTheme.primary,
                        cursorWidth: 2,
                        style: TextStyle(
                          fontFamily: GoPlayType.family,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: cs.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          hintStyle: TextStyle(
                            fontFamily: GoPlayType.family,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w400,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: widget.controller,
                      builder: (context, value, child) {
                        if (value.text.isEmpty) return const SizedBox.shrink();
                        return SizedBox(
                          width: 32,
                          height: widget.height,
                          child: IconButton(
                            tooltip: 'Clear search',
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.close_rounded,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                              size: 17,
                            ),
                            splashRadius: 16,
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              widget.controller.clear();
                              widget.onChanged?.call('');
                              widget.onClear?.call();
                              _effectiveFocusNode.requestFocus();
                            },
                          ),
                        );
                      },
                    ),
                    if (widget.onFilterTap != null)
                      SizedBox(
                        width: 36,
                        height: widget.height,
                        child: IconButton(
                          tooltip: widget.filterTooltip ?? 'Filter and sort',
                          padding: EdgeInsets.zero,
                          splashRadius: 18,
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                Icons.filter_list_rounded,
                                size: 20,
                                color: widget.isFilterActive
                                    ? GoPlayTheme.primary
                                    : cs.onSurfaceVariant.withValues(alpha: 0.8),
                              ),
                              if (widget.isFilterActive)
                                Positioned(
                                  top: -1,
                                  right: -1,
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: GoPlayTheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onPressed: widget.onFilterTap,
                        ),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
