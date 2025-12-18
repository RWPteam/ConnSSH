import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:basic_utils/basic_utils.dart';

class ReadKeyInfoPage extends StatefulWidget {
  const ReadKeyInfoPage({super.key});

  @override
  State<ReadKeyInfoPage> createState() => _ReadKeyInfoPageState();
}

class _ReadKeyInfoPageState extends State<ReadKeyInfoPage> {
  String? _fileName;
  String? _keyContent;
  bool _isProcessing = false;
  bool _isOhos = defaultTargetPlatform == TargetPlatform.ohos;
  Map<String, String> _parsedInfo = {};
  bool _showPasteField = false;
  final TextEditingController _pasteController = TextEditingController();

  void _parseInput(String content) {
    if (content.trim().isEmpty) return;

    Map<String, String> info = {};
    String trimmed = content.trim();

    // 定义常用签名算法 OID 映射
    const oidMap = {
      '1.2.840.113549.1.1.11': 'sha256WithRSAEncryption',
      '1.2.840.113549.1.1.12': 'sha384WithRSAEncryption',
      '1.2.840.113549.1.1.13': 'sha512WithRSAEncryption',
      '1.2.840.113549.1.1.5': 'sha1WithRSAEncryption',
      '1.2.840.10045.4.3.2': 'ecdsa-with-sha256',
    };

    try {
      info["文件名"] = _fileName ?? "未命名";
      if (trimmed.contains("BEGIN CERTIFICATE")) {
        info["类型"] = "X.509 证书";

        var data = X509Utils.x509CertificateFromPem(trimmed);

        // 1. 优化主体获取：优先获取 CN，否则拼接完整信息
        String getReadableName(Map<String, dynamic> dnMap) {
          if (dnMap.containsKey('CN') && dnMap['CN'] != null) {
            return dnMap['CN'].toString();
          }
          // 如果没有 CN，则把所有的 key-value 拼起来 (如 C=CN, O=Google...)
          return dnMap.entries.map((e) => "${e.key}=${e.value}").join(", ");
        }

        info["主体"] = getReadableName(data.subject);
        info["颁发者"] = getReadableName(data.issuer);

        // 2. 时间解析
        DateTime notBefore = data.validity.notBefore;
        DateTime notAfter = data.validity.notAfter;
        info["生效时间"] = notBefore.toLocal().toString().split('.')[0];
        info["过期时间"] = notAfter.toLocal().toString().split('.')[0];

        bool isExpired = DateTime.now().isAfter(notAfter);
        info["状态"] = isExpired ? "已过期" : "有效中";

        // 3. 签名算法 OID 转换
        String sigOid = data.signatureAlgorithm ?? "";
        info["签名算法"] = oidMap[sigOid] ?? sigOid; // 找不到映射则显示原始 OID
      } else if (trimmed.contains("BEGIN RSA PRIVATE KEY") ||
          trimmed.contains("BEGIN PRIVATE KEY")) {
        info["类型"] = "私钥 (Private Key)";
        info["格式"] = trimmed.contains("RSA") ? "PKCS#1" : "PKCS#8";
      }
      // ... 其他分支逻辑保持不变
    } catch (e) {
      info["解析状态"] = "证书结构解析失败";
      info["详情"] = "错误原因: $e";
    }

    info["字符长度"] = "${content.length} 字符";

    setState(() {
      _parsedInfo = info;
      _keyContent = content;
      _showPasteField = false;
    });
  }

  void _copyToClipboard() {
    if (_parsedInfo.isEmpty) return;
    String summary =
        _parsedInfo.entries.map((e) => "${e.key}: ${e.value}").join("\n");
    Clipboard.setData(ClipboardData(text: summary)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('解析结果已复制')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('密钥/证书解析')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isOhos) ...[
              _buildActionButton(
                onPressed: _pickKeyFile,
                title: '选择本地文件',
              ),
              const SizedBox(height: 16),
            ],
            _buildActionButton(
              onPressed: () => {
                setState(() => _showPasteField = !_showPasteField),
                if (_showPasteField) {_pasteController.clear()}
              },
              title: '从剪贴板粘贴',
            ),
            if (_showPasteField) _buildPasteArea(),
            if (_parsedInfo.isNotEmpty) _buildResultSection(),
            if (_keyContent != null) _buildPreviewArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildPasteArea() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          TextField(
            controller: _pasteController,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'maple', fontSize: 12),
            decoration: const InputDecoration(
                hintText: '在此粘贴内容...', border: InputBorder.none),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => _parseInput(_pasteController.text),
                child: const Text('解析'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultSection() {
    return Column(
      children: [
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('解析结果',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (!_isOhos)
              IconButton(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy, size: 18)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: _parsedInfo.entries
                .map((e) => _buildInfoRow(e.key, e.value))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text('内容预览', style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8)),
          child: Text(
            _keyContent!.length > 200
                ? "${_keyContent!.substring(0, 200)}..."
                : _keyContent!,
            style: const TextStyle(
                fontFamily: 'maple', fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required String title,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 90,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: Colors.grey, width: 0.5),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickKeyFile() async {
    setState(() => _isProcessing = true);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pem', 'crt', 'cer', 'key', 'jks', 'pub'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        String extension = result.files.single.extension?.toLowerCase() ?? '';
        _fileName = result.files.single.name;

        // 处理二进制格式 (CER/CRT 可能以 DER 形式存在)
        if (extension == 'cer' || extension == 'crt' || extension == 'jks') {
          List<int> bytes = await file.readAsBytes();
          String content = _attemptToConvertPem(bytes);
          _parseInput(content);
        } else {
          String content = await file.readAsString();
          _parseInput(content);
        }
      }
    } catch (e) {
      _showError("文件读取或转换失败: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  String _attemptToConvertPem(List<int> bytes) {
    try {
      String text = utf8.decode(bytes);
      if (text.contains("BEGIN ")) return text;
    } catch (_) {}

    String base64Content = base64.encode(bytes);

    return "-----BEGIN CERTIFICATE-----\n$base64Content\n-----END CERTIFICATE-----";
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
