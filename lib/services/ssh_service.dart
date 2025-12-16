import 'package:dartssh2/dartssh2.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';

class SshService {
  SSHClient? _client;

  Future<SSHClient> connect(
    ConnectionInfo connection,
    Credential credential,
  ) async {
    try {
      final socket = await SSHSocket.connect(connection.host, connection.port);
      
      if (credential.authType == AuthType.password) {
        _client = SSHClient(
          socket,
          username: credential.username,
          onPasswordRequest: () => credential.password!,
        );
      } else {
        final privateKey = credential.privateKey!;
        final passPhrase = credential.passphrase;
        
        try {
          final keyPairs = SSHKeyPair.fromPem(privateKey,passPhrase);
          if (keyPairs.isEmpty) {
            throw Exception('无法解析私钥');
          }
          
          _client = SSHClient(
            socket,
            username: credential.username,
            identities: keyPairs,
          );
        } catch (e) {
          throw Exception('私钥解析失败，请检查私钥格式和密码: $e');
        }
      }
      
      return _client!;
    } catch (e) {
      disconnect();
      throw Exception('连接失败: $e');
    }
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
}