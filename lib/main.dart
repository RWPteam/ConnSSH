import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'pages/home.dart';
import 'models/app_settings_model.dart';
import 'services/setting_service.dart';
import 'services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  const platform = MethodChannel('com.samuioto.connecter/background_task');
  platform.setMethodCallHandler((call) async {
    return null;
  });

  // 初始化通知服务
  NotificationService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final SettingsService _settingsService = SettingsService();

  AppSettings _currentSettings = AppSettings.defaults;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> loadSettings() async {
    final settings = await _settingsService.getSettings();
    setState(() {
      _currentSettings = settings;
      _isLoading = false;
    });
  }

  ThemeMode _getThemeMode() {
    switch (_currentSettings.defaultThemeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

    const List<Locale> supportedLocales = [Locale('zh', 'CH')];

    if (_isLoading) {
      return const MaterialApp(
        localizationsDelegates: localizationsDelegates,
        supportedLocales: supportedLocales,
        locale: Locale('zh', 'CH'),
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'ConnSSH',
          localizationsDelegates: localizationsDelegates,
          supportedLocales: supportedLocales,
          locale: const Locale('zh', 'CH'),
          theme:
              _currentSettings.defaultPageTheme == 'materialyou' &&
                  lightDynamic != null
              ? _buildTheme(
                  Brightness.light,
                ).copyWith(colorScheme: lightDynamic)
              : _buildTheme(Brightness.light),
          darkTheme:
              _currentSettings.defaultPageTheme == 'materialyou' &&
                  darkDynamic != null
              ? _buildTheme(Brightness.dark).copyWith(colorScheme: darkDynamic)
              : _buildTheme(Brightness.dark),
          themeMode: _getThemeMode(),
          home: MainPage(
            settingsService: _settingsService,
            onSettingsChanged: loadSettings,
          ),
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(),
              child: child!,
            );
          },
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    if (_currentSettings.defaultPageTheme == 'materialyou') {
      // Material You 使用系统颜色方案
      return ThemeData(
        fontFamily: 'hmossans',
        useMaterial3: true,
        brightness: brightness,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      );
    }

    if (_currentSettings.defaultPageTheme == 'monochrome') {
      final isDark = brightness == Brightness.dark;
      ColorScheme colorScheme;

      if (isDark) {
        colorScheme = ColorScheme(
          brightness: Brightness.dark,
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.grey[300]!,
          onSecondary: Colors.black,
          error: Colors.redAccent,
          onError: Colors.white,
          surface: Colors.grey[900]!,
          onSurface: Colors.white,
          surfaceContainerHighest: Colors.grey[800]!,
          onSurfaceVariant: Colors.grey[300]!,
          outline: Colors.grey[700]!,
          outlineVariant: Colors.grey[800]!,
          shadow: Colors.black,
          scrim: Colors.black54,
          inverseSurface: Colors.grey[200]!,
          onInverseSurface: Colors.black,
          inversePrimary: Colors.black,
          primaryContainer: Colors.grey[900]!,
          onPrimaryContainer: Colors.white,
          secondaryContainer: Colors.grey[800]!,
          onSecondaryContainer: Colors.white,
          tertiary: Colors.grey[500]!,
          onTertiary: Colors.black,
          tertiaryContainer: Colors.grey[700]!,
          onTertiaryContainer: Colors.white,
          errorContainer: Colors.red[900]!,
          onErrorContainer: Colors.white,
          surfaceTint: Colors.transparent,
        );
      } else {
        colorScheme = ColorScheme(
          brightness: Brightness.light,
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Colors.grey[700]!,
          onSecondary: Colors.white,
          error: Colors.redAccent,
          onError: Colors.white,
          surface: Colors.grey[100]!,
          onSurface: Colors.black,
          surfaceContainerHighest: Colors.grey[200]!,
          onSurfaceVariant: Colors.grey[800]!,
          outline: Colors.grey[300]!,
          outlineVariant: Colors.grey[200]!,
          shadow: Colors.black,
          scrim: Colors.black54,
          inverseSurface: Colors.grey[800]!,
          onInverseSurface: Colors.white,
          inversePrimary: Colors.white,
          primaryContainer: Colors.grey[100]!,
          onPrimaryContainer: Colors.black,
          secondaryContainer: Colors.grey[200]!,
          onSecondaryContainer: Colors.black,
          tertiary: Colors.grey[500]!,
          onTertiary: Colors.white,
          tertiaryContainer: Colors.grey[300]!,
          onTertiaryContainer: Colors.black,
          errorContainer: Colors.red[100]!,
          onErrorContainer: Colors.red[900]!,
          surfaceTint: Colors.transparent,
        );
      }

      return ThemeData(
        fontFamily: 'hmossans',
        colorScheme: colorScheme,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      );
    }

    Color seedColor;
    switch (_currentSettings.defaultPageTheme) {
      case 'orange':
        seedColor = Colors.orange;
        break;
      case 'green':
        seedColor = Colors.green;
        break;
      case 'yellow':
        seedColor = Colors.yellow;
        break;
      case 'red':
        seedColor = Colors.red;
        break;
      case 'pink':
        seedColor = Colors.pink;
        break;
      case 'purple':
        seedColor = Colors.purple;
        break;
      case 'cyan':
        seedColor = Colors.cyan;
        break;
      case 'indigo':
        seedColor = Colors.indigo;
        break;
      case 'default':
      default:
        seedColor = Colors.blueAccent;
    }

    return ThemeData(
      fontFamily: 'hmossans',
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
