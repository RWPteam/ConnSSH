// app_settings_model.dart
class AppSettings {
  final String? defaultSftpPath;
  final String? defaultDownloadPath;
  final bool isFirstRun;
  final double defaultFontSize;
  final String defaultTermTheme;
  final String termType;
  final String defaultPageTheme;
  final String defaultThemeMode;

  const AppSettings({
    this.defaultSftpPath,
    this.defaultDownloadPath,
    this.isFirstRun = true,
    this.defaultFontSize = 12.0,
    this.defaultTermTheme = 'dark',
    this.termType = 'xterm-256color',
    this.defaultPageTheme = 'default',
    this.defaultThemeMode = 'system',
  });

  AppSettings copyWith({
    String? defaultSftpPath,
    String? defaultDownloadPath,
    bool? isFirstRun,
    double? defaultFontSize,
    String? defaultTermTheme,
    String? termType,
    String? defaultPageTheme,
    String? defaultThemeMode,
  }) {
    return AppSettings(
      defaultSftpPath: defaultSftpPath ?? this.defaultSftpPath,
      defaultDownloadPath: defaultDownloadPath ?? this.defaultDownloadPath,
      isFirstRun: isFirstRun ?? this.isFirstRun,
      defaultFontSize: defaultFontSize ?? this.defaultFontSize,
      defaultTermTheme: defaultTermTheme ?? this.defaultTermTheme,
      termType: termType ?? this.termType,
      defaultPageTheme: defaultPageTheme ?? this.defaultPageTheme,
      defaultThemeMode: defaultThemeMode ?? this.defaultThemeMode,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'defaultSftpPath': defaultSftpPath,
      'defaultDownloadPath': defaultDownloadPath,
      'isFirstRun': isFirstRun,
      'defaultFontSize': defaultFontSize,
      'defaultTermTheme': defaultTermTheme,
      'termType': termType,
      'defaultPageTheme': defaultPageTheme,
      'defaultThemeMode': defaultThemeMode,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      defaultSftpPath: map['defaultSftpPath'],
      defaultDownloadPath: map['defaultDownloadPath'],
      isFirstRun: map['isFirstRun'] ?? true,
      defaultFontSize: map['defaultFontSize']?.toDouble() ?? 10.0,
      defaultTermTheme: map['defaultTermTheme'] ?? 'dark',
      termType: map['termType'] ?? 'xterm-256color',
      defaultPageTheme: map['defaultPageTheme'] ?? 'default',
      defaultThemeMode: map['defaultThemeMode'] ?? 'system',
    );
  }

  static AppSettings get defaults {
    return const AppSettings(
      defaultSftpPath: '/',
      defaultDownloadPath: null,
      isFirstRun: true,
      defaultFontSize: 12.0,
      defaultTermTheme: 'dark',
      termType: 'xterm-256color',
      defaultPageTheme: 'default',
      defaultThemeMode: 'system',
    );
  }
}
