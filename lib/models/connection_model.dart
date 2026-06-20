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
  String? archive;
  bool needTwoFa;

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
    this.archive,
    this.needTwoFa = false, // 默认不需要2FA
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();

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
      'archive': archive,
      'needTwoFa': needTwoFa, // 保存2FA设置
    };
  }

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
      archive: json['archive'],
      needTwoFa: json['needTwoFa'] ?? false, // 读取2FA设置
      lastUsed: json['lastUsed'] != null
          ? DateTime.parse(json['lastUsed'])
          : DateTime.now(),
    );
  }
}

class ArchiveGroup {
  String id;
  String name;
  List<String> connectionIds;
  bool isExpanded;

  ArchiveGroup({
    required this.id,
    required this.name,
    this.connectionIds = const [],
    this.isExpanded = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'connectionIds': connectionIds,
      'isExpanded': isExpanded,
    };
  }

  factory ArchiveGroup.fromJson(Map<String, dynamic> json) {
    return ArchiveGroup(
      id: json['id'],
      name: json['name'],
      connectionIds: List<String>.from(json['connectionIds'] ?? []),
      isExpanded: json['isExpanded'] ?? true,
    );
  }
}

enum ConnectionType { ssh, sftp }

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
