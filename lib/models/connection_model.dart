class ConnectionInfo {
  String id;
  String name;
  String host;
  int port;
  String credentialId;
  ConnectionType type;
  bool remember;
  bool isPinned;
  DateTime lastUsed;
  String? sftpPath; 

  ConnectionInfo({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.credentialId,
    required this.type,
    required this.remember,
    this.isPinned = false,
    this.sftpPath, 
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();//定义连接信息模型

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'credentialId': credentialId,
      'type': type.toString(),
      'remember': remember,
      'isPinned': isPinned,
      'lastUsed': lastUsed.toIso8601String(),
      'sftpPath': sftpPath, 
    };
  }//转换为json

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) {
    ConnectionType type;
    try {
      final typeString = json['type'] as String;
      type = ConnectionType.values.firstWhere(
        (e) => e.toString() == typeString,
        orElse: () => ConnectionType.ssh, 
      );
    } catch (e) {
      type = ConnectionType.ssh;
    }
    return ConnectionInfo(
      id: json['id'],
      name: json['name'],
      host: json['host'],
      port: json['port'],
      credentialId: json['credentialId'],
      type: type,
      remember: json['remember'],
      isPinned: json['isPinned'] ?? false,
      sftpPath: json['sftpPath'], 
      lastUsed: json['lastUsed'] != null
        ? DateTime.parse(json['lastUsed'])
        : DateTime.now(),
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



