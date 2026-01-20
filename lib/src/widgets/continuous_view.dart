import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../manga_page_view.dart';
import '../manga_page_view_controller.dart';
import 'interactive_panel.dart';
import 'page_strip.dart';
import 'viewport_size.dart';

/// Base widget for continuous view
class MangaPageContinuousView extends StatefulWidget {
  const MangaPageContinuousView({
    super.key,
    required this.controller,
    required this.direction,
    required this.options,
    required this.initialPageIndex,
    required this.pageCount,
    required this.pageBuilder,
    this.onPageChange,
    this.onZoomChange,
    this.onProgressChange,
  });

  final MangaPageViewController controller;
  final MangaPageViewDirection direction;
  final MangaPageViewOptions options;
  final int? initialPageIndex;
  final int pageCount;
  final IndexedWidgetBuilder pageBuilder;
  final Function(int index)? onPageChange;
  final Function(double zoomLevel)? onZoomChange;
  final Function(double progress)? onProgressChange;

  @override
  State<MangaPageContinuousView> createState() =>
      _MangaPageContinuousViewState();
}

class _MangaPageContinuousViewState extends State<MangaPageContinuousView> {
  final _interactionPanelKey = GlobalKey<InteractivePanelState>();
  final _stripContainerKey = GlobalKey<PageStripState>();

  double get _scrollBoundMin {
    final scrollableRegion = _panelState.scrollableRegion;
    switch (widget.direction) {
      case MangaPageViewDirection.up:
        return scrollableRegion.bottom;
      case MangaPageViewDirection.down:
        return scrollableRegion.top;
      case MangaPageViewDirection.left:
        return scrollableRegion.right;
      case MangaPageViewDirection.right:
        return scrollableRegion.left;
    }
  }

  double get _scrollBoundMax {
    final scrollableRegion = _panelState.scrollableRegion;
    switch (widget.direction) {
      case MangaPageViewDirection.up:
        return scrollableRegion.top;
      case MangaPageViewDirection.down:
        return scrollableRegion.bottom;
      case MangaPageViewDirection.left:
        return scrollableRegion.left;
      case MangaPageViewDirection.right:
        return scrollableRegion.right;
    }
  }

  Offset _currentOffset = Offset.zero;
  int _currentPage = 0;
  late double _currentZoomLevel = widget.options.initialZoomLevel;
  bool _isChangingPage = false;

  InteractivePanelState get _panelState => _interactionPanelKey.currentState!;

  PageStripState get _stripState => _stripContainerKey.currentState!;

  Size get _viewportSize => ViewportSize.of(context).value;

  StreamSubscription<ControllerChangeIntent>? _controllerIntentStream;

  @override
  void initState() {
    super.initState();
    _controllerIntentStream = widget.controller.intents.listen(
      _onControllerIntent,
    );
    if (widget.initialPageIndex != null) {
      _goToPage(widget.initialPageIndex!);
    }
  }

