import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'liquid_surface.dart';

class KumoneGlassSideNavigation extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<String> labels;
  final List<IconData> icons;
  final List<int> order;
  final bool expanded;
  final VoidCallback onExpand;
  final bool onLeft;
  final double scale;
  // Collapsed search and expanded panel deliberately have separate anchors.
  final double position;
  final double expandedPosition;
  final void Function(double position, bool onLeft)? onPositionChanged;

  const KumoneGlassSideNavigation(
      {super.key,
      required this.selectedIndex,
      required this.onChanged,
      required this.labels,
      required this.icons,
      this.order = const [3, 1, 0],
      this.expanded = true,
      required this.onExpand,
      this.onLeft = false,
      this.scale = 1,
      this.position = .8,
      this.expandedPosition = .8,
      this.onPositionChanged});

  @override
  State<KumoneGlassSideNavigation> createState() =>
      _KumoneGlassSideNavigationState();
}

class _KumoneGlassSideNavigationState extends State<KumoneGlassSideNavigation> {
  final _panelKey = GlobalKey();
  bool _scrubbing = false;
  bool _moved = false;
  int? _preview;
  double? _followY;
  Timer? _tapLift;
  bool _lifted = false;
  bool _positionDragging = false;
  Offset _dragOrigin = Offset.zero;
  Offset _startPosition = Offset.zero;
  Offset? _dragPosition;
  double _maxLeft = 0, _maxTop = 0;
  Offset _restingPosition = Offset.zero;

  @override
  void dispose() {
    _tapLift?.cancel();
    super.dispose();
  }

  void _previewAt(Offset global) {
    final box = _panelKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final cell = box.size.height / widget.order.length;
    final y = box
        .globalToLocal(global)
        .dy
        .clamp(cell / 2, box.size.height - cell / 2);
    final next =
        widget.order[(y / cell).floor().clamp(0, widget.order.length - 1)];
    if (next != _preview) HapticFeedback.selectionClick();
    setState(() {
      _preview = next;
      _followY = y;
    });
  }

  void _finish({bool canceled = false}) {
    final chosen = !canceled && _moved ? _preview : null;
    setState(() {
      _scrubbing = false;
      _moved = false;
      _preview = null;
      _followY = null;
    });
    if (chosen != null) widget.onChanged(chosen);
  }

  void _select(int index) {
    _tapLift?.cancel();
    setState(() {
      _preview = index;
      _lifted = true;
    });
    widget.onChanged(index);
    _tapLift = Timer(const Duration(milliseconds: 450), () {
      if (mounted) {
        setState(() {
          _lifted = false;
          _preview = null;
        });
      }
    });
  }

  void _positionStart(Offset global) {
    HapticFeedback.mediumImpact();
    setState(() {
      _positionDragging = true;
      _dragOrigin = global;
      _startPosition = _restingPosition;
      _dragPosition = _startPosition;
    });
  }

  void _positionMove(Offset global) {
    final next = _startPosition + global - _dragOrigin;
    setState(() => _dragPosition =
        Offset(next.dx.clamp(0, _maxLeft), next.dy.clamp(0, _maxTop)));
  }

  void _positionEnd({bool canceled = false}) {
    final position = _dragPosition;
    if (!canceled && position != null) {
      widget.onPositionChanged?.call(
          _maxTop == 0 ? 0 : position.dy / _maxTop, position.dx < _maxLeft / 2);
    }
    setState(() {
      _positionDragging = false;
      _dragPosition = null;
    });
  }

