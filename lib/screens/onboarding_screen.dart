import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import '../logic/state_provider.dart';
import '../theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _page = 1;
  static const int _totalPages = 8;

  final TextEditingController _berufController = TextEditingController();
  final TextEditingController _jahrController = TextEditingController();
  final TextEditingController _plzController = TextEditingController();
  List<String> _sources = ['alle'];
  List<String> _files = ['alle'];
  String _language = 'de';
  String _country = 'de';
  String _searchengine = 'google';
  bool _allowFeedback = false;
  bool _enableYouthProtection = true;

  @override
  void initState() {
    super.initState();
    _jahrController.text = '1990';
  }

  void _go(int p) {
    if (p < 1 || p > _totalPages) return;
    setState(() => _page = p);
  }

  bool _validatePage1() {
    if (_berufController.text.trim().isEmpty) {
      _showError('Bitte gib deinen Beruf ein.');
      return false;
    }
    return true;
  }

  bool _validatePage2() {
    final jahr = int.tryParse(_jahrController.text);
    if (jahr == null || jahr < 1930 || jahr > 2015) {
      _showError('Bitte gueltiges Jahr (1930-2015) eingeben.');
      return false;
    }
    return true;
  }

  void _showError(String msg) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Fehler'),
        content: Text(msg),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAll() async {
    final notifier = ref.read(settingsProvider.notifier);
    final newState = SettingsState(
      plz: _plzController.text.trim(),
      beruf: _berufController.text.trim(),
      searchEngine: _searchengine,
      language: _language,
      country: _country,
      allowFeedback: _allowFeedback,
      enableYouthProtection: _enableYouthProtection,
      jahr: int.parse(_jahrController.text),
      sources: _sources,
      files: _files,
      mode: 'standard',
    );
    await notifier.updateSettings(newState);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: FindUXProTheme.primaryPurple,
      child: Container(
        decoration: const BoxDecoration(
          gradient: FindUXProTheme.primaryGradient,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Row(
                            children: [
                              Text(
                                '${AppLocalizations.of(context)!.appTitle} Pro',
                                style: FindUXProTheme.headlineStyle.copyWith(
                                  color: Colors.white,
                                  fontSize: 28,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '$_page/$_totalPages',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _page / _totalPages,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                              minHeight: 6,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: _buildPage(),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          child: Row(
                            children: [
                              if (_page > 1)
                                Expanded(
                                  child: ElevatedButton(
                                    style: FindUXProTheme.glassButtonStyle,
                                    onPressed: () => _go(_page - 1),
                                    child: Text(
                                        AppLocalizations.of(context)!.back),
                                  ),
                                ),
                              if (_page > 1) const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor:
                                        FindUXProTheme.primaryPurple,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            FindUXProTheme.squircleRadius),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                  ),
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    if (_page == 1 && !_validatePage1()) return;
                                    if (_page == 2 && !_validatePage2()) return;

                                    if (_page == _totalPages) {
                                      await _saveAll();
                                      widget.onComplete();
                                    } else {
                                      _go(_page + 1);
                                    }
                                  },
                                  child: Text(
                                    _page == _totalPages
                                        ? AppLocalizations.of(context)!.start
                                        : AppLocalizations.of(context)!.next,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPage() {
    switch (_page) {
      case 1:
        return _buildPage1();
      case 2:
        return _buildPage2();
      case 3:
        return _buildPage3();
      case 4:
        return _buildPage4();
      case 5:
        return _buildPage5();
      case 6:
        return _buildPage6();
      case 7:
        return _buildPage7();
      case 8:
        return _buildPage8();
      default:
        return Container();
    }
  }

  Widget _buildPage1() {
    return _buildInputCard(
      title: 'Dein Beruf',
      description:
          'In welchem Bereich arbeitest du? Dies hilft uns, passende Quellen vorzuwaehlen.',
      child: CupertinoTextField(
        controller: _berufController,
        placeholder: 'z.B. Softwareentwickler, Student',
        padding: const EdgeInsets.all(16),
        style: const TextStyle(color: Colors.white),
        placeholderStyle: const TextStyle(color: Colors.white54),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
      ),
    );
  }

  Widget _buildPage2() {
    return _buildInputCard(
      title: 'Jahrgang',
      description:
          'Dein Abiturjahr oder Geburtsjahr hilft uns, zeitliche Filter zu setzen.',
      child: CupertinoTextField(
        controller: _jahrController,
        placeholder: 'z.B. 1990',
        keyboardType: TextInputType.number,
        padding: const EdgeInsets.all(16),
        style: const TextStyle(color: Colors.white),
        placeholderStyle: const TextStyle(color: Colors.white54),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
      ),
    );
  }

  Widget _buildPage3() {
    return _buildInputCard(
      title: 'Region (PLZ)',
      description: 'Deine Postleitzahl ermoeglicht regionalisierte Suchen.',
      child: CupertinoTextField(
        controller: _plzController,
        placeholder: 'z.B. 10115',
        keyboardType: TextInputType.number,
        padding: const EdgeInsets.all(16),
        style: const TextStyle(color: Colors.white),
        placeholderStyle: const TextStyle(color: Colors.white54),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
      ),
    );
  }

  Widget _buildPage4() {
    return _buildChipSelectionPage(
      title: 'Seitenquellen',
      description: 'Waehle deine bevorzugten Quellen aus.',
      items: const [
        {'v': 'alle', 'icon': '🌐', 'label': 'Alle'},
        {'v': 'foren', 'icon': '💬', 'label': 'Foren'},
        {'v': 'reddit', 'icon': '🟠', 'label': 'Reddit'},
        {'v': 'news', 'icon': '📰', 'label': 'News'},
        {'v': 'wikipedia', 'icon': '📚', 'label': 'Wikipedia'},
        {'v': 'offiziell', 'icon': '🏛️', 'label': 'Offiziell'},
        {'v': 'academic', 'icon': '🎓', 'label': 'Akademisch'},
        {'v': 'video', 'icon': '🎥', 'label': 'Video'},
        {'v': 'blogs', 'icon': '✍️', 'label': 'Blogs'},
        {'v': 'shops', 'icon': '🛒', 'label': 'Shops'},
        {'v': 'social', 'icon': '👥', 'label': 'Sozial'},
      ],
      selected: _sources,
      onChanged: (sel) => setState(() => _sources = sel),
    );
  }

  Widget _buildPage5() {
    return _buildChipSelectionPage(
      title: 'Dateitypen',
      description: 'Welche Dateiformate bevorzugst du?',
      items: const [
        {'v': 'alle', 'icon': '📄', 'label': 'Alle'},
        {'v': 'pdf', 'icon': '📕', 'label': 'PDF'},
        {'v': 'ppt', 'icon': '📊', 'label': 'PPT'},
        {'v': 'doc', 'icon': '📝', 'label': 'DOC'},
        {'v': 'xls', 'icon': '📈', 'label': 'XLS'},
        {'v': 'code', 'icon': '💻', 'label': 'Code'},
        {'v': 'images', 'icon': '🖼️', 'label': 'Bilder'},
      ],
      selected: _files,
      onChanged: (sel) => setState(() => _files = sel),
    );
  }

  Widget _buildPage6() {
    return _buildInputCard(
      title: 'Sprache & Region',
      description: 'Waehle deine bevorzugte Sprache und dein Land.',
      child: Column(
        children: [
          _buildPickerButton(
              'Sprache',
              _languages.firstWhere((l) => l[0] == _language)[1],
              () {
            _showPicker(
                _languages, _language, (val) => setState(() => _language = val));
          }),
          const SizedBox(height: 16),
          _buildPickerButton(
              'Land', _countries.firstWhere((c) => c[0] == _country)[1], () {
            _showPicker(
                _countries, _country, (val) => setState(() => _country = val));
          }),
        ],
      ),
    );
  }

  Widget _buildPage7() {
    return _buildInputCard(
      title: 'Suchmaschine',
      description: 'Welche Suchmaschine moechtest du nutzen?',
      child: Column(
        children: ['google', 'bing', 'duckduckgo'].map((e) {
          final isSel = _searchengine == e;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () => setState(() => _searchengine = e),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSel
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Text(
                      e == 'google'
                          ? 'Google'
                          : e == 'bing'
                              ? 'Bing'
                              : 'DuckDuckGo',
                      style: TextStyle(
                        color: isSel
                            ? FindUXProTheme.primaryPurple
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (isSel)
                      const Icon(Icons.check_circle,
                          color: FindUXProTheme.primaryPurple),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPage8() {
    return _buildInputCard(
      title: 'Fast geschafft!',
      description:
          'Moechtest du uns Feedback geben, wenn ein Ergebnis nicht passt?',
      child: Column(
        children: [
          _buildSwitchTile('Feedback ermoeglichen', _allowFeedback,
              (v) => setState(() => _allowFeedback = v)),
          const SizedBox(height: 12),
          _buildSwitchTile('Jugendschutz aktivieren', _enableYouthProtection,
              (v) => setState(() => _enableYouthProtection = v)),
          const SizedBox(height: 32),
          const Text(
            'Deine Einstellungen werden verschluesselt auf diesem Geraet gespeichert.\nDu kannst sie jederzeit aendern.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard(
      {required String title,
      required String description,
      required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 12),
        Text(description,
            style: const TextStyle(fontSize: 15, color: Colors.white70)),
        const SizedBox(height: 24),
        child,
      ],
    );
  }

  Widget _buildChipSelectionPage({
    required String title,
    required String description,
    required List<Map<String, String>> items,
    required List<String> selected,
    required void Function(List<String>) onChanged,
  }) {
    return _buildInputCard(
      title: title,
      description: description,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: items.map((item) {
          final isSel = selected.contains(item['v']!);
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              List<String> newSel = List.from(selected);
              if (item['v'] == 'alle') {
                newSel = isSel ? [] : [item['v']!];
              } else {
                if (isSel) {
                  newSel.remove(item['v']!);
                  if (newSel.isEmpty) newSel = ['alle'];
                } else {
                  newSel.add(item['v']!);
                  newSel.remove('alle');
                }
              }
              onChanged(newSel);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isSel
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: isSel ? Colors.white : Colors.white24),
              ),
              child: Text(
                '${item['icon']} ${item['label']}',
                style: TextStyle(
                  color: isSel ? FindUXProTheme.primaryPurple : Colors.white,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPickerButton(String label, String value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            const Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
      String label, bool value, void Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500)),
          const Spacer(),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white24,
          ),
        ],
      ),
    );
  }

  void _showPicker(List<List<String>> data, String currentValue,
      void Function(String) onSave) {
    final initialIndex = data.indexWhere((d) => d[0] == currentValue);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: 250,
        color: Colors.white,
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: CupertinoPicker(
                scrollController:
                    FixedExtentScrollController(initialItem: initialIndex),
                itemExtent: 40,
                onSelectedItemChanged: (i) => onSave(data[i][0]),
                children:
                    data.map((d) => Center(child: Text(d[1]))).toList(),
              ),
            ),
            CupertinoButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      ),
    );
  }

  // Aktuell sind nur Deutsch und Englisch in der App lokalisiert.
  // Weitere Sprachen werden ergaenzt, sobald die l10n-Dateien existieren.
  static const List<List<String>> _languages = [
    ['de', 'Deutsch'],
    ['en', 'English'],
  ];
  static const List<List<String>> _countries = [
    ['de', 'Deutschland'],
    ['at', 'Oesterreich'],
    ['ch', 'Schweiz'],
    ['us', 'USA'],
    ['uk', 'Grossbritannien'],
  ];

  @override
  void dispose() {
    _berufController.dispose();
    _jahrController.dispose();
    _plzController.dispose();
    super.dispose();
  }
}
