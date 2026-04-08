import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/services.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';
import '../services/twofa_service.dart';
import '../services/notification_service.dart';

class SshService {
  SSHClient? _client;
  TwoFactorAuthService _twoFactorAuthService;
  static const platform = MethodChannel(
    'com.samuioto.connecter/background_task',
  );

  static const _keepAliveInterval = Duration(seconds: 10);
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
        return await _connectWithTwoFactorAuth(
          socket,
          connection,
          credential,
          onTwoFactorAuth: onTwoFactorAuth,
        );
      } else {
        return await _connectWithoutTwoFactorAuth(
          socket,
          connection,
          credential,
        );
      }
    } catch (e) {
      print('SSH连接失败: $e');
      disconnect();
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

          final lowerPrompt = promptText.toLowerCase();
          final isTwoFactorPrompt =
              lowerPrompt.contains('verification') ||
              lowerPrompt.contains('code') ||
              lowerPrompt.contains('token') ||
              lowerPrompt.contains('otp') ||
              lowerPrompt.contains('2fa') ||
              lowerPrompt.contains('two-factor') ||
              lowerPrompt.contains('mfa');

          final isPasswordPrompt =
              !echo &&
              (lowerPrompt.contains('password') ||
                  lowerPrompt.contains('passphrase') ||
                  lowerPrompt.contains('密码') ||
                  lowerPrompt.contains('password:'));

          if (isTwoFactorPrompt && !hasProvidedTwoFactorCode) {
            print('请求2FA验证码...');
            final code = onTwoFactorAuth != null
                ? await onTwoFactorAuth(
                    connection.name,
                    connection.host,
                    promptText,
                  )
                : await _twoFactorAuthService.requestTwoFactorCode(
                    connection.name,
                    connection.host,
                    promptText,
                  );

            if (code == null || code.isEmpty) {
              throw Exception('2FA验证码未提供');
            }

            responses.add(code);
            hasProvidedTwoFactorCode = true;
            print('已提供2FA验证码: $code');
          } else if (isPasswordPrompt && !hasProvidedPassword) {
            print('提供密码...');
            final password = credential.password ?? '';
            if (password.isEmpty) {
              throw Exception('密码为空，请检查凭证');
            }
            responses.add(password);
            hasProvidedPassword = true;
            print('已提供密码');
          } else if (isTwoFactorPrompt && hasProvidedTwoFactorCode) {
            print('重新请求2FA验证码...');
            final code = onTwoFactorAuth != null
                ? await onTwoFactorAuth(
                    connection.name,
                    connection.host,
                    "验证码错误，请重新输入: $promptText",
                  )
                : await _twoFactorAuthService.requestTwoFactorCode(
                    connection.name,
                    connection.host,
                    "验证码错误，请重新输入: $promptText",
                  );

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

    if (credential.authType == AuthType.password) {
      print('使用密码认证（2FA模式）...');
      _client = SSHClient(
        socket,
        username: credential.username,
        onUserInfoRequest: keyboardInteractiveHandler,
        keepAliveInterval: _keepAliveInterval,
      );
    } else {
      print('使用私钥认证（2FA模式）...');
      final privateKey = credential.privateKey!;
      final passPhrase = credential.passphrase;

      try {
        final cleanedPrivateKey = _cleanPrivateKey(privateKey);
        final keyPairs = _loadPrivateKeyPairs(cleanedPrivateKey, passPhrase);

        if (keyPairs.isEmpty) {
          throw Exception('无法解析私钥');
        }

        _client = SSHClient(
          socket,
          username: credential.username,
          identities: keyPairs,
          onUserInfoRequest: keyboardInteractiveHandler,
          keepAliveInterval: _keepAliveInterval,
        );
      } catch (e) {
        throw Exception('私钥解析失败，请检查私钥格式和密码: $e');
      }
    }

    print('等待认证完成...');
    await _client!.authenticated;
    try {
      final result = await _client!
          .run('echo "test"')
          .timeout(Duration(seconds: 5));
      print('连接测试成功: ${result.join()}');
    } catch (e) {
      print('连接测试失败: $e');
      disconnect();
      throw Exception('认证成功但连接测试失败: $e');
    }

    _listenToConnectionClosure();
    print('认证成功！');

    // 显示连接通知
    try {
      await NotificationService().showConnectionNotification(
        connectionName: connection.name,
        host: connection.host,
        port: connection.port,
      );

      // 更新为已连接状态
      await NotificationService().updateConnectionNotification(
        connectionName: connection.name,
        host: connection.host,
        port: connection.port,
        status: '已连接',
      );
    } catch (e) {
      print('显示通知时出错: $e');
    }

    return _client!;
  }

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
        keepAliveInterval: _keepAliveInterval,
      );
    } else {
      print('使用私钥认证...');
      final cleanedPrivateKey = _cleanPrivateKey(credential.privateKey!);
      final keyPairs = _loadPrivateKeyPairs(
        cleanedPrivateKey,
        credential.passphrase,
      );

      _client = SSHClient(
        socket,
        username: credential.username,
        identities: keyPairs,
        keepAliveInterval: _keepAliveInterval,
      );
    }

    print('正在验证身份...');
    await _client!.authenticated;

    _listenToConnectionClosure();
    print('认证成功！');

    // 显示连接通知
    try {
      await NotificationService().showConnectionNotification(
        connectionName: connection.name,
        host: connection.host,
        port: connection.port,
      );

      // 更新为已连接状态
      await NotificationService().updateConnectionNotification(
        connectionName: connection.name,
        host: connection.host,
        port: connection.port,
        status: '已连接',
      );
    } catch (e) {
      print('显示通知时出错: $e');
    }

    return _client!;
  }

  void _listenToConnectionClosure() {
    _client?.done
        .then((_) async {
          print('SSH 连接已关闭');
          // 连接关闭时取消通知
          try {
            await NotificationService().cancelConnectionNotification();
          } catch (e) {
            print('取消通知失败: $e');
          }
          _client = null;
        })
        .catchError((e) async {
          print('SSH 连接异常中断: $e');
          // 连接异常时也取消通知
          try {
            await NotificationService().cancelConnectionNotification();
          } catch (e2) {
            print('取消通知失败: $e2');
          }
          _client = null;
        });
  }

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

  List<SSHKeyPair> _loadPrivateKeyPairs(String privateKey, String? passPhrase) {
    try {
      final keyPairs = SSHKeyPair.fromPem(privateKey, null);
      if (keyPairs.isNotEmpty) {
        print('私钥未加密，成功解析得到 ${keyPairs.length} 个密钥对');
        return keyPairs;
      }
    } catch (e) {
      print('无密码解析失败: $e');
      if (e is SSHKeyDecryptError || e.toString().contains('encrypted')) {
        if (passPhrase == null || passPhrase.isEmpty) {
          throw Exception('私钥已加密，但未提供密码或密码为空');
        }
        try {
          final keyPairs = SSHKeyPair.fromPem(privateKey, passPhrase);
          if (keyPairs.isNotEmpty) {
            print('使用密码成功解析加密私钥，得到 ${keyPairs.length} 个密钥对');
            return keyPairs;
          } else {
            throw Exception('无法从私钥解析出密钥对');
          }
        } catch (e2) {
          print('使用密码解析加密私钥失败: $e2');
          throw Exception('私钥密码错误或密钥格式不正确: $e2');
        }
      } else {
        throw Exception('无法解析私钥，请检查私钥格式: $e');
      }
    }
    throw Exception('无法从私钥解析出密钥对');
  }

  String _cleanPrivateKey(String privateKey) {
    final lines = privateKey.split('\n');
    final cleanedLines = <String>[];
    bool inKeyData = false;
    bool foundBegin = false;

    for (var line in lines) {
      final trimmedLine = line.trim();

      if (trimmedLine.isEmpty) {
        continue;
      }

      if (trimmedLine.startsWith('-----BEGIN')) {
        cleanedLines.add(trimmedLine);
        foundBegin = true;
        inKeyData = false;
        continue;
      }

      if (trimmedLine.startsWith('-----END')) {
        cleanedLines.add(trimmedLine);
        break;
      }

      if (trimmedLine.startsWith('Proc-Type:') ||
          trimmedLine.startsWith('DEK-Info:')) {
        cleanedLines.add(trimmedLine);
        continue;
      }

      if (!inKeyData &&
          !trimmedLine.startsWith('Proc-Type:') &&
          !trimmedLine.startsWith('DEK-Info:') &&
          !_isBase64Line(trimmedLine)) {
        continue;
      }

      inKeyData = true;
      cleanedLines.add(trimmedLine);
    }

    if (!foundBegin || cleanedLines.length < 3) {
      return privateKey;
    }

    return cleanedLines.join('\n');
  }

  bool _isBase64Line(String line) {
    if (line.isEmpty) return false;
    return RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(line);
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

  void disconnect() async {
    try {
      await NotificationService().cancelConnectionNotification();
    } catch (e) {
      print('取消通知失败: $e');
    }

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
          '提示 $i: ${_getPromptText(prompt)}, 回显: ${_getPromptEcho(prompt)}',
        );
      }
    } else {
      print('没有提示信息');
    }
    print('============================');
  }
}

typedef TwoFactorAuthHandler =
    Future<String?> Function(String connectionName, String host, String prompt);