  @override
  void didUpdateWidget(covariant MangaPageContinuousView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.direction != oldWidget.direction) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _goToPage(_currentPage);
      });
    }
  }

  @override
  void dispose() {
    _controllerIntentStream?.cancel();
    super.dispose();
  }

  void _onControllerIntent(ControllerChangeIntent intent) {
    switch (intent) {
      case PageChangeIntent(:final index, :final duration, :final curve):
        if (index < 0 || index >= widget.pageCount) return;

        if (duration > Duration.zero) {
          _animateToPage(index, duration, curve);
        } else {
          _goToPage(index);
        }
      case ProgressChangeIntent(:final progress, :final duration, :final curve):
        final targetOffset = progressToOffset(progress);
        if (duration > Duration.zero) {
          _panelState.animateToOffset(
            targetOffset,
            duration,
            curve,
            onEnd: _onPageChangeEnd,
          );
        } else {
          _panelState.jumpToOffset(targetOffset);
        }
      case ZoomChangeIntent(:final zoomLevel, :final duration, :final curve):
        if (duration > Duration.zero) {
          _panelState.animateZoomTo(zoomLevel, duration, curve);
        } else {
          _panelState.zoomTo(zoomLevel);
        }
      case ScrollDeltaChangeIntent(:final delta, :final duration, :final curve):
        final targetOffset = _scrollBy(delta);
        if (duration > Duration.zero) {
          _panelState.animateToOffset(
            targetOffset,
            duration,
            curve,
            onEnd: _onPageChangeEnd,
          );
        } else {
          _panelState.jumpToOffset(targetOffset);
        }
      case PanDeltaChangeIntent(:final delta, :final duration, :final curve):
        final targetOffset = _panBy(delta);
        if (duration > Duration.zero) {
          _panelState.animateToOffset(
            targetOffset,
            duration,
            curve,
            onEnd: _onPageChangeEnd,
          );
        } else {
          _panelState.jumpToOffset(targetOffset);
        }
    }
  }

  Offset _getPageJumpOffset(Rect pageBounds) {
    final viewport = _viewportSize;
    final padding = (viewport / 2) * (1 - 1 / _currentZoomLevel);

    final bounds = Rect.fromLTRB(
      pageBounds.left - padding.width,
      pageBounds.top - padding.height,
      pageBounds.right + padding.width,
      pageBounds.bottom + padding.height,
    );

    final gravity = widget.options.pageJumpGravity;
    final viewportCenter = viewport.center(Offset.zero);

    return switch (widget.direction) {
      MangaPageViewDirection.down => gravity.select(
        start: bounds.topCenter,
        center: bounds.center.translate(0, -viewportCenter.dy),
        end: bounds.bottomCenter.translate(0, -viewport.height),
      ),
      MangaPageViewDirection.up => gravity.select(
        start: bounds.bottomCenter,
        center: bounds.center.translate(0, viewportCenter.dy),
        end: bounds.topCenter.translate(0, viewport.height),
      ),
      MangaPageViewDirection.right => gravity.select(
        start: bounds.centerLeft,
        center: bounds.center.translate(-viewportCenter.dx, 0),
        end: bounds.centerRight.translate(-viewport.width, 0),
      ),
      MangaPageViewDirection.left => gravity.select(
        start: bounds.centerRight,
        center: bounds.center.translate(viewportCenter.dx, 0),
        end: bounds.centerLeft.translate(viewport.width, 0),
      ),
    };
  }

  void _goToPage(int pageIndex) {
    _isChangingPage = true;

    // Early callback
    _doPageChangeCallback(pageIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pageRect = _stripState.pageBounds[pageIndex];
      _panelState.jumpToOffset(_getPageJumpOffset(pageRect));
      _onPageChangeEnd();
    });
    WidgetsBinding.instance.scheduleFrame(); // Force refresh
  }

  void _onPageChangeEnd() {
    _isChangingPage = false;
    _updatePageDisplay();
  }

  void _animateToPage(int pageIndex, Duration duration, Curve curve) {
    _isChangingPage = true;

    // Early callback
    _doPageChangeCallback(pageIndex);

    final pageRect = _stripState.pageBounds[pageIndex];
    _panelState.animateToOffset(
      _getPageJumpOffset(pageRect),
      duration,
      curve,
      onEnd: _onPageChangeEnd,
    );
  }

  Offset _scrollBy(double delta) {
    final currentOffset = _panelState.offset;
    final scrollableRegion = _panelState.scrollableRegion;
    final Offset newOffset;

    switch (widget.direction) {
      case MangaPageViewDirection.down:
        newOffset = Offset(
          currentOffset.dx,
          (currentOffset.dy + delta).clamp(
            scrollableRegion.top,
            scrollableRegion.bottom,
          ),
        );
        break;
      case MangaPageViewDirection.up:
        newOffset = Offset(
          currentOffset.dx,
          (currentOffset.dy - delta).clamp(
            scrollableRegion.bottom,
            scrollableRegion.top,
          ),
        );
        break;
      case MangaPageViewDirection.right:
        newOffset = Offset(
          (currentOffset.dx + delta).clamp(
            scrollableRegion.left,
            scrollableRegion.right,
          ),
          currentOffset.dy,
        );
        break;
      case MangaPageViewDirection.left:
        newOffset = Offset(
          (currentOffset.dx - delta).clamp(
            scrollableRegion.right,
            scrollableRegion.left,
          ),
          currentOffset.dy,
        );
        break;
    }
    return newOffset;
  }

  Offset _panBy(Offset delta) {
    final currentOffset = _panelState.offset;
    final newOffset = currentOffset + delta;
    return newOffset;
  }

  void _onScroll(Offset offset, double zoomLevel) {
    _currentOffset = offset;

    if (zoomLevel != _currentZoomLevel) {
      _currentZoomLevel = zoomLevel;
      widget.onZoomChange?.call(
        zoomLevel.clamp(
          widget.options.minZoomLevel,
          widget.options.maxZoomLevel,
        ),
      );
    }

    if (!_isChangingPage) {
      _updatePageDisplay();
    }
  }

  void _onPageSizeChanged(int pageIndex, Size oldSize, Size newSize) {
    // print('Size changed for page $pageIndex: $oldSize -> $newSize');
  }

  void _updatePageDisplay() {
    final viewRegion = _computeVisibleWindow(
      _currentOffset,
      _currentZoomLevel,
      _viewportSize,
    );
    if (!viewRegion.isEmpty) {
      _stripState.glance(viewRegion);
      _updatePageIndex(viewRegion);
    }
    final fraction = _offsetToFraction(_currentOffset);

    widget.onProgressChange?.call(fraction);
  }

  void _updatePageIndex(Rect viewRegion) {
    final bounds = _stripState.pageBounds;
    final gravity = widget.options.pageSenseGravity;

    final screenEdge = switch (widget.direction) {
      MangaPageViewDirection.down => gravity.select(
        start: viewRegion.top,
        center: viewRegion.center.dy,
        end: viewRegion.bottom,
      ),
      MangaPageViewDirection.up => gravity.select(
        start: -viewRegion.bottom,
        center: -viewRegion.center.dy,
        end: -viewRegion.top,
      ),
      MangaPageViewDirection.left => gravity.select(
        start: -viewRegion.right,
        center: -viewRegion.center.dx,
        end: -viewRegion.left,
      ),
      MangaPageViewDirection.right => gravity.select(
        start: viewRegion.left,
        center: viewRegion.center.dx,
        end: viewRegion.right,
      ),
    };
    final pageEdge = switch (widget.direction) {
      MangaPageViewDirection.down => (Rect b) => b.top,
      MangaPageViewDirection.up => (Rect b) => -b.bottom,
      MangaPageViewDirection.left => (Rect b) => -b.right,
      MangaPageViewDirection.right => (Rect b) => b.left,
    };

    int checkIndex = -1;
    final differenceTolerance = 20;

    for (int i = 0; i < widget.pageCount; i++) {
      if (pageEdge(bounds[i]) - screenEdge > differenceTolerance) {
        break;
      }
      checkIndex += 1;
    }

    final pageIndex = checkIndex.clamp(0, widget.pageCount - 1);

    if (!_isChangingPage && _currentPage != pageIndex) {
      _doPageChangeCallback(pageIndex);
    }
  }

  void _doPageChangeCallback(int pageIndex) {
    widget.onPageChange?.call(pageIndex);
    _currentPage = pageIndex;
  }

  double _offsetToFraction(Offset offset) {
    final double current;
    final double min;
    final double max;

    switch (widget.direction) {
      case MangaPageViewDirection.up:
        current = offset.dy;
        min = _scrollBoundMax;
        max = _scrollBoundMin;
        break;
      case MangaPageViewDirection.down:
        current = offset.dy;
        min = _scrollBoundMin;
        max = _scrollBoundMax;
        break;
      case MangaPageViewDirection.left:
        current = offset.dx;
        min = _scrollBoundMax;
        max = _scrollBoundMin;
        break;
      case MangaPageViewDirection.right:
        current = offset.dx;
        min = _scrollBoundMin;
        max = _scrollBoundMax;
        break;
    }
    if (max - min == 0) {
      return 0;
    }
    return ((current - min) / (max - min)).clamp(0, 1);
  }

  Offset progressToOffset(double fraction) {
    final double target;
    final double min;
    final double max;

    switch (widget.direction) {
      case MangaPageViewDirection.up:
      case MangaPageViewDirection.left:
        min = _scrollBoundMax;
        max = _scrollBoundMin;
        break;
      case MangaPageViewDirection.down:
      case MangaPageViewDirection.right:
        min = _scrollBoundMin;
        max = _scrollBoundMax;
        break;
    }
    target = min + (max - min) * fraction;

    return switch (widget.direction) {
      MangaPageViewDirection.up ||
      MangaPageViewDirection.down => Offset(_currentOffset.dx, target),
      MangaPageViewDirection.left ||
      MangaPageViewDirection.right => Offset(target, _currentOffset.dy),
    };
  }

  Rect _computeVisibleWindow(
    Offset offset,
    double zoomLevel,
    Size viewportSize,
  ) {
    final viewportCenter = viewportSize.center(Offset.zero);
    final worldCenter = offset + viewportCenter;

    final halfSizeInWorld = Offset(
      viewportSize.width / zoomLevel / 2,
      viewportSize.height / zoomLevel / 2,
    );

    final topLeft = worldCenter - halfSizeInWorld;
    final size = viewportSize / zoomLevel;

    final visibleRect = topLeft & size;

    // Adjust window on left and up direction mode
    return switch (widget.direction) {
      MangaPageViewDirection.up => visibleRect.translate(
        0,
        -viewportSize.height,
      ),
      MangaPageViewDirection.down => visibleRect,
      MangaPageViewDirection.left => visibleRect.translate(
        -viewportSize.width,
        0,
      ),
      MangaPageViewDirection.right => visibleRect,
    };
  }

  @override
  Widget build(BuildContext context) {
    return InteractivePanel(
      key: _interactionPanelKey,
      initialZoomLevel: widget.options.initialZoomLevel,
      initialFadeInDuration: widget.options.initialFadeInDuration,
      initialFadeInCurve: widget.options.initialFadeInCurve,
      minZoomLevel: widget.options.minZoomLevel,
      maxZoomLevel: widget.options.maxZoomLevel,
      presetZoomLevels: widget.options.presetZoomLevels,
      zoomOnFocalPoint: widget.options.zoomOnFocalPoint,
      zoomOvershoot: widget.options.zoomOvershoot,
      verticalOverscroll:
          widget.direction.isVertical && widget.options.mainAxisOverscroll ||
          widget.direction.isHorizontal && widget.options.crossAxisOverscroll,
      horizontalOverscroll:
          widget.direction.isHorizontal && widget.options.mainAxisOverscroll ||
          widget.direction.isVertical && widget.options.crossAxisOverscroll,
      anchor: switch (widget.direction) {
        MangaPageViewDirection.down => MangaPageViewEdge.top,
        MangaPageViewDirection.right => MangaPageViewEdge.left,
        MangaPageViewDirection.up => MangaPageViewEdge.bottom,
        MangaPageViewDirection.left => MangaPageViewEdge.right,
      },
      panCheckAxis: widget.direction.axis,
      onScroll: _onScroll,
      child: PageStrip(
        key: _stripContainerKey,
        direction: widget.direction,
        padding: widget.options.padding,
        spacing: widget.options.spacing,
        initialPageSize: widget.options.initialPageSize,
        precacheAhead: widget.options.precacheAhead,
        precacheBehind: widget.options.precacheBehind,
        widthLimit: widget.options.pageWidthLimit,
        heightLimit: widget.options.pageHeightLimit,
        pageCount: widget.pageCount,
        pageBuilder: widget.pageBuilder,
        onPageSizeChanged: _onPageSizeChanged,
      ),
    );
  }
}
