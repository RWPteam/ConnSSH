// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/makefile.dart';
import 'package:highlight/languages/plaintext.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/github.dart';

class FileEditorPage extends StatefulWidget {
  final String filename;
  final String remotePath;
  final String initialContent;
  final Future<void> Function(String, Uint8List, String) saveCallback;

  const FileEditorPage({
    super.key,
    required this.filename,
    required this.remotePath,
    required this.initialContent,
    required this.saveCallback,
  });

  @override
  State<FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends State<FileEditorPage> {
  late CodeController _codeController;
  double _fontSize = 14.0;
  bool _isModified = false;
  bool _isSaving = false;
  bool _showSearch = false;

  bool get ismobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();

  final List<String> _history = [];
  int _historyIndex = -1;
  bool _isIgnoringListener = false;
  Timer? _historyTimer;

  final Map<String, dynamic> _languages = {
    '纯文本': plaintext,
    'Bash': bash,
    'C++': cpp,
    'CSS': css,
    'Dart': dart,
    'Go': go,
    'HTML/XML': xml,
    'Java': java,
    'Javascript': javascript,
    'JSON': json,
    'Kotlin': kotlin,
    'Markdown': markdown,
    'Makefile': makefile,
    'PHP': php,
    'Python': python,
    'Rust': rust,
    'SQL': sql,
    'Swift': swift,
    'YAML': yaml,
  };

  late String _currentLangKey;

  @override
  void initState() {
    super.initState();
    _currentLangKey = _detectLanguage(widget.filename);

    _codeController = CodeController(
      text: widget.initialContent,
      language: _languages[_currentLangKey],
    );

    _history.add(widget.initialContent);
    _historyIndex = 0;
    _codeController.addListener(_handleTextChange);
  }

  String _detectLanguage(String filename) {
    String ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return 'Dart';
      case 'py':
        return 'Python';
      case 'js':
        return 'Javascript';
      case 'ts':
        return 'Javascript';
      case 'json':
        return 'JSON';
      case 'html':
        return 'HTML/XML';
      case 'xml':
        return 'HTML/XML';
      case 'yaml':
        return 'YAML';
      case 'yml':
        return 'YAML';
      case 'sh':
        return 'Bash';
      case 'md':
        return 'Markdown';
      case 'go':
        return 'Go';
      case 'rs':
        return 'Rust';
      case 'php':
        return 'PHP';
      case 'sql':
        return 'SQL';
      case 'kt':
        return 'Kotlin';
      case 'swift':
        return 'Swift';
      case 'cpp':
        return 'C++';
      case 'cc':
        return 'C++';
      case 'h':
        return 'C++';
      case 'css':
        return 'CSS';
      case 'java':
        return 'Java';
      default:
        return '纯文本';
    }
  }

