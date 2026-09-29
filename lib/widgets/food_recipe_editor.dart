import 'package:flutter/material.dart';

import 'package:diabetes_app/models/food_recipe.dart';
import 'package:diabetes_app/services/food_recipe_service.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';

Future<FoodRecipe?> showFoodRecipeEditor(
  BuildContext context, {
  required FoodRecipeService recipes,
  FoodRecipe? existing,
  String initialName = '',
}) {
  return showDialog<FoodRecipe>(
    context: context,
    builder: (context) => _FoodRecipeEditorDialog(
      recipes: recipes,
      existing: existing,
      initialName: initialName,
    ),
  );
}

Future<void> showFoodRecipeManager(
  BuildContext context, {
  required FoodRecipeService recipes,
  required List<FoodRecipe> items,
  required void Function(List<FoodRecipe> next) onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _FoodRecipeManagerDialog(
      recipes: recipes,
      items: items,
      onChanged: onChanged,
    ),
  );
}

class _FoodRecipeEditorDialog extends StatefulWidget {
  const _FoodRecipeEditorDialog({
    required this.recipes,
    this.existing,
    required this.initialName,
  });

  final FoodRecipeService recipes;
  final FoodRecipe? existing;
  final String initialName;

  @override
  State<_FoodRecipeEditorDialog> createState() =>
      _FoodRecipeEditorDialogState();
}

class _FoodRecipeEditorDialogState extends State<_FoodRecipeEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.existing?.name ?? widget.initialName,
    );
    _note = TextEditingController(text: widget.existing?.note ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final note = _note.text.trim();
    if (name.isEmpty || note.isEmpty) {
      setState(() => _error = 'Informe o nome e o ajuste da receita.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = widget.existing == null
          ? await widget.recipes.create(name: name, note: note)
          : await widget.recipes.update(
              id: widget.existing!.id,
              name: name,
              note: note,
            );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userFacingError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nova receita' : 'Editar receita'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nome',
              hintText: 'Arroz da minha mãe',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Ajuste',
              hintText: 'leva mais óleo',
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Salvando…' : 'Salvar'),
        ),
      ],
    );
  }
}

class _FoodRecipeManagerDialog extends StatefulWidget {
  const _FoodRecipeManagerDialog({
    required this.recipes,
    required this.items,
    required this.onChanged,
  });

  final FoodRecipeService recipes;
  final List<FoodRecipe> items;
  final void Function(List<FoodRecipe> next) onChanged;

  @override
  State<_FoodRecipeManagerDialog> createState() =>
      _FoodRecipeManagerDialogState();
}

class _FoodRecipeManagerDialogState extends State<_FoodRecipeManagerDialog> {
  late List<FoodRecipe> _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _items = List<FoodRecipe>.from(widget.items);
  }

  void _publish() => widget.onChanged(List<FoodRecipe>.from(_items));

  Future<void> _edit(FoodRecipe recipe) async {
    final saved = await showFoodRecipeEditor(
      context,
      recipes: widget.recipes,
      existing: recipe,
    );
    if (saved == null) return;
    setState(() {
      final index = _items.indexWhere((item) => item.id == saved.id);
      if (index >= 0) _items[index] = saved;
    });
    _publish();
  }

  Future<void> _delete(FoodRecipe recipe) async {
    try {
      await widget.recipes.delete(recipe.id);
      if (!mounted) return;
      setState(() => _items.removeWhere((item) => item.id == recipe.id));
      _publish();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Receitas'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_items.isEmpty)
              const Text('Nenhuma receita salva.')
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final recipe in _items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(recipe.name),
                        subtitle: Text(recipe.note),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Editar',
                              onPressed: () => _edit(recipe),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Excluir',
                              onPressed: () => _delete(recipe),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
