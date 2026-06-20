import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/telnet_connection_model.dart';

class TelnetStorageService {
  static const String _connectionsKey = 'telnet_connections';
  static const String _recentConnectionsKey = 'telnet_recent_connections';
  static const int _maxRecentConnections = 12;

  Future<List<TelnetConnectionInfo>> getRecentConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_recentConnectionsKey);

    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList
          .map((json) => TelnetConnectionInfo.fromMap(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> addRecentConnection(TelnetConnectionInfo connection) async {
    final prefs = await SharedPreferences.getInstance();
    List<TelnetConnectionInfo> recentConnections = await getRecentConnections();

    // 更新最后使用时间
    final updatedConnection = TelnetConnectionInfo(
      id: connection.id,
      name: connection.name,
      host: connection.host,
      port: connection.port,
      username: connection.username,
      password: connection.password,
      remember: connection.remember,
      terminalType: connection.terminalType,
      lineSeparator: connection.lineSeparator,
      lastUsed: DateTime.now(),
    );

    // 移除旧的，添加新的
    recentConnections.removeWhere((c) => c.id == connection.id);
    recentConnections.insert(0, updatedConnection);

    // 限制数量
    if (recentConnections.length > _maxRecentConnections) {
      recentConnections =
          recentConnections.take(_maxRecentConnections).toList();
    }

    final jsonList = recentConnections.map((c) => c.toMap()).toList();
    await prefs.setString(_recentConnectionsKey, json.encode(jsonList));
  }

  Future<void> saveConnection(TelnetConnectionInfo connection) async {
    final prefs = await SharedPreferences.getInstance();
    final connections = await getConnections();

    connections.removeWhere((c) => c.id == connection.id);
    connections.add(connection);

    final jsonList = connections.map((c) => c.toMap()).toList();
    await prefs.setString(_connectionsKey, json.encode(jsonList));
  }

  Future<List<TelnetConnectionInfo>> getConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_connectionsKey);

    if (jsonString == null) return [];

    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList
          .map((json) => TelnetConnectionInfo.fromMap(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteConnection(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final connections = await getConnections();
    connections.removeWhere((c) => c.id == id);

    final jsonList = connections.map((c) => c.toMap()).toList();
    await prefs.setString(_connectionsKey, json.encode(jsonList));
  }
}
