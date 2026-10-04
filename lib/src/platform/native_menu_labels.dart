import 'package:mosh/l10n/app_localizations.dart';

/// Stable identifiers connect translations to the existing Cocoa menu items.
Map<String, String> nativeMenuLabels(AppLocalizations l) => {
      ..._appLabels(l),
      ..._editLabels(l),
      ..._windowLabels(l),
      'nativeMenuExitFullScreen': l.nativeMenuExitFullScreen,
    };

Map<String, String> _appLabels(AppLocalizations l) => {
      'nativeMenuAboutMosh': l.nativeMenuAboutMosh,
      'nativeMenuPreferencesAction': l.nativeMenuPreferencesAction,
      'nativeMenuServices': l.nativeMenuServices,
      'nativeMenuHideMosh': l.nativeMenuHideMosh,
      'nativeMenuHideOthers': l.nativeMenuHideOthers,
      'nativeMenuShowAll': l.nativeMenuShowAll,
      'nativeMenuQuitMosh': l.nativeMenuQuitMosh,
    };

Map<String, String> _editLabels(AppLocalizations l) => {
      'nativeMenuEdit': l.nativeMenuEdit,
      'nativeMenuUndo': l.nativeMenuUndo,
      'nativeMenuRedo': l.nativeMenuRedo,
      'nativeMenuCut': l.nativeMenuCut,
      'nativeMenuCopy': l.nativeMenuCopy,
      'nativeMenuPaste': l.nativeMenuPaste,
      'nativeMenuPasteAndMatchStyle': l.nativeMenuPasteAndMatchStyle,
      'nativeMenuDelete': l.nativeMenuDelete,
      'nativeMenuSelectAll': l.nativeMenuSelectAll,
      'nativeMenuFind': l.nativeMenuFind,
      'nativeMenuFindAction': l.nativeMenuFindAction,
      'nativeMenuFindAndReplaceAction': l.nativeMenuFindAndReplaceAction,
      'nativeMenuFindNext': l.nativeMenuFindNext,
      'nativeMenuFindPrevious': l.nativeMenuFindPrevious,
      'nativeMenuUseSelectionForFind': l.nativeMenuUseSelectionForFind,
      'nativeMenuJumpToSelection': l.nativeMenuJumpToSelection,
      'nativeMenuSpellingAndGrammar': l.nativeMenuSpellingAndGrammar,
      'nativeMenuShowSpellingAndGrammar': l.nativeMenuShowSpellingAndGrammar,
      'nativeMenuCheckDocumentNow': l.nativeMenuCheckDocumentNow,
      'nativeMenuCheckSpellingWhileTyping':
          l.nativeMenuCheckSpellingWhileTyping,
      'nativeMenuCheckGrammarWithSpelling':
          l.nativeMenuCheckGrammarWithSpelling,
      'nativeMenuCorrectSpellingAutomatically':
          l.nativeMenuCorrectSpellingAutomatically,
      'nativeMenuSubstitutions': l.nativeMenuSubstitutions,
      'nativeMenuShowSubstitutions': l.nativeMenuShowSubstitutions,
      'nativeMenuSmartCopyPaste': l.nativeMenuSmartCopyPaste,
      'nativeMenuSmartQuotes': l.nativeMenuSmartQuotes,
      'nativeMenuSmartDashes': l.nativeMenuSmartDashes,
      'nativeMenuSmartLinks': l.nativeMenuSmartLinks,
      'nativeMenuDataDetectors': l.nativeMenuDataDetectors,
      'nativeMenuTextReplacement': l.nativeMenuTextReplacement,
      'nativeMenuTransformations': l.nativeMenuTransformations,
      'nativeMenuMakeUpperCase': l.nativeMenuMakeUpperCase,
      'nativeMenuMakeLowerCase': l.nativeMenuMakeLowerCase,
      'nativeMenuCapitalize': l.nativeMenuCapitalize,
      'nativeMenuSpeech': l.nativeMenuSpeech,
      'nativeMenuStartSpeaking': l.nativeMenuStartSpeaking,
      'nativeMenuStopSpeaking': l.nativeMenuStopSpeaking,
    };

Map<String, String> _windowLabels(AppLocalizations l) => {
      'nativeMenuView': l.nativeMenuView,
      'nativeMenuEnterFullScreen': l.nativeMenuEnterFullScreen,
      'nativeMenuWindow': l.nativeMenuWindow,
      'nativeMenuMinimize': l.nativeMenuMinimize,
      'nativeMenuZoom': l.nativeMenuZoom,
      'nativeMenuBringAllToFront': l.nativeMenuBringAllToFront,
      'nativeMenuHelp': l.nativeMenuHelp,
    };
