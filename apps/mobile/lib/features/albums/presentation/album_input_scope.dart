import 'package:flutter/material.dart';

/// Owns popup inputs until its route content is actually unmounted.
/// Navigator.pop completes a popup's result before its exit animation finishes.
/// Disposing controllers immediately after awaiting showDialog/showModalBottomSheet
/// would leave the still-mounted TextFields listening to disposed controllers.
class AlbumInputScope extends StatefulWidget {
  const AlbumInputScope({
    super.key,
    required this.initialValues,
    required this.builder,
  });

  final Map<String, String> initialValues;
  final Widget Function(
    BuildContext context,
    Map<String, TextEditingController> inputs,
  )
  builder;

  @override
  State<AlbumInputScope> createState() => _AlbumInputScopeState();
}

class _AlbumInputScopeState extends State<AlbumInputScope> {
  late final Map<String, TextEditingController> _inputs;

  @override
  void initState() {
    super.initState();
    _inputs = {
      for (final entry in widget.initialValues.entries)
        entry.key: TextEditingController(text: entry.value),
    };
  }

  @override
  void dispose() {
    for (final controller in _inputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _inputs);
}
