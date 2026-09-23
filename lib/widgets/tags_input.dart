import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Input de tags tipo chip. El usuario tipea, presiona Enter (o coma)
/// para agregar el tag. Tap en X del chip lo quita. Backspace en input
/// vacío quita el último.
///
/// Auto-sugerencias opcionales via [suggestions] (típicamente todos los
/// tags ya usados en la app).
class TagsInput extends StatefulWidget {
  final List<String> initialTags;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;
  final String label;
  final String hint;

  const TagsInput({
    super.key,
    required this.initialTags,
    required this.onChanged,
    this.suggestions = const [],
    this.label = 'Tags',
    this.hint = 'Escribe y presiona Enter para agregar',
  });

  @override
  State<TagsInput> createState() => _TagsInputState();
}

class _TagsInputState extends State<TagsInput> {
  late List<String> _tags;
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.initialTags.map(_normalize));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _normalize(String raw) => raw.trim().toLowerCase();

  void _addTag(String raw) {
    final tag = _normalize(raw);
    if (tag.isEmpty) return;
    if (_tags.contains(tag)) {
      _controller.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _controller.clear();
    });
    widget.onChanged(_tags);
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    widget.onChanged(_tags);
  }

  void _handleSubmit(String value) {
    // Soportar coma como separador adicional
    if (value.contains(',')) {
      for (final part in value.split(',')) {
        _addTag(part);
      }
    } else {
      _addTag(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final availableSuggestions = widget.suggestions
        .where((s) => !_tags.contains(_normalize(s)))
        .where((s) {
          final input = _normalize(_controller.text);
          if (input.isEmpty) return false;
          return s.contains(input);
        })
        .take(5)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ..._tags.map((tag) => Chip(
                    label: Text(tag),
                    backgroundColor: theme.primaryColor.withValues(alpha: 0.1),
                    side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.3)),
                    deleteIconColor: theme.primaryColor,
                    onDeleted: () => _removeTag(tag),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 140),
                child: IntrinsicWidth(
                  child: KeyboardListener(
                    focusNode: FocusNode(),
                    onKeyEvent: (event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.backspace &&
                          _controller.text.isEmpty &&
                          _tags.isNotEmpty) {
                        _removeTag(_tags.last);
                      }
                    },
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: InputDecoration(
                        hintText: _tags.isEmpty ? widget.hint : null,
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                      onSubmitted: _handleSubmit,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (availableSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: availableSuggestions
                .map((s) => ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 11)),
                      onPressed: () => _addTag(s),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}

/// Helper para juntar todos los tags únicos usados en una colección de
/// productos (input para autocomplete).
List<String> collectAllTags(Iterable<dynamic> productsWithTags) {
  final all = <String>{};
  for (final p in productsWithTags) {
    final tags = (p.tags as List<String>?) ?? const [];
    for (final t in tags) {
      final n = t.trim().toLowerCase();
      if (n.isNotEmpty) all.add(n);
    }
  }
  final list = all.toList()..sort();
  return list;
}
