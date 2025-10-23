// models/connection_model.dart
class ConnectionInfo {
  String id;
  String name;
  String host;
  int port;
  String credentialId;
  ConnectionType type;
  bool remember;

  ConnectionInfo({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.credentialId,
    required this.type,
    required this.remember,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'credentialId': credentialId,
      'type': type.toString(),
      'remember': remember,
    };
  }

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) {
  ConnectionType type;
  try {
    final typeString = json['type'] as String;
    type = ConnectionType.values.firstWhere(
      (e) => e.toString() == typeString,
      orElse: () => ConnectionType.ssh, // 默认 SSH
    );
  } catch (e) {
    type = ConnectionType.ssh; // 出错时默认 SSH
  }
    return ConnectionInfo(
      id: json['id'],
      name: json['name'],
      host: json['host'],
      port: json['port'],
      credentialId: json['credentialId'],
      type: type,
      remember: json['remember'],
    );
  }
}

enum ConnectionType {
  ssh,
  sftp,
}

extension ConnectionTypeExtension on ConnectionType {
  String get displayName {
    switch (this) {
      case ConnectionType.ssh:
        return 'SSH';
      case ConnectionType.sftp:
        return 'SFTP';
    }
  }
}