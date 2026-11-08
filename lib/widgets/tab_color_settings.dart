import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-tab, per-element HSL color preferences.
class TabColorSettings {
  static String _key(String tab, String element) =>
      'tab_color_${tab}_${element}';

  static Future<Color> load(String tab, String element, Color fallback) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_key(tab, element));
    return value == null ? fallback : Color(value);
  }

  static Future<void> open(
    BuildContext context, {
    required String tab,
    required Map<String, Color> elements,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _ColorSettingsSheet(
        tab: tab,
        elements: elements,
        prefs: prefs,
      ),
    );
  }
}

class TabColorSettingsButton extends StatelessWidget {
  const TabColorSettingsButton({
    super.key,
    required this.tab,
    required this.elements,
  });

  final String tab;
  final Map<String, Color> elements;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'تنظیمات رنگ',
        icon: const Icon(Icons.palette_outlined),
        onPressed: () => TabColorSettings.open(
          context,
          tab: tab,
          elements: elements,
        ),
      );
}

class _ColorSettingsSheet extends StatefulWidget {
  const _ColorSettingsSheet({
    required this.tab,
    required this.elements,
    required this.prefs,
  });

  final String tab;
  final Map<String, Color> elements;
  final SharedPreferences prefs;

  @override
  State<_ColorSettingsSheet> createState() => _ColorSettingsSheetState();
}

class _ColorSettingsSheetState extends State<_ColorSettingsSheet> {
  late final Map<String, HSLColor> _colors;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _colors = {
      for (final entry in widget.elements.entries)
        entry.key: HSLColor.fromColor(
          Color(widget.prefs.getInt('tab_color_${widget.tab}_${entry.key}') ??
              entry.value.value),
        ),
    };
    _selected = _colors.keys.firstOrNull;
  }

  Future<void> _save() async {
    for (final entry in _colors.entries) {
      await widget.prefs.setInt(
        'tab_color_${widget.tab}_${entry.key}',
        entry.value.toColor().value,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final key = _selected;
    final color = key == null ? Colors.blue : _colors[key]!.toColor();
    final hsl = key == null ? HSLColor.fromColor(Colors.blue) : _colors[key]!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('رنگ‌های این بخش', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: key,
              decoration: const InputDecoration(labelText: 'عنصر'),
              items: _colors.keys
                  .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                  .toList(),
              onChanged: (value) => setState(() => _selected = value),
            ),
            const SizedBox(height: 16),
            Container(
              height: 54,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('پیش‌نمایش رنگ', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 12),
            _slider('Hue', hsl.hue, 0, 360, (v) {
              setState(() => _colors[key!] = hsl.withHue(v));
            }),
            _slider('Saturation', hsl.saturation, 0, 1, (v) {
              setState(() => _colors[key!] = hsl.withSaturation(v));
            }),
            _slider('Lightness', hsl.lightness, 0, 1, (v) {
              setState(() => _colors[key!] = hsl.withLightness(v));
            }),
            const SizedBox(height: 8),
            FilledButton(onPressed: _save, child: const Text('ذخیره رنگ‌ها')),
          ],
        ),
      ),
    );
  }

  Widget _slider(
    String label, double value, double min, double max,
    ValueChanged<double> onChanged,
  ) => Row(
        children: [
          SizedBox(width: 92, child: Text(label)),
          Expanded(
            child: Slider(value: value.clamp(min, max), min: min, max: max,
                onChanged: onChanged),
          ),
        ],
      );
}
