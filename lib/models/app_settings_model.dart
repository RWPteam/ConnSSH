class AppSettings {
  final String? defaultSftpPath;
  final String? defaultDownloadPath;
  final bool isFirstRun;
  final double defaultFontSize;
  final String defaultTermTheme;
  final String termType;
  final String defaultPageTheme;
  final String defaultThemeMode;
  final List<int> toolbarLayout;
  final String defaultFonts;

  const AppSettings({
    this.defaultSftpPath,
    this.defaultDownloadPath,
    this.isFirstRun = true,
    this.defaultFontSize = 12.0,
    this.defaultTermTheme = 'dark',
    this.termType = 'xterm-256color',
    this.defaultPageTheme = 'default',
    this.defaultThemeMode = 'system',
    this.toolbarLayout = const [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
    ],
    this.defaultFonts = 'maple', // 默认字体
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
    List<int>? toolbarLayout,
    String? defaultFonts,
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
      toolbarLayout: toolbarLayout ?? this.toolbarLayout,
      defaultFonts: defaultFonts ?? this.defaultFonts,
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
      'toolbarLayout': toolbarLayout,
      'defaultFonts': defaultFonts,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      defaultSftpPath: map['defaultSftpPath'],
      defaultDownloadPath: map['defaultDownloadPath'],
      isFirstRun: map['isFirstRun'] ?? true,
      defaultFontSize: map['defaultFontSize']?.toDouble() ?? 12.0,
      defaultTermTheme: map['defaultTermTheme'] ?? 'dark',
      termType: map['termType'] ?? 'xterm-256color',
      defaultPageTheme: map['defaultPageTheme'] ?? 'default',
      defaultThemeMode: map['defaultThemeMode'] ?? 'system',
      toolbarLayout: List<int>.from(
        map['toolbarLayout'] ??
            [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
      ),
      defaultFonts: map['defaultFonts'] ?? 'maple',
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
      toolbarLayout: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
      defaultFonts: 'maple',
    );
  }
}
