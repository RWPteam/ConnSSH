import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'pages/home.dart';
import 'models/app_settings_model.dart';
import 'services/setting_service.dart';
import 'widgets/app_style.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  const platform = MethodChannel('com.samuioto.connecter/background_task');
  platform.setMethodCallHandler((call) async {
    return null;
  });


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

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'ConnSSH',
      localizationsDelegates: localizationsDelegates,
      supportedLocales: supportedLocales,
      locale: const Locale('zh', 'CH'),
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _getThemeMode(),
      home: MainPage(
        settingsService: _settingsService,
        onSettingsChanged: loadSettings,
      ),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return AppVisualEffects(
          blurEnabled: _currentSettings.blurEffectsEnabled,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(),
            child: child!,
          ),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final systemOverlayStyle = brightness == Brightness.light
        ? SystemUiOverlayStyle.dark
        : SystemUiOverlayStyle.light;

    Color seedColor;
    bool monochrome = false;
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
      case 'monochrome':
        seedColor = Colors.black;
        monochrome = true;
        break;
      case 'default':
      default:
        seedColor = Colors.blueAccent;
    }

    return AppThemeFactory.build(
      brightness: brightness,
      seedColor: seedColor,
      monochrome: monochrome,
      fontFamily: 'hmossans',
      systemOverlayStyle: systemOverlayStyle,
    );
  }

}
