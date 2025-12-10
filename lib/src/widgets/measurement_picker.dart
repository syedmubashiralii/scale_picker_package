import 'package:flutter/material.dart';
import '../models/scale_config.dart';
import '../utils/unit_converter.dart';
import 'scale_widget.dart';

/// A complete measurement picker with unit toggle functionality
class MeasurementPicker extends StatefulWidget {
  /// Primary measurement configuration (e.g., kg, cm)
  final MeasurementConfig primaryConfig;

  /// Secondary measurement configuration (e.g., lbs, ft)
  final MeasurementConfig secondaryConfig;

  /// Scale appearance configuration
  final ScaleConfig scaleConfig;

  /// Initial value in primary units
  final double? initialValue;

  /// Whether to start with primary unit (true) or secondary (false)
  final bool initialPrimaryUnit;

  /// Title text
  final String? title;
  final TextStyle? titleStyle;

  /// Subtitle text
  final String? subtitle;
  final TextStyle? subtitleStyle;

  /// Toggle button labels
  final String primaryUnitLabel;
  final String secondaryUnitLabel;

  /// Callback when value changes
  final ValueChanged<MeasurementValue>? onChanged;

  /// Custom toggle button builder
  final Widget Function(bool isPrimary, VoidCallback onToggle)?
      toggleButtonBuilder;

  /// Custom value display builder
  final Widget Function(MeasurementValue value)? valueDisplayBuilder;

  /// Custom shader colors for fade effect
  final List<Color>? shaderColors;
  final List<double>? shaderStops;

  const MeasurementPicker({
    super.key,
    required this.primaryConfig,
    required this.secondaryConfig,
    required this.scaleConfig,
    this.initialValue,
    this.initialPrimaryUnit = true,
    this.title,
    this.titleStyle,
    this.subtitle,
    this.subtitleStyle,
    required this.primaryUnitLabel,
    required this.secondaryUnitLabel,
    this.onChanged,
    this.toggleButtonBuilder,
    this.valueDisplayBuilder,
    this.shaderColors,
    this.shaderStops,
  });

  @override
  State<MeasurementPicker> createState() => _MeasurementPickerState();
}

class _MeasurementPickerState extends State<MeasurementPicker> {
  late ValueNotifier<bool> _isPrimaryUnitNotifier;
  late ValueNotifier<double> _currentValueNotifier;

  /// ScrollController created safely AFTER layout
  ScrollController? _scrollController;

  @override
  void initState() {
    super.initState();

    _isPrimaryUnitNotifier = ValueNotifier(widget.initialPrimaryUnit);

    final initialVal = widget.initialValue ??
        (widget.initialPrimaryUnit
            ? widget.primaryConfig.initialValue
            : widget.secondaryConfig.initialValue);

    _currentValueNotifier = ValueNotifier(initialVal);

    // Fix: Delay scroll controller creation AFTER layout to avoid crashes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _scrollController = ScrollController();
        });
      }
    });

    _isPrimaryUnitNotifier.addListener(_onUnitChanged);
  }

  @override
  void dispose() {
    _isPrimaryUnitNotifier.dispose();
    _currentValueNotifier.dispose();
    _scrollController?.dispose();
    super.dispose();
  }

  void _onUnitChanged() {
    final currentValue = _currentValueNotifier.value;
    double convertedValue;

    if (_isPrimaryUnitNotifier.value) {
      // Converting secondary → primary
      convertedValue = UnitConverter.convert(
        currentValue,
        1.0 / widget.secondaryConfig.conversionFactor,
      );
    } else {
      // Converting primary → secondary
      convertedValue = UnitConverter.convert(
        currentValue,
        widget.primaryConfig.conversionFactor,
      );
    }

    _currentValueNotifier.value = convertedValue;
    _notifyChange();
  }

  void _onScaleChanged(double value) {
    _currentValueNotifier.value = value;
    _notifyChange();
  }

  void _notifyChange() {
    if (widget.onChanged != null) {
      final value = MeasurementValue(
        value: _currentValueNotifier.value,
        unit: _isPrimaryUnitNotifier.value
            ? widget.primaryConfig.primaryUnit
            : widget.secondaryConfig.primaryUnit,
        isPrimaryUnit: _isPrimaryUnitNotifier.value,
      );
      widget.onChanged!(value);
    }
  }

  MeasurementConfig get _currentConfig =>
      _isPrimaryUnitNotifier.value ? widget.primaryConfig : widget.secondaryConfig;

  // ------------------------------------------
  // UI BUILD
  // ------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isPrimaryUnitNotifier,
      builder: (context, isPrimaryUnit, _) {
        return Column(
          children: [
            if (widget.title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  widget.title!,
                  style: widget.titleStyle ??
                      const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),

            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  widget.subtitle!,
                  style: widget.subtitleStyle ??
                      TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                ),
              ),

            // Unit toggle UI
            widget.toggleButtonBuilder != null
                ? widget.toggleButtonBuilder!(
                    isPrimaryUnit,
                    () => _isPrimaryUnitNotifier.value =
                        !_isPrimaryUnitNotifier.value,
                  )
                : _buildDefaultToggleButton(isPrimaryUnit),

            const SizedBox(height: 32),

            // Value display
            ValueListenableBuilder<double>(
              valueListenable: _currentValueNotifier,
              builder: (context, val, _) {
                final mv = MeasurementValue(
                  value: val,
                  unit: _currentConfig.primaryUnit,
                  isPrimaryUnit: isPrimaryUnit,
                );

                return widget.valueDisplayBuilder?.call(mv) ??
                    _buildDefaultValueDisplay(mv);
              },
            ),

            const SizedBox(height: 32),

            // MAIN SCALE PICKER — only build when scrollController is ready
            if (_scrollController != null)
              ScaleWidget(
                config: widget.scaleConfig,
                measurementConfig: _currentConfig,
                controller: _scrollController!,
                onChanged: _onScaleChanged,
                shaderColors: widget.shaderColors,
                shaderStops: widget.shaderStops,
              )
            else
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDefaultToggleButton(bool isPrimary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration:
          BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(25)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleItem(isPrimary, true, widget.primaryUnitLabel),
          _toggleItem(isPrimary, false, widget.secondaryUnitLabel),
        ],
      ),
    );
  }

  Widget _toggleItem(bool isPrimaryUnit, bool isThisPrimary, String label) {
    final selected = isPrimaryUnit == isThisPrimary;
    return GestureDetector(
      onTap: selected
          ? null
          : () => _isPrimaryUnitNotifier.value = !isPrimaryUnit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultValueDisplay(MeasurementValue v) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          v.formattedValue,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Text(
          v.unit,
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

class MeasurementValue {
  final double value;
  final String unit;
  final bool isPrimaryUnit;

  const MeasurementValue({
    required this.value,
    required this.unit,
    required this.isPrimaryUnit,
  });

  String get formattedValue => value.toStringAsFixed(0);

  @override
  String toString() => '$formattedValue $unit';
}
