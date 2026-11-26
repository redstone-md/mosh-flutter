import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_field.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_spinner.dart';
import 'package:mosh/src/features/onboarding/display_name_limit.dart';
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/inline_error.dart';

/// Shared name editor for setup and Settings. Persist before reporting success.
class DisplayNameForm extends StatefulWidget {
  const DisplayNameForm(
      {super.key,
      required this.initialName,
      required this.actionLabel,
      required this.onSave,
      this.showAvatar = true,
      this.showPlus = false,
      this.showSaveConfirmation = true,
      this.note});
  final String initialName;
  final String actionLabel;
  final Future<void> Function(String) onSave;

  /// The profile editor previews initials; setup leads straight to the field.
  final bool showAvatar;
  final bool showPlus;

  /// Settings confirms a save; the wizard confirms by moving to the next step.
  final bool showSaveConfirmation;

  /// Stands between the field and the button: what setup says about the name.
  final Widget? note;

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
      if (mounted) setState(() => _saved = widget.showSaveConfirmation);
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
            if (widget.showAvatar) ...[
              // Until there is a name to take initials from, the person sign.
              Center(
                  child: Avatar(
                      name: _name.text,
                      sign: _name.text.trim().isEmpty ? MoshIcons.person : null,
                      radius: MoshSpace.s12,
                      ownPlus: widget.showPlus)),
              const SizedBox(height: MoshSpace.s6),
            ],
            _field(l),
            if (widget.note case final note?) ...[
              const SizedBox(height: MoshSpace.s5),
              note,
            ],
            const SizedBox(height: MoshSpace.s5),
            MoshLoading(
              loading: _busy,
              child: FilledButton.icon(
                  onPressed: _save,
                  icon: _busy ? const MoshSpinner() : null,
                  label: Text(widget.actionLabel)),
            ),
            if (_error != null || _saved) ...[
              const SizedBox(height: MoshSpace.s3),
              if (_error != null)
                InlineError(message: _error)
              else
                Semantics(liveRegion: true, child: Text(l.firstRunNameSaved)),
            ],
          ],
        ));
  }

  Widget _field(AppLocalizations l) => MoshField(
        enabled: !_busy,
        label: l.setupDisplayNameLabel,
        child: TextFormField(
            controller: _name,
            enabled: !_busy,
            inputFormatters: const [DisplayNameLimit()],
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _save(),
            onChanged: (_) => setState(() => _saved = false),
            validator: (name) => name == null || name.trim().isEmpty
                ? l.firstRunNameRequired
                : null,
            decoration: InputDecoration(
                prefixIcon: const Icon(MoshIcons.person),
                counterText: '',
                helperText: l.firstRunNameHint,
                helperMaxLines: 3,
                errorMaxLines: 3)),
      );
}
