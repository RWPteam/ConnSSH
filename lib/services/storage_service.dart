import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';

class StorageService {
  static const String _connectionsKey = 'saved_connections';
  static const String _credentialsKey = 'saved_credentials';
  static const String _recentConnectionsKey = 'recent_connections';
  static const int _maxRecentConnections = 12;
  static const int _maxPinnedConnections = 12;

  Future<List<ConnectionInfo>> getRecentConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_recentConnectionsKey);

    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      final connections = jsonList.map((json) => ConnectionInfo.fromJson(json)).toList();
      connections.sort((a,b){
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.lastUsed.compareTo(a.lastUsed);
      });
      return connections;
    } catch (e) {
      return [];
    }
  }//从sharedpreferences中获取最近的连接

  Future<void> addRecentConnection(ConnectionInfo connection) async {
    final prefs = await SharedPreferences.getInstance();
    List<ConnectionInfo> recentConnections = await getRecentConnections();
    final updatedConnnection = ConnectionInfo(id: connection.id, name: connection.name, host: connection.host, port: connection.port, credentialId: connection.credentialId, type: connection.type, remember: connection.remember, isPinned: connection.isPinned,lastUsed: DateTime.now());
    recentConnections.removeWhere((c) => c.id == connection.id);
    if (connection.isPinned) {
      recentConnections.insert(0, updatedConnnection);
    } else {
      final pinnedCount = recentConnections.where((c) => c.isPinned).length;
      recentConnections.insert(pinnedCount, updatedConnnection);
    }
    if (recentConnections.length > _maxRecentConnections) {
      recentConnections = recentConnections.take(_maxRecentConnections).toList();
    }
    final jsonList = recentConnections.map((c) => c.toJson()).toList();
    await prefs.setString(_recentConnectionsKey, json.encode(jsonList));
  }//将连接信息按照模型转换为最近连接

  Future<void> togglePinConnection(String id) async {
    final prefs = await SharedPreferences.getInstance();
    List<ConnectionInfo> recentConnections = await getRecentConnections();

    final connectionIndex = recentConnections.indexWhere((c) => c.id == id);
    if (connectionIndex != -1) {
      final connection = recentConnections[connectionIndex];
      final pinnedCount = recentConnections.where((c) => c.isPinned).length;

      if (!connection.isPinned && pinnedCount >= _maxPinnedConnections) {
        throw Exception('置顶数量达到上限');
      }

    recentConnections[connectionIndex] = ConnectionInfo(id: connection.id, name: connection.name, host: connection.host, port: connection.port, credentialId: connection.credentialId, type: connection.type, remember: connection.remember, isPinned: !connection.isPinned,lastUsed: connection.lastUsed);
    recentConnections.sort((a,b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.lastUsed.compareTo(a.lastUsed);
      });

      final jsonList = recentConnections.map((c) => c.toJson()).toList();
      await prefs.setString(_recentConnectionsKey, json.encode(jsonList));
    }
  }//存储置顶列表

  Future<void> deleteRecentConnection(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final recentConnections = await getRecentConnections();
    recentConnections.removeWhere((c) => c.id == id);
    final jsonList = recentConnections.map((c) => c.toJson()).toList();
    await prefs.setString(_recentConnectionsKey, json.encode(jsonList));
  }//删除最近连接

  Future<void> saveConnection(ConnectionInfo connection) async {
    final prefs = await SharedPreferences.getInstance();
    final connections = await getConnections();
    
    connections.removeWhere((c) => c.id == connection.id);
    connections.add(connection);
    
    final jsonList = connections.map((c) => c.toJson()).toList();
    await prefs.setString(_connectionsKey, json.encode(jsonList)); 
  }//保存连接到连接列表

  Future<List<ConnectionInfo>> getConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_connectionsKey);
    
    if (jsonString == null) return [];
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString); 
      return jsonList.map((json) => ConnectionInfo.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }//获取连接列表

  Future<void> deleteConnection(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final connections = await getConnections();
    connections.removeWhere((c) => c.id == id);
    
    final jsonList = connections.map((c) => c.toJson()).toList();
    await prefs.setString(_connectionsKey, json.encode(jsonList)); 
  }//删除连接

  Future<void> saveCredential(Credential credential) async {
    final prefs = await SharedPreferences.getInstance();
    final credentials = await getCredentials();
    
   
    credentials.removeWhere((c) => c.id == credential.id);
    credentials.add(credential);
    
    final jsonList = credentials.map((c) => c.toJson()).toList();
    await prefs.setString(_credentialsKey, json.encode(jsonList)); 
  }//保存凭证

  Future<List<Credential>> getCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_credentialsKey);
    
    if (jsonString == null) return [];
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((json) => Credential.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }//获取凭证列表

  Future<void> deleteCredential(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final credentials = await getCredentials();
    credentials.removeWhere((c) => c.id == id);
    
    final jsonList = credentials.map((c) => c.toJson()).toList();
    await prefs.setString(_credentialsKey, json.encode(jsonList)); 
  }//删除保存的凭证
}