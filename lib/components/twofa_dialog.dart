// two_factor_auth_dialog.dart
import 'package:flutter/material.dart';

class TwoFactorAuthDialog extends StatefulWidget {
  final String connectionName;
  final String host;
  final String prompt;
  final ValueChanged<String>? onCodeEntered;
  final VoidCallback? onCancel;

  const TwoFactorAuthDialog({
    Key? key,
    required this.connectionName,
    required this.host,
    required this.prompt,
    this.onCodeEntered,
    this.onCancel,
  }) : super(key: key);

  static Future<String?> show(
    BuildContext context, {
    required String connectionName,
    required String host,
    required String prompt,
  }) async {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TwoFactorAuthDialog(
        connectionName: connectionName,
        host: host,
        prompt: prompt,
      ),
    );
  }

  @override
  _TwoFactorAuthDialogState createState() => _TwoFactorAuthDialogState();
}

class _TwoFactorAuthDialogState extends State<TwoFactorAuthDialog> {
  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Text('2FA 验证'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '连接: ${widget.connectionName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('主机: ${widget.host}'),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: '验证码',
                hintText: '请输入验证器app内的验证码',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_clock),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel ?? () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('验证'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入验证码')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    await Future.delayed(const Duration(milliseconds: 300));

    if (widget.onCodeEntered != null) {
      widget.onCodeEntered!(code);
    }

    if (mounted) {
      Navigator.of(context).pop(code);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}
