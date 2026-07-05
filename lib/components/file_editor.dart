// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter/scheduler.dart';

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
  final Future<bool> Function(String, Uint8List, String) saveCallback;

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
  late FocusNode _focusNode;

  bool _controllerReady = false;
  bool _isHandlingBackGesture = false;

  double _fontSize = 14.0;
  bool _isModified = false;
  bool _isSaving = false;
  bool _showSearch = false;
  bool _showReplaceRow = false;
  bool _isLoading = true;

  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();

  List<TextRange> _matches = [];

  final List<String> _history = [];
  int _historyIndex = -1;
  bool _isIgnoringListener = false;
  Timer? _historyTimer;

  final GlobalKey _codeFieldKey = GlobalKey(debugLabel: 'CodeField');

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

  TextStyle get _editorTextStyle {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      height: 1.35,
    );
  }

  TextStyle _lineNumberTextStyle(bool isDark) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: _fontSize,
      height: 1.35,
      color: isDark ? Colors.grey[600] : Colors.blueGrey[300],
    );
  }

  @override
  void initState() {
    super.initState();

    _focusNode = FocusNode();
    _currentLangKey = _detectLanguage(widget.filename);

    if (widget.initialContent.length > 100 * 1024 &&
        _currentLangKey != '纯文本') {
      _currentLangKey = '纯文本';

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件较大，已关闭代码高亮')),
        );
      });
    }

    _initCodeControllerAsync();
  }

  void _initCodeControllerAsync() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _codeController = CodeController(
        text: widget.initialContent,
        language: _languages[_currentLangKey],
      );

      _controllerReady = true;

      _history.add(widget.initialContent);
      _historyIndex = 0;

      _codeController.addListener(_handleTextChange);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  String _detectLanguage(String filename) {
    final ext = filename.split('.').last.toLowerCase();

    switch (ext) {
      case 'dart':
        return 'Dart';
      case 'py':
        return 'Python';
      case 'js':
      case 'ts':
        return 'Javascript';
      case 'json':
        return 'JSON';
      case 'html':
      case 'xml':
        return 'HTML/XML';
      case 'yaml':
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
      case 'cc':
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
      if (!_controllerReady) return;
      _saveToHistory(_codeController.text);
    });

    _matches.clear();
  }

  void _saveToHistory(String text) {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }

    if (_history.isEmpty || _history.last != text) {
      _history.add(text);

      if (_history.length > 50) {
        _history.removeAt(0);
      }

      _historyIndex = _history.length - 1;
    }
  }

  void _undo() {
    if (_historyIndex > 0) {
      setState(() {
        _isIgnoringListener = true;

        _historyIndex--;

        final newText = _history[_historyIndex];

        _codeController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );

        _isModified = newText != widget.initialContent;
        _isIgnoringListener = false;
      });
    }
  }

  void _findAllMatches() {
    final findText = _findController.text;

    if (findText.isEmpty) {
      _matches.clear();
      return;
    }

    final text = _codeController.text;
    final regex = RegExp(RegExp.escape(findText));
    final matches = regex.allMatches(text);

    _matches = matches
        .map((m) => TextRange(start: m.start, end: m.end))
        .toList();
  }

  void _goToMatch(int index) {
    if (index < 0 || index >= _matches.length) return;

    final match = _matches[index];

    _codeController.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _codeFieldKey.currentState;

      if (state != null) {
        try {
          (state as dynamic).ensureOffsetVisible(match.start);
        } catch (_) {
          // 部分 code_text_field 版本没有 ensureOffsetVisible，忽略即可。
        }
      }
    });
  }

  void _findNext() {
    if (_findController.text.isEmpty) return;

    _findAllMatches();

    if (_matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未找到匹配内容'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    final cursor = _codeController.selection.baseOffset;

    int newIndex = 0;

    for (int i = 0; i < _matches.length; i++) {
      if (_matches[i].start > cursor) {
        newIndex = i;
        break;
      }
    }

    _goToMatch(newIndex);
  }

  void _findPrevious() {
    if (_findController.text.isEmpty) return;

    _findAllMatches();

    if (_matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未找到匹配内容'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    final cursor = _codeController.selection.baseOffset;

    int newIndex = _matches.length - 1;

    for (int i = _matches.length - 1; i >= 0; i--) {
      if (_matches[i].start < cursor) {
        newIndex = i;
        break;
      }
    }

    _goToMatch(newIndex);
  }

  void _replaceSingle() {
    final findText = _findController.text;
    final replaceText = _replaceController.text;

    if (findText.isEmpty) return;

    _findAllMatches();

    if (_matches.isEmpty) return;

    final cursor = _codeController.selection.baseOffset;

    int targetIndex = -1;

    for (int i = 0; i < _matches.length; i++) {
      if (_matches[i].start >= cursor) {
        targetIndex = i;
        break;
      }
    }

    if (targetIndex == -1 && _matches.isNotEmpty) {
      targetIndex = 0;
    }

    final match = _matches[targetIndex];
    final text = _codeController.text;

    final newText =
        text.substring(0, match.start) +
        replaceText +
        text.substring(match.end);

    _codeController.text = newText;

    final newCursor = match.start + replaceText.length;

    _codeController.selection = TextSelection.collapsed(offset: newCursor);

    _markModified();
    _findAllMatches();

    if (_matches.isNotEmpty) {
      _goToMatch(0);
    }
  }

  void _replaceAll() {
    final findText = _findController.text;
    final replaceText = _replaceController.text;

    if (findText.isEmpty) return;

    final newText = _codeController.text.replaceAll(findText, replaceText);

    _codeController.text = newText;

    _markModified();
    _findAllMatches();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('全部替换完成'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _markModified() {
    if (!_isModified) {
      setState(() => _isModified = true);
    }
  }

  Future<void> _handleExit() async {
    if (!_isModified || await _confirmExit()) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Color _getAppBarColor() {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1E1E1E)
        : Theme.of(context).primaryColor;
  }

  Widget _buildIOSBackGestureWrapper({
    required Widget child,
  }) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return child;
    }

    double dragStartX = 0;
    double dragDistance = 0;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        dragStartX = details.globalPosition.dx;
        dragDistance = 0;
      },
      onHorizontalDragUpdate: (details) {
        if (dragStartX > 24) return;

        final delta = details.primaryDelta ?? 0;

        if (delta > 0) {
          dragDistance += delta;
        }
      },
      onHorizontalDragEnd: (details) async {
        if (_isHandlingBackGesture) return;

        final velocity = details.primaryVelocity ?? 0;

        final shouldTriggerBack =
            dragStartX <= 24 && (dragDistance > 80 || velocity > 500);

        if (!shouldTriggerBack) return;

        _isHandlingBackGesture = true;

        try {
          await _handleExit();
        } finally {
          if (mounted) {
            _isHandlingBackGesture = false;
          }
        }
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        await _handleExit();
      },
      child: _buildIOSBackGestureWrapper(
        child: Scaffold(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          appBar: AppBar(
            toolbarHeight: 45,
            backgroundColor: _getAppBarColor(),
            foregroundColor: Colors.white,
            titleSpacing: 0,
            automaticallyImplyLeading: false,
            leading: null,
            title: Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.filename,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Icon(
                        _isModified ? Icons.circle : Icons.circle_outlined,
                        color:
                            _isModified ? Colors.greenAccent : Colors.white70,
                        size: 8,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.remotePath,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
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
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildShortcutBar(isDark),
                    if (_showSearch) ...[
                      _buildSearchRow(isDark),
                      if (_showReplaceRow) _buildReplaceRow(isDark),
                    ],
                    Expanded(
                      child: CodeTheme(
                        data: CodeThemeData(
                          styles: isDark ? monokaiSublimeTheme : githubTheme,
                        ),
                        child: Container(
                          color: isDark
                              ? const Color(0xFF1E1E1E)
                              : const Color(0xFFFCFCFC),
                          child: CodeField(
                            controller: _codeController,
                            focusNode: _focusNode,
                            fieldKey: _codeFieldKey,
                            keyboardType: TextInputType.multiline,
                            textStyle: _editorTextStyle,
                            lineNumberStyle: LineNumberStyle(
                              width: 96,
                              margin: 2,
                              textStyle: _lineNumberTextStyle(isDark),
                              background: isDark
                                  ? const Color(0xFF252525)
                                  : const Color(0xFFF5F5F5),
                            ),
                            cursorColor: Colors.blueAccent,
                            expands: true,
                            maxLines: null,
                            wrap: false,
                            horizontalScroll: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
          bottom: BorderSide(
            color: isDark ? Colors.black54 : Colors.grey[300]!,
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _toolBtn(
            Icons.search,
            '查找',
            () => setState(() => _showSearch = !_showSearch),
            isDark,
          ),
          _toolBtn(Icons.undo, '撤销', _undo, isDark),
          _toolBtn(
            Icons.text_increase,
            '',
            () => setState(() => _fontSize++),
            isDark,
          ),
          _toolBtn(
            Icons.text_decrease,
            '',
            () {
              if (_fontSize <= 8) return;
              setState(() => _fontSize--);
            },
            isDark,
          ),
          const VerticalDivider(width: 1, indent: 10, endIndent: 10),
          PopupMenuButton<String>(
            tooltip: '切换语言',
            onSelected: (key) {
              setState(() {
                _currentLangKey = key;
                _codeController.language = _languages[key];
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.code,
                    size: 16,
                    color: _currentLangKey == '纯文本'
                        ? Colors.grey
                        : Colors.blue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _currentLangKey,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                      fontSize: 12,
                      fontWeight: _currentLangKey == '纯文本'
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ],
              ),
            ),
            itemBuilder: (context) {
              return _languages.keys
                  .map(
                    (e) => PopupMenuItem(
                      value: e,
                      child: Text(
                        e,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                  .toList();
            },
          ),
        ],
      ),
    );
  }

  Widget _toolBtn(
    IconData icon,
    String label,
    VoidCallback onTap,
    bool isDark,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchRow(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF333333) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _findController,
              decoration: const InputDecoration(
                hintText: '查找内容',
                isDense: true,
                contentPadding: EdgeInsets.all(10),
                border: OutlineInputBorder(),
              ),
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 13,
              ),
              onChanged: (_) {
                _matches.clear();
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.find_replace,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: () {
              setState(() => _showReplaceRow = !_showReplaceRow);
            },
            tooltip: '替换',
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_upward,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: _findPrevious,
            tooltip: '上一个',
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_downward,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: _findNext,
            tooltip: '下一个',
          ),
        ],
      ),
    );
  }

  Widget _buildReplaceRow(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3A3A) : Colors.grey[50],
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.black54 : Colors.grey[300]!,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _replaceController,
              decoration: const InputDecoration(
                hintText: '替换为',
                isDense: true,
                contentPadding: EdgeInsets.all(10),
                border: OutlineInputBorder(),
              ),
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.repeat_one,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: _replaceSingle,
            tooltip: '替换单个',
          ),
          IconButton(
            icon: Icon(
              Icons.done_all,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: _replaceAll,
            tooltip: '全部替换',
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: () => setState(() => _showReplaceRow = false),
            tooltip: '退出替换',
          ),
        ],
      ),
    );
  }

  Future<void> _saveFile() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      final contentBytes = utf8.encode(_codeController.text);

      final success = await widget.saveCallback(
        widget.remotePath,
        Uint8List.fromList(contentBytes),
        widget.filename,
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          _isModified = false;
          _isSaving = false;
        });
      } else {
        setState(() => _isSaving = false);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _confirmExit() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              title: const Text('未保存的更改'),
              content: const Text(
                '当前文件有未保存的更改，确定要退出吗？\n\n退出后将丢失所有修改。',
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('继续编辑'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    '放弃保存并退出',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  @override
  void dispose() {
    _historyTimer?.cancel();

    if (_controllerReady) {
      _codeController.removeListener(_handleTextChange);
      _codeController.dispose();
    }

    _findController.dispose();
    _replaceController.dispose();
    _focusNode.dispose();

    super.dispose();
  }
}