  void _handleTextChange() {
    if (_isIgnoringListener) return;
    if (!_isModified && _codeController.text != widget.initialContent) {
      setState(() => _isModified = true);
    }
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(milliseconds: 500), () {
      _saveToHistory(_codeController.text);
    });
  }

  void _saveToHistory(String text) {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    if (_history.isEmpty || _history.last != text) {
      _history.add(text);
      if (_history.length > 50) _history.removeAt(0);
      _historyIndex = _history.length - 1;
    }
  }

  void _undo() {
    if (_historyIndex > 0) {
      setState(() {
        _isIgnoringListener = true;
        _historyIndex--;
        _codeController.text = _history[_historyIndex];
        _isIgnoringListener = false;
      });
    }
  }

  Color _getAppBarColor() {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Theme.of(context).primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (!_isModified || await _confirmExit()) {
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        appBar: AppBar(
          toolbarHeight: 45,
          backgroundColor: _getAppBarColor(),
          foregroundColor: Colors.white,
          titleSpacing: 0,
          automaticallyImplyLeading: false,
          leading: ismobile
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          title: Padding(
            padding: EdgeInsets.only(left: ismobile ? 18.0 : 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.filename,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Icon(
                      _isModified ? Icons.circle : Icons.circle_outlined,
                      color: _isModified ? Colors.orangeAccent : Colors.white70,
                      size: 8,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.remotePath,
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(_isSaving ? Icons.sync : Icons.save, size: 20),
              onPressed: _isSaving ? null : _saveFile,
              tooltip: '保存文件',
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            _buildShortcutBar(isDark),
            _buildSearchPanel(isDark),
            Expanded(
              child: GestureDetector(
                onScaleUpdate: (details) {
                  if (details.scale != 1.0) {
                    setState(() {
                      _fontSize =
                          (_fontSize * (details.scale > 1 ? 1.01 : 0.99))
                              .clamp(8.0, 40.0);
                    });
                  }
                },
                child: CodeTheme(
                  data: CodeThemeData(
                      styles: isDark ? monokaiSublimeTheme : githubTheme),
                  child: Container(
                    color: isDark
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFFFCFCFC),
                    child: CodeField(
                      controller: _codeController,
                      textStyle: TextStyle(
                        fontFamily: 'hmossans',
                        fontSize: _fontSize,
                        height: 1.5,
                      ),
                      lineNumberStyle: LineNumberStyle(
                        width: 54,
                        margin: 10,
                        textStyle: TextStyle(
                          color:
                              isDark ? Colors.grey[600] : Colors.blueGrey[300],
                          fontSize: 12,
                        ),
                        background: isDark
                            ? const Color(0xFF252525)
                            : const Color(0xFFF5F5F5),
                      ),
                      cursorColor: Colors.blueAccent,
                      expands: true,
                      maxLines: null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutBar(bool isDark) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : Colors.grey[100],
        border: Border(
            bottom:
                BorderSide(color: isDark ? Colors.black54 : Colors.grey[300]!)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _toolBtn(Icons.search, "查找",
              () => setState(() => _showSearch = !_showSearch), isDark),
          _toolBtn(Icons.undo, "撤销", _undo, isDark),
          _toolBtn(Icons.text_increase, "", () => setState(() => _fontSize++),
              isDark),
          _toolBtn(Icons.text_decrease, "", () => setState(() => _fontSize--),
              isDark),
          const VerticalDivider(width: 1, indent: 10, endIndent: 10),
          PopupMenuButton<String>(
            tooltip: "切换语言",
            onSelected: (key) => setState(() {
              _currentLangKey = key;
              _codeController.language = _languages[key];
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.code,
                      size: 16,
                      color:
                          _currentLangKey == '纯文本' ? Colors.grey : Colors.blue),
                  const SizedBox(width: 6),
                  Text(_currentLangKey,
                      style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 12,
                          fontWeight: _currentLangKey == '纯文本'
                              ? FontWeight.normal
                              : FontWeight.bold)),
                  Icon(Icons.arrow_drop_down,
                      size: 16,
                      color: isDark ? Colors.white70 : Colors.black87),
                ],
              ),
            ),
            itemBuilder: (context) => _languages.keys
                .map((e) => PopupMenuItem(
                    value: e,
                    child: Text(e, style: const TextStyle(fontSize: 13))))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(
      IconData icon, String label, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(icon,
                size: 18, color: isDark ? Colors.white70 : Colors.black54),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 12))
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchPanel(bool isDark) {
    if (!_showSearch) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: isDark ? const Color(0xFF333333) : Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)
          ]),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _findController,
              decoration: const InputDecoration(
                  hintText: "查找内容",
                  isDense: true,
                  contentPadding: EdgeInsets.all(10),
                  border: OutlineInputBorder()),
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _replaceController,
              decoration: const InputDecoration(
                  hintText: "替换为",
                  isDense: true,
                  contentPadding: EdgeInsets.all(10),
                  border: OutlineInputBorder()),
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black, fontSize: 13),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.done_all, color: Colors.blue),
            onPressed: () {
              if (_findController.text.isEmpty) return;
              final text = _codeController.text
                  .replaceAll(_findController.text, _replaceController.text);
              _codeController.text = text;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("已完成全部替换"), duration: Duration(seconds: 1)));
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _showSearch = false),
          )
        ],
      ),
    );
  }

  Future<void> _saveFile() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final contentBytes = utf8.encode(_codeController.text);
      await widget.saveCallback(
          widget.remotePath, Uint8List.fromList(contentBytes), widget.filename);
      if (mounted) {
        setState(() {
          _isModified = false;
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("保存失败: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<bool> _confirmExit() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('提醒'),
            content: const Text('当前更改尚未保存，确定要退出编辑吗？'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('继续编辑')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child:
                      const Text('放弃保存', style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    _codeController.dispose();
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }
}
