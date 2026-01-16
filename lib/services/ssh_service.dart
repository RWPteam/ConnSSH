// ssh_service.dart
import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';
import '../services/twofa_service.dart';

class SshService {
  SSHClient? _client;
  TwoFactorAuthService _twoFactorAuthService;

  SshService({TwoFactorAuthService? twoFactorAuthService})
      : _twoFactorAuthService = twoFactorAuthService ?? TwoFactorAuthService();

  Future<SSHClient> connect(
    ConnectionInfo connection,
    Credential credential, {
    TwoFactorAuthHandler? onTwoFactorAuth,
  }) async {
    try {
      final socket = await SSHSocket.connect(connection.host, connection.port);

      if (connection.needTwoFa) {
        // 2FA模式：使用键盘交互式认证
        return await _connectWithTwoFactorAuth(
          socket,
          connection,
          credential,
          onTwoFactorAuth: onTwoFactorAuth,
        );
      } else {
        // 传统模式：使用标准认证，不设置键盘交互处理器
        return await _connectWithoutTwoFactorAuth(
          socket,
          connection,
          credential,
        );
      }
    } catch (e) {
      print('SSH连接失败: $e');
      disconnect();

      // 根据错误类型返回友好的错误信息
      if (e.toString().contains('Authentication failed')) {
        throw Exception('认证失败：用户名、密码或密钥错误');
      } else if (e.toString().contains('Connection refused')) {
        throw Exception('连接被拒绝，请检查主机和端口');
      } else if (e.toString().contains('Network is unreachable')) {
        throw Exception('网络不可达，请检查网络连接');
      } else if (e.toString().contains('timed out')) {
        throw Exception('连接超时，请检查网络或服务器状态');
      }

      throw Exception('连接失败: ${e.toString()}');
    }
  }

