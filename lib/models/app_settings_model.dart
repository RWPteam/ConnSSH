class AppSettings {
  final String? defaultSftpPath;
  final String? defaultDownloadPath;
  final bool isFirstRun;

  const AppSettings({
    this.defaultSftpPath,
    this.defaultDownloadPath,
    this.isFirstRun = true, 
  });

  AppSettings copyWith({
    String? defaultSftpPath,
    String? defaultDownloadPath,
    bool? isFirstRun,
  }) {
    return AppSettings(
      defaultSftpPath: defaultSftpPath ?? this.defaultSftpPath,
      defaultDownloadPath: defaultDownloadPath ?? this.defaultDownloadPath,
      isFirstRun: isFirstRun ?? this.isFirstRun,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'defaultSftpPath': defaultSftpPath,
      'defaultDownloadPath': defaultDownloadPath,
      'isFirstRun': isFirstRun,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      defaultSftpPath: map['defaultSftpPath'],
      defaultDownloadPath: map['defaultDownloadPath'],
      isFirstRun: map['isFirstRun'] ?? true, 
    );
  }

  static AppSettings get defaults {
    return const AppSettings(
      defaultSftpPath: '/',
      defaultDownloadPath: null,
      isFirstRun: true,
    );
  }
}