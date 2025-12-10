// scale_widget.dart (patched — safe scroll handling)
import 'package:flutter/material.dart';
import '../models/scale_config.dart';
import '../utils/debounce.dart';

/// A highly customizable scale picker widget
class ScaleWidget extends StatefulWidget {
  /// Configuration for the scale appearance and behavior
  final ScaleConfig config;

  /// Configuration for the measurement unit and values
  final MeasurementConfig measurementConfig;

  /// Callback when the selected value changes
  final ValueChanged<double>? onChanged;

  /// Initial scroll controller (optional)
  final ScrollController? controller;

  /// Whether to show the center indicator
  final bool showCenterIndicator;

  /// Custom center indicator widget
  final Widget? centerIndicator;

  /// Custom shader for fade effect
  final List<Color>? shaderColors;
  final List<double>? shaderStops;

  const ScaleWidget({
    super.key,
    required this.config,
    required this.measurementConfig,
    this.onChanged,
    this.controller,
    this.showCenterIndicator = true,
    this.centerIndicator,
    this.shaderColors,
    this.shaderStops,
  });

  @override
  State<ScaleWidget> createState() => _ScaleWidgetState();
}

class _ScaleWidgetState extends State<ScaleWidget> {
  late ScrollController _scrollController;
  late ValueNotifier<double> _valueNotifier;
  late Debounce _debounce;

  bool _pauseListener = false;
  double get _itemSpacing => widget.config.itemSpacing;

  // retry attempts for initial positioning (to wait for controllers to attach)
  int _initialPositionAttempts = 0;
  static const int _maxInitialPositionAttempts = 4;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    _valueNotifier =
        ValueNotifier<double>(widget.measurementConfig.initialValue);
    _debounce = Debounce(duration: const Duration(milliseconds: 250));