  // 2FA认证模式
  Future<SSHClient> _connectWithTwoFactorAuth(
    SSHSocket socket,
    ConnectionInfo connection,
    Credential credential, {
    TwoFactorAuthHandler? onTwoFactorAuth,
  }) async {
    print('使用2FA认证模式...');

    bool hasProvidedTwoFactorCode = false;
    bool hasProvidedPassword = false;

    Future<List<String>?> keyboardInteractiveHandler(dynamic request) async {
      _debugAuthRequest(request);
      try {
        final prompts = _getPromptsFromRequest(request);
        if (prompts == null || prompts.isEmpty) {
          print('没有提示，返回空列表');
          return [];
        }

        final responses = <String>[];

        for (var i = 0; i < prompts.length; i++) {
          final prompt = prompts[i];
          final promptText = _getPromptText(prompt);
          final echo = _getPromptEcho(prompt);

          print('处理提示: "$promptText", echo: $echo');

          // 检查是否是2FA提示
          final lowerPrompt = promptText.toLowerCase();
          final isTwoFactorPrompt = lowerPrompt.contains('verification') ||
              lowerPrompt.contains('code') ||
              lowerPrompt.contains('token') ||
              lowerPrompt.contains('otp') ||
              lowerPrompt.contains('2fa') ||
              lowerPrompt.contains('two-factor') ||
              lowerPrompt.contains('mfa');

          // 检查是否是密码提示
          final isPasswordPrompt = !echo &&
              (lowerPrompt.contains('password') ||
                  lowerPrompt.contains('passphrase') ||
                  lowerPrompt.contains('密码') ||
                  lowerPrompt.contains('password:'));

          if (isTwoFactorPrompt && !hasProvidedTwoFactorCode) {
            // 第一次出现2FA提示，请求验证码
            print('请求2FA验证码...');
            final code = onTwoFactorAuth != null
                ? await onTwoFactorAuth(
                    connection.name, connection.host, promptText)
                : await _twoFactorAuthService.requestTwoFactorCode(
                    connection.name, connection.host, promptText);

            if (code == null || code.isEmpty) {
              throw Exception('2FA验证码未提供');
            }

            responses.add(code);
            hasProvidedTwoFactorCode = true;
            print('已提供2FA验证码: $code');
          } else if (isPasswordPrompt && !hasProvidedPassword) {
            // 第一次出现密码提示，提供密码
            print('提供密码...');
            final password = credential.password ?? '';
            if (password.isEmpty) {
              throw Exception('密码为空，请检查凭证');
            }
            responses.add(password);
            hasProvidedPassword = true;
            print('已提供密码');
          } else if (isTwoFactorPrompt && hasProvidedTwoFactorCode) {
            // 第二次出现2FA提示，可能是验证码错误，重新请求
            print('重新请求2FA验证码...');
            final code = onTwoFactorAuth != null
                ? await onTwoFactorAuth(connection.name, connection.host,
                    "验证码错误，请重新输入: $promptText")
                : await _twoFactorAuthService.requestTwoFactorCode(
                    connection.name,
                    connection.host,
                    "验证码错误，请重新输入: $promptText");

            if (code == null || code.isEmpty) {
              throw Exception('2FA验证码未提供');
            }

            responses.add(code);
            print('已重新提供2FA验证码: $code');
          } else {
            // 其他情况返回空字符串
            print('返回空响应');
            responses.add('');
          }
        }

        print('返回响应数量: ${responses.length}');
        return responses;
      } catch (e) {
        print('键盘交互认证失败: $e');
        rethrow;
      }
    }

    // 2FA模式下，无论密码还是密钥认证，都使用键盘交互式处理器
    if (credential.authType == AuthType.password) {
      print('使用密码认证（2FA模式）...');
      _client = SSHClient(
        socket,
        username: credential.username,
        onUserInfoRequest: keyboardInteractiveHandler,
        // 注意：不设置 onPasswordRequest
      );
    } else {
      print('使用私钥认证（2FA模式）...');
      final privateKey = credential.privateKey!;
      final passPhrase = credential.passphrase;

      try {
        final cleanedPrivateKey = _cleanPrivateKey(privateKey);
        final keyPairs = SSHKeyPair.fromPem(cleanedPrivateKey, passPhrase);

        if (keyPairs.isEmpty) {
          throw Exception('无法解析私钥');
        }

        _client = SSHClient(
          socket,
          username: credential.username,
          identities: keyPairs,
          onUserInfoRequest: keyboardInteractiveHandler,
        );
      } catch (e) {
        throw Exception('私钥解析失败，请检查私钥格式和密码: $e');
      }
    }

    // 等待认证完成（不设置超时，让服务器决定）
    print('等待认证完成...');
    await _client!.authenticated;

    // 验证连接是否真的可用
    try {
      final result =
          await _client!.run('echo "test"').timeout(Duration(seconds: 5));
      print('连接测试成功: ${result.join()}');
    } catch (e) {
      print('连接测试失败: $e');
      disconnect();
      throw Exception('认证成功但连接测试失败: $e');
    }

    print('认证成功！');
    return _client!;
  }

  // 传统认证模式（无2FA）
  Future<SSHClient> _connectWithoutTwoFactorAuth(
    SSHSocket socket,
    ConnectionInfo connection,
    Credential credential,
  ) async {
    print('使用传统认证模式...');

    if (credential.authType == AuthType.password) {
      print('使用密码认证...');
      _client = SSHClient(
        socket,
        username: credential.username,
        onPasswordRequest: () {
          if (credential.password == null || credential.password!.isEmpty) {
            throw Exception('密码为空');
          }
          return credential.password;
        },
        // 传统模式：不设置键盘交互处理器
      );
    } else {
      print('使用私钥认证...');
      final cleanedPrivateKey = _cleanPrivateKey(credential.privateKey!);
      final keyPairs =
          SSHKeyPair.fromPem(cleanedPrivateKey, credential.passphrase);

      _client = SSHClient(
        socket,
        username: credential.username,
        identities: keyPairs,
        // 传统模式：不设置键盘交互处理器
      );
    }

    print('正在验证身份...');
    // 不设置超时，让服务器决定
    await _client!.authenticated;

    print('认证成功！');
    return _client!;
  }