  Widget _gestures(Widget child, {required bool search}) => RawGestureDetector(
        // Do not replace the 200ms recognizer during expand-and-scrub.
        key: ValueKey(search ? widget.expanded && !_scrubbing : 'panel'),
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                  () => LongPressGestureRecognizer(
                      duration: search && !widget.expanded
                          ? const Duration(milliseconds: 200)
                          : const Duration(seconds: 1)), (recognizer) {
            recognizer
              ..onLongPressStart = (details) {
                if (search && !widget.expanded) {
                  setState(() {
                    _scrubbing = true;
                    _moved = false;
                  });
                  widget.onExpand();
                  HapticFeedback.selectionClick();
                } else {
                  _positionStart(details.globalPosition);
                }
              }
              ..onLongPressMoveUpdate = (details) {
                if (_positionDragging) {
                  _positionMove(details.globalPosition);
                } else if (_scrubbing &&
                    details.offsetFromOrigin.distance >= 8) {
                  _moved = true;
                  _previewAt(details.globalPosition);
                }
              }
              ..onLongPressEnd = (_) {
                if (_positionDragging) {
                  _positionEnd();
                } else {
                  _finish();
                }
              }
              ..onLongPressCancel = () {
                if (_positionDragging) {
                  _positionEnd(canceled: true);
                } else if (_scrubbing) {
                  _finish(canceled: true);
                }
              };
          }),
          if (!search)
            VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                    VerticalDragGestureRecognizer>(
                () => VerticalDragGestureRecognizer(), (recognizer) {
              recognizer
                ..onStart = (details) {
                  setState(() {
                    _scrubbing = true;
                    _moved = true;
                  });
                  _previewAt(details.globalPosition);
                }
                ..onUpdate = (details) {
                  _previewAt(details.globalPosition);
                }
                ..onEnd = (_) {
                  _finish();
                }
                ..onCancel = () {
                  _finish(canceled: true);
                };
            }),
        },
        child: child,
      );

  Widget _item(int index, double scale, double size, double cell) {
    final selected = (_preview ?? widget.selectedIndex) == index;
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.primary : scheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: ValueKey('floating-tab-$index'),
        borderRadius: BorderRadius.circular(size / 2),
        onTap: () => _select(index),
        child: SizedBox(
          width: size,
          height: cell,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(widget.icons[index], size: 26 * scale, color: foreground),
            SizedBox(height: 3 * scale),
            Text(widget.labels[index],
                maxLines: 1,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w600,
                    color: foreground)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duration = reduce || _positionDragging
        ? Duration.zero
        : const Duration(milliseconds: 280);
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (context, constraints) {
        final scale = math
            .min(widget.scale.clamp(.8, 1.4), constraints.maxHeight / 302)
            .clamp(.5, 1.4)
            .toDouble();
        final size = 60 * scale;
        final cell = 70 * scale;
        final panelHeight = cell * widget.order.length;
        final expanded = widget.expanded || _scrubbing;
        final groupHeight = size + 20 * scale + panelHeight;
        final height = expanded ? groupHeight : size;
        _maxLeft = math.max(0, constraints.maxWidth - size);
        _maxTop = math.max(0, constraints.maxHeight - height);
        _restingPosition = Offset(
            widget.onLeft ? 0 : _maxLeft,
            _maxTop *
                (expanded ? widget.expandedPosition : widget.position)
                    .clamp(0, 1));
        final position = _dragPosition ?? _restingPosition;
        final selected = widget.order.indexOf(_preview ?? widget.selectedIndex);
        final targetY = _followY ?? cell * ((selected < 0 ? 0 : selected) + .5);
        const optics = LiquidGlassTabPillStyle();
        final pillStyle = LiquidGlassStyle(
          color: Colors.transparent, blur: optics.blur,
          refractionIndex: optics.refractionIndex,
          refractionWidth: optics.refractionWidth,
          // The same magnifier strength as the bottom tab, now along Y.
          magnification: optics.magnifierPill.magnification,
          dispersion: optics.dispersion,
        );
        return Stack(clipBehavior: Clip.none, children: [
          AnimatedPositioned(
            duration: duration,
            curve: Curves.easeInOutCubic,
            top: position.dy,
            left: position.dx,
            width: size,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              KumoneLiquidSurface(
                radius: size / 2,
                child: _gestures(
                    Semantics(
                      label: '搜索',
                      hint: expanded ? '长按一秒后拖动功能栏位置' : '按住零点二秒展开，继续滑动选择',
                      child: IconButton(
                          key: const ValueKey('floating-search'),
                          tooltip: '搜索',
                          style: IconButton.styleFrom(
                              fixedSize: Size.square(size),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                          icon: Icon(Icons.search, size: 29 * scale),
                          onPressed: () => widget.onChanged(2)),
                    ),
                    search: true),
              ),
              AnimatedSize(
                duration: duration,
                curve: Curves.easeInOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: EdgeInsets.only(top: 8 * scale),
                        child: KumoneLiquidSurface(
                          radius: size / 2,
                          padding: EdgeInsets.symmetric(vertical: 6 * scale),
                          child: _gestures(
                              SizedBox(
                                key: _panelKey,
                                width: size,
                                height: panelHeight,
                                child:
                                    Stack(clipBehavior: Clip.none, children: [
                                  Column(children: [
                                    for (final i in widget.order)
                                      _item(i, scale, size, cell)
                                  ]),
                                  // Overlay the content with the library's spring-driven lens:
                                  // it magnifies/refracts the glyphs underneath on Impeller,
                                  // and handles lift, squash/stretch and settling itself.
                                  if (selected >= 0 || _scrubbing)
                                    Positioned.fill(
                                        child: IgnorePointer(
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(end: targetY),
                                        duration: _scrubbing
                                            ? Duration.zero
                                            : duration,
                                        curve: Curves.easeOutCubic,
                                        builder: (_, y, __) =>
                                            LiquidGlassMotionPill(
                                          key: const ValueKey(
                                              'floating-glass-selection'),
                                          center: Offset(size / 2, y),
                                          active: !reduce &&
                                              (_scrubbing || _lifted),
                                          restSize: Size(size - 8 * scale,
                                              cell - 4 * scale),
                                          activeSize: Size(size + 5 * scale,
                                              cell + 8 * scale),
                                          style: pillStyle,
                                          motion: optics.motion,
                                          cover:
                                              ColoredBox(color: optics.color),
                                        ),
                                      ),
                                    )),
                                ]),
                              ),
                              search: false),
                        ),
                      )
                    : SizedBox(width: size),
              ),
            ]),
          ),
        ]);
      }),
    );
  }
}

@Preview(name: 'Floating glass navigation', size: Size(900, 500))
Widget floatingNavigationPreview() => MaterialApp(
        home: Scaffold(
      body: KumoneGlassSideNavigation(
          selectedIndex: 0,
          onChanged: (_) {},
          onExpand: () {},
          labels: const [
            '推荐',
            '精选',
            '搜索',
            '我的'
          ],
          icons: const [
            Icons.home,
            Icons.grid_view,
            Icons.search,
            Icons.person
          ]),
    ));
