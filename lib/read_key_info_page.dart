// ignore_for_file: unused_field, deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'package:connssh/keygen_page.dart';
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
  List<Map<String, String>> _multipleCertificates = [];
  int _currentCertificateIndex = 0;

  void _parseInput(String content) {
    if (content.trim().isEmpty) return;

    _multipleCertificates.clear();
    _currentCertificateIndex = 0;

    String trimmed = content.trim();

    final certPattern = RegExp(
      r'-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----',
      dotAll: true,
    );

    final matches = certPattern.allMatches(trimmed);

    if (matches.isNotEmpty) {
      for (var match in matches) {
        final certContent =
            '-----BEGIN CERTIFICATE-----${match.group(1)}-----END CERTIFICATE-----';
        _parseSingleCertificate(certContent, isMultiple: true);
      }

      if (_multipleCertificates.isNotEmpty) {
        setState(() {
          _parsedInfo = _multipleCertificates[0];
          _keyContent = matches.first.group(0);
        });
      }
    } else {
      _parseSingleCertificate(trimmed);
    }
  }

  void _parseSingleCertificate(String content, {bool isMultiple = false}) {
    Map<String, String> info = {};
    String trimmed = content.trim();

    const oidMap = {
      '1.2.840.113549.1.1.11': 'sha256WithRSAEncryption',
      '1.2.840.113549.1.1.12': 'sha384WithRSAEncryption',
      '1.2.840.113549.1.1.13': 'sha512WithRSAEncryption',
      '1.2.840.113549.1.1.5': 'sha1WithRSAEncryption',
      '1.2.840.10045.4.3.2': 'ecdsa-with-sha256',
      '1.2.840.10045.4.3.3': 'ecdsa-with-sha384',
      '1.2.840.10045.4.3.4': 'ecdsa-with-sha512',
    };

    const oidToNameMap = {
      '2.5.4.3': 'CN', // 通用名称
      '2.5.4.6': 'C', // 国家
      '2.5.4.7': 'L', // 地区
      '2.5.4.8': 'S', // 州/省
      '2.5.4.10': 'O', // 组织
      '2.5.4.11': 'OU', // 组织单位
      '2.5.4.12': 'T', // 职务
      '2.5.4.13': 'D', // 描述
      '1.2.840.113549.1.9.1': 'EMAIL', // 电子邮件
    };

    try {
      info["文件名"] = _fileName ?? "未命名";

      if (trimmed.contains("BEGIN CERTIFICATE")) {
        info["类型"] = "X.509 证书";

        var data = X509Utils.x509CertificateFromPem(trimmed);

        String getReadableName(Map<String, dynamic> dnMap) {
          List<String> parts = [];

          // 按照常用顺序添加字段
          const orderedOids = ['C', 'O', 'OU', 'CN', 'L', 'S', 'EMAIL'];
          const oidToOrderedKey = {
            'C': '2.5.4.6',
            'O': '2.5.4.10',
            'OU': '2.5.4.11',
            'CN': '2.5.4.3',
            'L': '2.5.4.7',
            'S': '2.5.4.8',
            'EMAIL': '1.2.840.113549.1.9.1',
          };

          for (var key in orderedOids) {
            var oid = oidToOrderedKey[key];
            if (dnMap.containsKey(oid) &&
                dnMap[oid] != null &&
                dnMap[oid].toString().isNotEmpty) {
              parts.add('$key=${dnMap[oid]}');
            }
          }

          dnMap.forEach((oid, value) {
            if (value != null && value.toString().isNotEmpty) {
              var name = oidToNameMap[oid] ?? oid;
              if (!parts.any((part) => part.startsWith('$name='))) {
                parts.add('$name=$value');
              }
            }
          });

          return parts.join(', ');
        }

        info["主体"] = getReadableName(data.subject);
        info["颁发者"] = getReadableName(data.issuer);

        DateTime notBefore = data.validity.notBefore;
        DateTime notAfter = data.validity.notAfter;
        info["生效时间"] = notBefore.toLocal().toString().split('.')[0];
        info["过期时间"] = notAfter.toLocal().toString().split('.')[0];

        bool isExpired = DateTime.now().isAfter(notAfter);
        info["状态"] = isExpired ? "已过期" : "有效中";

        String sigOid = data.signatureAlgorithm;
        info["签名算法"] = oidMap[sigOid] ?? sigOid;

        // 处理序列号，确保是16进制且格式正确
        BigInt serial = data.serialNumber;
        String hexString = serial.toRadixString(16).toUpperCase();
        if (hexString.length % 2 != 0) {
          hexString = '0' + hexString;
        }
        info["序列号"] = hexString;

        if (isMultiple) {
          info["证书序号"] = "${_multipleCertificates.length + 1}";
        }
      } else if (trimmed.contains("BEGIN RSA PRIVATE KEY") ||
          trimmed.contains("BEGIN PRIVATE KEY") ||
          trimmed.contains("BEGIN ENCRYPTED PRIVATE KEY")) {
        info["类型"] = "私钥 (不支持解析)";
        info["状态"] = "私钥解析功能已禁用";
        info["建议"] = "请上传证书文件(.crt/.cer/.pem)";
      } else {
        try {
          List<int> bytes =
              base64.decode(trimmed.replaceAll(RegExp(r'\s'), ''));
          String pem = "-----BEGIN CERTIFICATE-----\n" +
              base64.encode(bytes).replaceAllMapped(
                  RegExp(r'.{64}'), (match) => '${match.group(0)}\n') +
              "\n-----END CERTIFICATE-----";

          _parseSingleCertificate(pem);
          return;
        } catch (e) {
          info["类型"] = "未知格式";
          info["状态"] = "无法解析";
          info["详情"] = "内容无法识别";
        }
      }
    } catch (e) {
      info["解析状态"] = "证书结构解析失败";
      info["详情"] = "${e.toString().split('\n').first}";
    }

    info["字符长度"] = "${content.length} 字符";

    if (isMultiple) {
      _multipleCertificates.add(info);
    } else {
      setState(() {
        _parsedInfo = info;
        _keyContent = content;
        _showPasteField = false;
      });
    }
  }

  void _switchCertificate(int index) {
    if (index >= 0 && index < _multipleCertificates.length) {
      setState(() {
        _currentCertificateIndex = index;
        _parsedInfo = _multipleCertificates[index];

        final certPattern = RegExp(
          r'-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----',
          dotAll: true,
        );
        final matches = certPattern.allMatches(_pasteController.text);
        if (matches.length > index) {
          _keyContent = matches.elementAt(index).group(0);
        }
      });
    }
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

  void _navigateToKeyGen() {
    if (mounted) {
      Navigator.push(
          context, MaterialPageRoute(builder: (context) => KeygenPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('密钥和证书工具')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('证书解析', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            const Text('密钥工具', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildActionButton(
              onPressed: _navigateToKeyGen,
              title: '密钥生成',
            ),
            if (_showPasteField) _buildPasteArea(),
            if (_multipleCertificates.length > 1) _buildCertificateSwitcher(),
            if (_parsedInfo.isNotEmpty) _buildResultSection(),
            if (_keyContent != null) _buildPreviewArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateSwitcher() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('包含多个证书:', style: TextStyle(fontWeight: FontWeight.bold)),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentCertificateIndex > 0
                    ? () => _switchCertificate(_currentCertificateIndex - 1)
                    : null,
              ),
              Text(
                  '${_currentCertificateIndex + 1}/${_multipleCertificates.length}'),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed:
                    _currentCertificateIndex < _multipleCertificates.length - 1
                        ? () => _switchCertificate(_currentCertificateIndex + 1)
                        : null,
              ),
            ],
          ),
        ],
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
            Text(
              '解析结果${_multipleCertificates.length > 1 ? " (证书${_currentCertificateIndex + 1})" : ""}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
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
        allowedExtensions: ['pem', 'crt', 'cer', 'der'],
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        _fileName = result.files.single.name;

        String content = await file.readAsString();
        _parseInput(content);
      }
    } catch (e) {
      _showError("文件读取失败: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
