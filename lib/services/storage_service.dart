// services/storage_service.dart
import 'dart:convert'; // 添加这个导入
import 'package:shared_preferences/shared_preferences.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';

class StorageService {
  static const String _connectionsKey = 'saved_connections';
  static const String _credentialsKey = 'saved_credentials';

  Future<void> saveConnection(ConnectionInfo connection) async {
    final prefs = await SharedPreferences.getInstance();
    final connections = await getConnections();
    
    // 移除同名的旧连接
    connections.removeWhere((c) => c.id == connection.id);
    connections.add(connection);
    
    final jsonList = connections.map((c) => c.toJson()).toList();
    await prefs.setString(_connectionsKey, json.encode(jsonList)); // 使用 json.encode
  }

  Future<List<ConnectionInfo>> getConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_connectionsKey);
    
    if (jsonString == null) return [];
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString); // 使用 json.decode
      return jsonList.map((json) => ConnectionInfo.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteConnection(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final connections = await getConnections();
    connections.removeWhere((c) => c.id == id);
    
    final jsonList = connections.map((c) => c.toJson()).toList();
    await prefs.setString(_connectionsKey, json.encode(jsonList)); // 使用 json.encode
  }

  Future<void> saveCredential(Credential credential) async {
    final prefs = await SharedPreferences.getInstance();
    final credentials = await getCredentials();
    
    // 移除同名的旧凭证
    credentials.removeWhere((c) => c.id == credential.id);
    credentials.add(credential);
    
    final jsonList = credentials.map((c) => c.toJson()).toList();
    await prefs.setString(_credentialsKey, json.encode(jsonList)); // 使用 json.encode
  }

  Future<List<Credential>> getCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_credentialsKey);
    
    if (jsonString == null) return [];
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString); // 使用 json.decode
      return jsonList.map((json) => Credential.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteCredential(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final credentials = await getCredentials();
    credentials.removeWhere((c) => c.id == id);
    
    final jsonList = credentials.map((c) => c.toJson()).toList();
    await prefs.setString(_credentialsKey, json.encode(jsonList)); // 使用 json.encode
  }
}