class AppSettings {
  final String? defaultSftpPath;
  final String? defaultDownloadPath;
  final bool isFirstRun;

  const AppSettings({
    this.defaultSftpPath,
    this.defaultDownloadPath,
    this.isFirstRun = true, 
  });//定义设置的数据结构

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
  }//SFTP默认目录，默认下载位置，是否第一次运行（用于判断是否需要展示帮助）

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      defaultSftpPath: map['defaultSftpPath'],
      defaultDownloadPath: map['defaultDownloadPath'],
      isFirstRun: map['isFirstRun'] ?? true, 
    );
  }//构造设置对象

  static AppSettings get defaults {
    return const AppSettings(
      defaultSftpPath: '/',
      defaultDownloadPath: null,
      isFirstRun: true,
    );
  }//默认设置
}