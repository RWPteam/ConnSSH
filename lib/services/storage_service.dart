import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';

class StorageService {
  static const String _connectionsKey = 'saved_connections';
  static const String _credentialsKey = 'saved_credentials';
  static const String _recentConnectionsKey = 'recent_connections';

  Future<List<ConnectionInfo>> getRecentConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_recentConnectionsKey);

    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      final connections = jsonList.map((json) => ConnectionInfo.fromJson(json)).toList();
      final uniqueConnections = <String, ConnectionInfo> {};
      for (final connection in connections) {
        uniqueConnections[connection.id] = connection;
      }
      return uniqueConnections.values.take(5).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> addRecentConnection(ConnectionInfo connection) async {
    final prefs = await SharedPreferences.getInstance();
    final recentConnections = await getRecentConnections();
    recentConnections.removeWhere((c) => c.id == connection.id);
    recentConnections.insert(0, connection);

    final limitConnections = recentConnections.take(5).toList();

    final jsonList = limitConnections.map((c) => c.toJson()).toList();
    await prefs.setString(_recentConnectionsKey, json.encode(jsonList));
  }

  Future<void> deleteRecentConnection(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final recentConnections = await getRecentConnections();

    recentConnections.removeWhere((c) => c.id == id);

    final jsonList = recentConnections.map((c) => c.toJson()).toList();
    await prefs.setString(_recentConnectionsKey, json.encode(jsonList));
  }

  Future<void> saveConnection(ConnectionInfo connection) async {
    final prefs = await SharedPreferences.getInstance();
    final connections = await getConnections();
    
    connections.removeWhere((c) => c.id == connection.id);
    connections.add(connection);
    
    final jsonList = connections.map((c) => c.toJson()).toList();
    await prefs.setString(_connectionsKey, json.encode(jsonList)); 
  }

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
  }

  Future<void> deleteConnection(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final connections = await getConnections();
    connections.removeWhere((c) => c.id == id);
    
    final jsonList = connections.map((c) => c.toJson()).toList();
    await prefs.setString(_connectionsKey, json.encode(jsonList)); 
  }

  Future<void> saveCredential(Credential credential) async {
    final prefs = await SharedPreferences.getInstance();
    final credentials = await getCredentials();
    
   
    credentials.removeWhere((c) => c.id == credential.id);
    credentials.add(credential);
    
    final jsonList = credentials.map((c) => c.toJson()).toList();
    await prefs.setString(_credentialsKey, json.encode(jsonList)); 
  }

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
  }

  Future<void> deleteCredential(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final credentials = await getCredentials();
    credentials.removeWhere((c) => c.id == id);
    
    final jsonList = credentials.map((c) => c.toJson()).toList();
    await prefs.setString(_credentialsKey, json.encode(jsonList)); 
  }
}