  // 以下辅助方法保持不变...
  List<dynamic>? _getPromptsFromRequest(dynamic request) {
    if (request is Map) {
      if (request.containsKey('prompts')) {
        return request['prompts'] as List<dynamic>;
      }
      if (request.containsKey('promptList')) {
        return request['promptList'] as List<dynamic>;
      }
    }

    try {
      final prompts = request.prompts;
      if (prompts is List) {
        return prompts;
      }
    } catch (_) {}

    return null;
  }

  String _getPromptText(dynamic prompt) {
    if (prompt is Map) {
      if (prompt.containsKey('prompt')) {
        return prompt['prompt'] as String;
      }
      if (prompt.containsKey('text')) {
        return prompt['text'] as String;
      }
    }
    try {
      final text = prompt.prompt ?? prompt.text;
      if (text is String) {
        return text;
      }
    } catch (_) {}

    return prompt.toString();
  }

  bool _getPromptEcho(dynamic prompt) {
    if (prompt is Map) {
      if (prompt.containsKey('echo')) {
        return prompt['echo'] as bool;
      }
      if (prompt.containsKey('isEcho')) {
        return prompt['isEcho'] as bool;
      }
    }

    try {
      final echo = prompt.echo ?? prompt.isEcho;
      if (echo is bool) {
        return echo;
      }
    } catch (_) {}

    return true;
  }

  String _cleanPrivateKey(String privateKey) {
    final lines = privateKey.split('\n');
    final cleanedLines = <String>[];
    bool inHeader = false;
    bool foundBegin = false;

    for (var line in lines) {
      final trimmedLine = line.trim();

      if (trimmedLine.isEmpty) {
        continue;
      }

      if (trimmedLine.startsWith('-----BEGIN')) {
        cleanedLines.add(trimmedLine);
        foundBegin = true;
        inHeader = true;
        continue;
      }

      if (trimmedLine.startsWith('-----END')) {
        cleanedLines.add(trimmedLine);
        break;
      }

      if (inHeader &&
          (trimmedLine.startsWith('Proc-Type:') ||
              trimmedLine.startsWith('DEK-Info:'))) {
        continue;
      }

      if (inHeader) {
        inHeader = false;
      }

      cleanedLines.add(trimmedLine);
    }

    if (!foundBegin || cleanedLines.length < 3) {
      return privateKey;
    }

    return cleanedLines.join('\n');
  }

  Future<String> executeCommand(String command) async {
    if (_client == null) {
      throw Exception('未建立SSH连接');
    }

    try {
      final result = await _client!.run(command);
      return result.join();
    } catch (e) {
      throw Exception('命令执行失败: $e');
    }
  }

  void disconnect() {
    _client?.close();
    _client = null;
  }

  bool isConnected() {
    return _client != null;
  }

  void _debugAuthRequest(dynamic request) {
    print('=== SSH Auth Request Debug ===');
    print('请求类型: ${request.runtimeType}');
    print('请求对象: $request');

    if (request is Map) {
      print('请求键值:');
      for (var key in request.keys) {
        print('  $key: ${request[key]}');
      }
    }

    try {
      if (request is Map && request.containsKey('method')) {
        print('认证方法: ${request['method']}');
      }
    } catch (_) {}

    final prompts = _getPromptsFromRequest(request);
    if (prompts != null) {
      print('提示数量: ${prompts.length}');
      for (var i = 0; i < prompts.length; i++) {
        final prompt = prompts[i];
        print(
            '提示 $i: ${_getPromptText(prompt)}, 回显: ${_getPromptEcho(prompt)}');
      }
    } else {
      print('没有提示信息');
    }
    print('============================');
  }
}

typedef TwoFactorAuthHandler = Future<String?> Function(
    String connectionName, String host, String prompt);