    // Wait for layout, then try to position & attach listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptInitialPositioning();
      // Always add listener — it's safe even if controller has no clients.
      // But methods that access offset check hasClients.
      _scrollController.addListener(_onScroll);
    });
  }

  @override
  void dispose() {
    _debounce.dispose();
    if (widget.controller == null) {
      // only dispose if we created it
      _scrollController.dispose();
    }
    _valueNotifier.dispose();
    super.dispose();
  }

  /// Try to position the scroll offset to the initial value.
  /// If the controller has no clients yet, retry for a few frames.
  void _attemptInitialPositioning() {
    if (!mounted) return;

    // If controller is already attached to a Scrollable, animate/jump safely.
    if (_scrollController.hasClients) {
      final initialOffset = _valueToOffset(widget.measurementConfig.initialValue);

      // Try animateTo but guard and catch errors.
      try {
        // Use jumpTo if the animation duration is zero or very small.
        if (widget.config.animationDuration == Duration.zero) {
          _scrollController.jumpTo(initialOffset);
        } else {
          _scrollController.animateTo(
            initialOffset,
            duration: widget.config.animationDuration,
            curve: widget.config.animationCurve,
          );
        }
      } catch (_) {
        // swallow any exceptions (controller may be disposed mid-flight)
      }
      return;
    }

    // If no clients yet, schedule a retry (limited attempts).
    if (_initialPositionAttempts < _maxInitialPositionAttempts) {
      _initialPositionAttempts += 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _attemptInitialPositioning();
      });
    } else {
      // final fallback: nothing to do; the user can scroll manually
    }
  }

  double _valueToOffset(double value) {
    // offset = (value - min) * (spacing / minorInterval)
    final adjustedValue = value - widget.measurementConfig.minValue;
    return adjustedValue * _itemSpacing / widget.measurementConfig.minorInterval;
  }

  double _offsetToValue(double offset) {
    final adjustedValue =
        (offset / _itemSpacing) * widget.measurementConfig.minorInterval;
    return adjustedValue + widget.measurementConfig.minValue;
  }

  void _onScroll() {
    // Guard: if controller has no clients, don't read offset.
    if (!_scrollController.hasClients || _pauseListener) return;

    _updateCurrentValue();
    _snapToNearestValue();
  }

  void _updateCurrentValue() {
    if (!_scrollController.hasClients) return;

    final currentValue = _offsetToValue(_scrollController.offset);
    final clampedValue = currentValue.clamp(
      widget.measurementConfig.minValue,
      widget.measurementConfig.maxValue,
    );

    if (_valueNotifier.value != clampedValue) {
      _valueNotifier.value = clampedValue;
      try {
        widget.onChanged?.call(clampedValue);
      } catch (_) {
        // ignore callback errors
      }
    }
  }

  void _snapToNearestValue() {
    // Debounced snap to nearest tick - guarded by hasClients
    _debounce.call(() async {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      if (_pauseListener) return;

      final rawOffset = _scrollController.offset;
      final snapOffset =
          (rawOffset / _itemSpacing).round() * _itemSpacing;

      _pauseListener = true;
      try {
        await _scrollController.animateTo(
          snapOffset,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      } catch (_) {
        // swallow (controller may be disposed or animation interrupted)
      } finally {
        if (mounted) _pauseListener = false;
      }
    });
  }

  int _getItemCount() {
    final totalRange =
        widget.measurementConfig.maxValue - widget.measurementConfig.minValue;
    return (totalRange / widget.measurementConfig.minorInterval).ceil() + 1;
  }

  bool _isMajorTick(int index) {
    final value = widget.measurementConfig.minValue +
        (index * widget.measurementConfig.minorInterval);
    return (value - widget.measurementConfig.minValue) %
            widget.measurementConfig.majorInterval ==
        0;
  }

  String _getLabel(int index) {
    final value = widget.measurementConfig.minValue +
        (index * widget.measurementConfig.minorInterval);
    final isMajor = _isMajorTick(index);

    if (widget.measurementConfig.labelFormatter != null) {
      return widget.measurementConfig.labelFormatter!(index, isMajor);
    }

    if (isMajor) {
      return value.toStringAsFixed(widget.measurementConfig.decimalPlaces);
    } else if (widget.config.showMinorLabels) {
      return value.toStringAsFixed(widget.measurementConfig.decimalPlaces);
    }

    return '';
  }

  Widget _buildCenterIndicator() {
    if (widget.centerIndicator != null) {
      return widget.centerIndicator!;
    }

    if (widget.config.isVertical) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.arrow_right,
            color: widget.config.centerIndicatorColor,
            size: 20,
          ),
          Container(
            height: 3,
            width: 40,
            color: widget.config.centerIndicatorColor,
          ),
          const SizedBox(width: 25),
        ],
      );
    } else {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 25),
          Container(
            height: 40,
            width: 3,
            color: widget.config.centerIndicatorColor,
          ),
          Icon(
            Icons.keyboard_arrow_up,
            color: widget.config.centerIndicatorColor,
            size: 20,
          ),
        ],
      );
    }
  }

  Widget _buildListView() {
    if (widget.config.isVertical) {
      return _buildVerticalListView();
    } else {
      return _buildHorizontalListView();
    }
  }

  Widget _buildVerticalListView() {
    final screenHeight = MediaQuery.of(context).size.height;
    final containerHeight = widget.config.height ?? screenHeight * 0.4;
    final listViewHeight = containerHeight - (widget.config.padding.vertical);

    return SizedBox(
      height: listViewHeight,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.vertical,
        itemCount: _getItemCount(),
        padding: EdgeInsets.only(
          top: listViewHeight / 2.5,
          bottom: listViewHeight / 2.5,
        ),
        separatorBuilder: (context, index) => SizedBox(height: _itemSpacing - 2),
        itemBuilder: (context, index) {
          final isMajor = _isMajorTick(index);
          final label = _getLabel(index);

          return SizedBox(
            height: 2,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                if (label.isNotEmpty)
                  Positioned(
                    left: -60,
                    child: SizedBox(
                      width: 50,
                      child: Text(
                        label,
                        style: isMajor
                            ? widget.config.majorTextStyle ??
                                const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)
                            : widget.config.minorTextStyle ??
                                const TextStyle(fontSize: 10),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                Container(
                  height: widget.config.majorLineWidth,
                  width: isMajor ? widget.config.majorLineLength : widget.config.minorLineLength,
                  color: isMajor ? widget.config.majorLineColor : widget.config.minorLineColor,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalListView() {
    final screenWidth = MediaQuery.of(context).size.width;
    final listViewWidth = widget.config.width ?? screenWidth - 32;

    return ListView.separated(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      itemCount: _getItemCount(),
      padding: EdgeInsets.only(
        left: listViewWidth / 2,
        right: listViewWidth / 2,
      ),
      separatorBuilder: (context, index) => SizedBox(width: _itemSpacing - 2),
      itemBuilder: (context, index) {
        final isMajor = _isMajorTick(index);
        final label = _getLabel(index);

        return SizedBox(
          width: 2,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              if (label.isNotEmpty)
                Positioned(
                  top: -25,
                  child: Text(
                    label,
                    style: isMajor
                        ? widget.config.majorTextStyle ??
                            const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)
                        : widget.config.minorTextStyle ??
                            const TextStyle(fontSize: 10),
                  ),
                ),
              Container(
                height: isMajor ? widget.config.majorLineLength : widget.config.minorLineLength,
                width: widget.config.majorLineWidth,
                color: isMajor ? widget.config.majorLineColor : widget.config.minorLineColor,
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Determine container dimensions based on orientation
    final containerHeight = widget.config.isVertical
        ? (widget.config.height ?? screenHeight * 0.4)
        : null;
    final containerWidth = widget.config.isVertical
        ? null
        : (widget.config.width ?? screenWidth - 32);

    final child = Container(
      decoration: BoxDecoration(
        color: widget.config.backgroundColor,
        borderRadius: widget.config.borderRadius,
      ),
      height: containerHeight,
      width: containerWidth,
      padding: widget.config.padding,
      child: Stack(
        children: [
          _buildListView(),
          if (widget.showCenterIndicator)
            Align(
              alignment: Alignment.center,
              child: _buildCenterIndicator(),
            ),
        ],
      ),
    );

    // Apply shader mask if colors are provided
    if (widget.shaderColors != null) {
      return ShaderMask(
        shaderCallback: (Rect bounds) {
          return LinearGradient(
            colors: widget.shaderColors!,
            stops: widget.shaderStops ?? [0.0, 0.25, 0.75, 1.0],
            begin: widget.config.isVertical ? Alignment.topCenter : Alignment.centerLeft,
            end: widget.config.isVertical ? Alignment.bottomCenter : Alignment.centerRight,
          ).createShader(bounds);
        },
        child: child,
      );
    }

    return child;
  }
}
