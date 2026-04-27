import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchField extends StatefulWidget {
  final Function(String) onQueryChanged;
  final VoidCallback onSearch;

  const SearchField({Key? key, required this.onQueryChanged, required this.onSearch}) : super(key: key);

  @override
  _SearchFieldState createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  final TextEditingController _controller = TextEditingController();
  List<String> _searchHistory = []; // Beispiel Historie

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    // Lade gespeicherte Suchhistorie
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _searchHistory = prefs.getStringList('searchHistory') ?? [];
    });
  }

  Future<void> _saveHistory(String query) async {
    if (query.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    _searchHistory.remove(query);
    _searchHistory.insert(0, query);
    if (_searchHistory.length > 10) _searchHistory = _searchHistory.sublist(0, 10);
    await prefs.setStringList('searchHistory', _searchHistory);
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return CupertinoSearchTextField(
        controller: _controller,
        placeholder: 'Suchen...',
        onChanged: widget.onQueryChanged,
        onSubmitted: (_) {
          _saveHistory(_controller.text);
          widget.onSearch();
        },
      );
    } else {
      return Autocomplete<String>(
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text == '') {
            return const Iterable<String>.empty();
          }
          return _searchHistory.where((String option) {
            return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
          });
        },
        onSelected: (String selection) {
          _controller.text = selection;
          widget.onQueryChanged(selection);
          widget.onSearch();
        },
        fieldViewBuilder: (BuildContext context, TextEditingController fieldTextEditingController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
          _controller.addListener(() {
            if (_controller.text != fieldTextEditingController.text) {
              fieldTextEditingController.text = _controller.text;
            }
          });
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Suchen...',
                          border: InputBorder.none,
                        ),
                        onChanged: (val) {
                          _controller.text = val;
                          widget.onQueryChanged(val);
                        },
                        onSubmitted: (_) {
                          _saveHistory(fieldTextEditingController.text);
                          onFieldSubmitted();
                          widget.onSearch();
                        },
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.search),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _saveHistory(fieldTextEditingController.text);
                        widget.onSearch();
                      },
                    ),
                    if (fieldTextEditingController.text.isNotEmpty)
                      IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          fieldTextEditingController.clear();
                          _controller.clear();
                          widget.onQueryChanged('');
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
  }
}
