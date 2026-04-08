enum TelnetTerminalType {
  vt100('VT100'),
  vt220('VT220'),
  vt320('VT320'),
  xterm('XTerm'),
  ansi('ANSI'),
  linux('Linux'),
  dumb('Dumb');

  final String displayName;
  const TelnetTerminalType(this.displayName);
}

enum TelnetLineSeparator {
  cr('\r', 'CR'),
  lf('\n', 'LF'),
  crlf('\r\n', 'CRLF');

  final String value;
  final String displayName;
  const TelnetLineSeparator(this.value, this.displayName);
}
// 在 models/telnet_connection_model.dart 中添加

enum TelnetEncoding {
  utf8('UTF-8'),
  gbk('GBK'),
  gb2312('GB2312'),
  big5('Big5'),
  iso8859_1('ISO-8859-1'),
  ascii('ASCII');

  final String displayName;
  const TelnetEncoding(this.displayName);
}

class TelnetConnectionInfo {
  final String id;
  String name;
  String host;
  int port;
  String? username;
  String? password;
  final bool remember;
  final TelnetTerminalType terminalType;
  final TelnetLineSeparator lineSeparator;
  final TelnetEncoding encoding; // 新增编码字段
  DateTime lastUsed;

  TelnetConnectionInfo({
    required this.id,
    required this.name,
    required this.host,
    this.port = 23,
    this.username,
    this.password,
    this.remember = true,
    this.terminalType = TelnetTerminalType.xterm,
    this.lineSeparator = TelnetLineSeparator.crlf,
    this.encoding = TelnetEncoding.utf8, // 默认使用UTF-8
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();

  factory TelnetConnectionInfo.fromMap(Map<String, dynamic> map) {
    return TelnetConnectionInfo(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      host: map['host'] ?? '',
      port: map['port'] ?? 23,
      username: map['username'],
      password: map['password'],
      remember: map['remember'] ?? true,
      terminalType: TelnetTerminalType.values.firstWhere(
        (e) => e.toString().split('.').last == map['terminalType'],
        orElse: () => TelnetTerminalType.xterm,
      ),
      lineSeparator: TelnetLineSeparator.values.firstWhere(
        (e) => e.toString().split('.').last == map['lineSeparator'],
        orElse: () => TelnetLineSeparator.crlf,
      ),
      encoding: TelnetEncoding.values.firstWhere(
        (e) => e.toString().split('.').last == map['encoding'],
        orElse: () => TelnetEncoding.utf8,
      ),
      lastUsed: map['lastUsed'] != null
          ? DateTime.parse(map['lastUsed'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'remember': remember,
      'terminalType': terminalType.toString().split('.').last,
      'lineSeparator': lineSeparator.toString().split('.').last,
      'encoding': encoding.toString().split('.').last,
      'lastUsed': lastUsed.toIso8601String(),
    };
  }
}
