import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/avatar.dart';

/// Shared name editor for setup and Settings. Persist before reporting success.
class DisplayNameForm extends StatefulWidget {
  const DisplayNameForm(
      {super.key,
      required this.initialName,
      required this.actionLabel,
      required this.onSave});
  final String initialName;
  final String actionLabel;
  final Future<void> Function(String) onSave;

  @override
  State<DisplayNameForm> createState() => _DisplayNameFormState();
}

class _DisplayNameFormState extends State<DisplayNameForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  bool _busy = false;
  bool _saved = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      await widget.onSave(_name.text.trim());
      if (mounted) setState(() => _saved = true);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = AppLocalizations.of(context)!.firstRunSaveError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
                child: Theme(
                    data: Theme.of(context).copyWith(
                        textTheme: Theme.of(context).textTheme.copyWith(
                            labelMedium: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(fontSize: 28))),
                    child: Avatar(name: _name.text, radius: 48))),
            const SizedBox(height: 28),
            TextFormField(
                controller: _name,
                enabled: !_busy,
                maxLength: 64,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                onChanged: (_) => setState(() => _saved = false),
                validator: (name) => name == null || name.trim().isEmpty
                    ? l.firstRunNameRequired
                    : null,
                decoration: InputDecoration(
                    labelText: l.setupDisplayNameLabel,
                    prefixIcon: const Icon(Icons.person_outline),
                    counterText: '',
                    helperText: l.firstRunNameHint,
                    helperMaxLines: 3)),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? l.firstRunSaving : widget.actionLabel)),
            if (_error != null || _saved) ...[
              const SizedBox(height: 12),
              Semantics(
                  liveRegion: true,
                  child: Text(_error ?? l.firstRunNameSaved,
                      style: _error == null
                          ? null
                          : TextStyle(
                              color: Theme.of(context).colorScheme.error))),
            ],
          ],
        ));
  }
}
