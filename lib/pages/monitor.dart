import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';
import '../services/storage_service.dart';
import '../services/ssh_service.dart';
import '../components/quick_connect_dialog.dart';
import '../components/twofa_dialog.dart';

class ServerMetrics {
  final double cpuUsage;
  final double memoryUsage;
  final double memoryTotal;
  final double memoryUsed;
  final List<DiskUsage> diskUsage;
  final String uptime;
  final double loadAverage15;
  final List<ProcessInfo> processes;
  final NetworkSpeed networkSpeed;

  ServerMetrics({
    required this.cpuUsage,
    required this.memoryUsage,
    required this.memoryTotal,
    required this.memoryUsed,
    required this.diskUsage,
    required this.uptime,
    required this.loadAverage15,
    required this.processes,
    required this.networkSpeed,
  });

  factory ServerMetrics.fromJson(Map<String, dynamic> json) {
    final mem = json['memory'] ?? {};
    double totalMem = (mem['total'] ?? 0).toDouble();
    double usedMem = (mem['used'] ?? 0).toDouble();
    double memUsage = totalMem > 0 ? (usedMem / totalMem) * 100 : 0.0;

    List<DiskUsage> disks = [];
    if (json['disk'] != null) {
      for (var d in json['disk']) {
        disks.add(DiskUsage(
          filesystem: d['filesystem']?.toString() ?? '',
          size: d['size']?.toString() ?? '',
          used: d['used']?.toString() ?? '',
          available: d['available']?.toString() ?? '',
          usePercent: d['usePercent']?.toString() ?? '',
          mounted: d['mounted']?.toString() ?? '',
        ));
      }
    }

    final load = json['load'] ?? {};

    List<ProcessInfo> processes = [];
    if (json['processes'] != null) {
      for (var p in json['processes']) {
        processes.add(ProcessInfo(
          user: p['user']?.toString() ?? '',
          pid: p['pid']?.toString() ?? '',
          cpu: p['cpu']?.toString() ?? '',
          mem: p['mem']?.toString() ?? '',
          command: p['command']?.toString() ?? '',
        ));
      }
    }

    final net = json['network'] ?? {};

    return ServerMetrics(
      cpuUsage: (json['cpu'] ?? 0).toDouble(),
      memoryTotal: totalMem,
      memoryUsed: usedMem,
      memoryUsage: memUsage,
      diskUsage: disks,
      uptime: json['uptime']?.toString() ?? '未知',
      loadAverage15: (load['15min'] ?? 0).toDouble(),
      processes: processes,
      networkSpeed: NetworkSpeed(
        rxBytes: (net['rx_bytes'] ?? 0).toInt(),
        txBytes: (net['tx_bytes'] ?? 0).toInt(),
        rxSpeed: (net['rx_speed'] ?? 0).toDouble(),
        txSpeed: (net['tx_speed'] ?? 0).toDouble(),
      ),
    );
  }
}

class DiskUsage {
  final String filesystem;
  final String size;
  final String used;
  final String available;
  final String usePercent;
  final String mounted;

  DiskUsage({
    required this.filesystem,
    required this.size,
    required this.used,
    required this.available,
    required this.usePercent,
    required this.mounted,
  });
}

class ProcessInfo {
  final String user;
  final String pid;
  final String cpu;
  final String mem;
  final String command;

  ProcessInfo({
    required this.user,
    required this.pid,
    required this.cpu,
    required this.mem,
    required this.command,
  });
}

class NetworkSpeed {
  final int rxBytes;
  final int txBytes;
  final double rxSpeed;
  final double txSpeed;

  NetworkSpeed({
    required this.rxBytes,
    required this.txBytes,
    required this.rxSpeed,
    required this.txSpeed,
  });
}

class MonitorServerPage extends StatefulWidget {
  const MonitorServerPage({super.key});

  @override
  State<MonitorServerPage> createState() => _MonitorServerPageState();
}

class _MonitorServerPageState extends State<MonitorServerPage> {
  Timer? _firstDataTimeoutTimer;
  final StorageService _storageService = StorageService();
  final SshService _sshService = SshService();
  List<ConnectionInfo> _savedConnections = [];
  ConnectionInfo? _selectedConnection;
  Credential? _selectedCredential;
  bool _isLoading = false;
  bool _isMonitoring = false;
  Timer? _monitorTimer;
  ServerMetrics? _serverMetrics;
  String _errorMessage = '';

  int _lastRxBytes = 0;
  int _lastTxBytes = 0;
  DateTime? _lastNetworkTime;
  double _rxSpeed = 0.0;
  double _txSpeed = 0.0;

  bool _needsTwoFactorAuth = false;
  Completer<String?>? _twoFactorCompleter;

  final String _monitorScript = r'''
    #!/bin/bash
    export LC_ALL=C
    set +o history

    get_cpu() {
      read cpu a b c idle rest < /proc/stat 2>/dev/null
      total=$((a+b+c+idle))
      sleep 0.1 
      read cpu2 a2 b2 c2 idle2 rest < /proc/stat 2>/dev/null
      total2=$((a2+b2+c2+idle2))
      if [ $((total2-total)) -eq 0 ]; then
        echo "0"
      else
        echo "$((1000*( (total2-total) - (idle2-idle) ) / (total2-total) / 10 ))"
      fi
    }

    get_mem() {
      free -m 2>/dev/null | grep Mem | awk '{printf "{\"total\":%s,\"used\":%s,\"free\":%s}", $2, $3, $4}'
    }

    get_disk() {
      df -Ph 2>/dev/null | grep -E '^/dev/|^/' | grep -vE 'loop|tmpfs|snap' | awk '
      BEGIN { first=1 }
      {
        if (!first) printf ",";
        printf "{\"filesystem\":\"%s\",\"size\":\"%s\",\"used\":\"%s\",\"available\":\"%s\",\"usePercent\":\"%s\",\"mounted\":\"%s\"}", $1, $2, $3, $4, $5, $6;
        first=0
      }'
    }

    get_load() {
      read l1 l5 l15 rest < /proc/loadavg 2>/dev/null
      printf "{\"1min\":%s,\"5min\":%s,\"15min\":%s}" ${l1:-0} ${l5:-0} ${l15:-0}
    }

    get_uptime() {
      uptime -p 2>/dev/null | sed 's/"/\\"/g' | tr -d '\n'
    }

    get_network() {
      rx_total=0
      tx_total=0
      
      for iface in /sys/class/net/*; do
        iface_name=$(basename $iface)
        if [ "$iface_name" != "lo" ]; then
          if [ -r "$iface/statistics/rx_bytes" ] && [ -r "$iface/statistics/tx_bytes" ]; then
            rx_bytes=$(cat "$iface/statistics/rx_bytes" 2>/dev/null)
            tx_bytes=$(cat "$iface/statistics/tx_bytes" 2>/dev/null)
            if [ ! -z "$rx_bytes" ] && [ ! -z "$tx_bytes" ]; then
              rx_total=$((rx_total + rx_bytes))
              tx_total=$((tx_total + tx_bytes))
            fi
          fi
        fi
      done
      
      printf "{\"rx_bytes\":%s,\"tx_bytes\":%s}" $rx_total $tx_total
    }

    get_processes() {
      ps aux --sort=-%cpu | head -11 | tail -10 | awk '
      BEGIN { 
        first=1
        getline
      }
      {
        cmd = $11
        for (i=12; i<=NF; i++) {
          cmd = cmd " " $i
        }
        if (length(cmd) > 30) {
          cmd = substr(cmd, 1, 27) "..."
        }
        
        gsub(/"/, "\\\"", cmd)
        gsub(/"/, "\\\"", $1)
        
        if (!first) printf ",";
        printf "{\"user\":\"%s\",\"pid\":\"%s\",\"cpu\":\"%s\",\"mem\":\"%s\",\"command\":\"%s\"}", $1, $2, $3, $4, cmd;
        first=0
      }'
    }

    CPU_RAW=$(get_cpu)
    MEM=$(get_mem)
    DISK=$(get_disk)
    LOAD=$(get_load)
    UPTIME=$(get_uptime)
    NETWORK=$(get_network)
    PROCESSES=$(get_processes)

    echo "{\"cpu\":$CPU_RAW, \"memory\":$MEM, \"disk\":[$DISK], \"load\":$LOAD, \"uptime\":\"$UPTIME\", \"network\":$NETWORK, \"processes\":[$PROCESSES]}"
  ''';

  final String _cleanupScriptCommand = 'rm -f /tmp/connssh_monitor.sh';
  final String _monitorScriptPath = '/tmp/connssh_monitor.sh';

  @override
  void initState() {
    super.initState();
    _loadSavedConnections();
  }

  @override
  void dispose() {
    _stopMonitoring();
    _cleanupRemoteScript();
    _firstDataTimeoutTimer?.cancel();
    _sshService.disconnect();
    if (_twoFactorCompleter != null && !_twoFactorCompleter!.isCompleted) {
      _twoFactorCompleter!.complete(null);
    }
    super.dispose();
  }

  Future<String?> _showTwoFactorAuthDialog(
    String connectionName,
    String host,
    String prompt,
  ) async {
    if (mounted) {
      setState(() {
        _errorMessage = '$prompt\n请在对话框中输入验证码';
        _needsTwoFactorAuth = true;
      });
    }

    _twoFactorCompleter = Completer<String?>();

    final code = await TwoFactorAuthDialog.show(
      context,
      connectionName: connectionName,
      host: host,
      prompt: prompt,
    );

    _twoFactorCompleter = null;
    if (mounted) {
      setState(() {
        _needsTwoFactorAuth = false;
        if (code == null || code.isEmpty) {
          _errorMessage = '2FA 验证已取消';
        } else {
          _errorMessage = '正在验证 2FA 码...';
        }
      });
    }

    return code;
  }

  Future<void> _loadSavedConnections() async {
    try {
      final connections = await _storageService.getConnections();
      setState(() {
        _savedConnections = connections;
        if (connections.isNotEmpty && _selectedConnection == null) {
          _selectedConnection = connections.first;
        }
      });
    } catch (e) {
      _showError('加载已保存连接失败: $e');
    }
  }

  void _handleConnectOrDisconnect() {
    if (_isMonitoring) {
      _disconnectFromServer();
    } else {
      _connectToServer();
    }
  }

  Future<void> _connectToServer() async {
    if (_selectedConnection == null) {
      _showError('请选择一个连接');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _lastRxBytes = 0;
      _lastTxBytes = 0;
      _lastNetworkTime = null;
      _rxSpeed = 0.0;
      _txSpeed = 0.0;
      _needsTwoFactorAuth = false;
    });

    try {
      final credentials = await _storageService.getCredentials();
      final credential = credentials.firstWhere(
        (c) => c.id == _selectedConnection!.credentialId,
        orElse: () => throw Exception('找不到认证凭证'),
      );

      await _sshService.connect(
        _selectedConnection!,
        credential,
        onTwoFactorAuth: (connectionName, host, prompt) async {
          return await _showTwoFactorAuthDialog(
            connectionName,
            host,
            prompt,
          );
        },
      ).timeout(const Duration(seconds: 30));

      final setupCmd =
          "cat << 'EOF' > $_monitorScriptPath\n$_monitorScript\nEOF\nchmod +x $_monitorScriptPath";
      await _sshService.executeCommand(setupCmd);

      setState(() {
        _selectedCredential = credential;
        _isLoading = false;
        _isMonitoring = true;
      });

      _startMonitoring();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isMonitoring = false;
          _errorMessage = '连接失败: $e';
        });
      }
      _cleanupRemoteScript();
      _sshService.disconnect();
    }
  }

  Future<void> _cleanupRemoteScript() async {
    try {
      if (_sshService.isConnected()) {
        await _sshService.executeCommand(_cleanupScriptCommand);
      }
    } catch (e) {}
  }

  void _disconnectFromServer() {
    _stopMonitoring();
    _cleanupRemoteScript();
    _sshService.disconnect();

    if (_twoFactorCompleter != null && !_twoFactorCompleter!.isCompleted) {
      _twoFactorCompleter!.complete(null);
    }

    if (mounted) {
      setState(() {
        _isMonitoring = false;
        _serverMetrics = null;
        _selectedCredential = null;
        _errorMessage = '';
        _lastRxBytes = 0;
        _lastTxBytes = 0;
        _lastNetworkTime = null;
        _rxSpeed = 0.0;
        _txSpeed = 0.0;
        _needsTwoFactorAuth = false;
      });
    }
  }

  void _startMonitoring() {
    _fetchServerMetrics();
    _firstDataTimeoutTimer?.cancel();
    _firstDataTimeoutTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isMonitoring && _serverMetrics == null) {
        _handleFirstDataTimeout();
      }
    });
    _monitorTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchServerMetrics();
    });
  }

  void _handleFirstDataTimeout() {
    setState(() {
      _errorMessage = '连接超时';
    });
    _disconnectFromServer();
  }

  void _stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _firstDataTimeoutTimer?.cancel();
    _firstDataTimeoutTimer = null;
  }

  String _decodeSshOutput(String encodedStr) {
    final cleanStr = encodedStr.trim();

    if (!RegExp(r'^\d+$').hasMatch(cleanStr) || cleanStr.isEmpty) {
      return encodedStr;
    }

    final StringBuffer buffer = StringBuffer();
    int currentIndex = 0;

    while (currentIndex < cleanStr.length) {
      int code = -1;
      int charLength = 0;

      if (currentIndex + 3 <= cleanStr.length) {
        final sub3 = cleanStr.substring(currentIndex, currentIndex + 3);
        code = int.tryParse(sub3) ?? -1;
        if (code >= 100 && code <= 127) {
          charLength = 3;
        } else {
          code = -1;
        }
      }

      if (code == -1 && currentIndex + 2 <= cleanStr.length) {
        final sub2 = cleanStr.substring(currentIndex, currentIndex + 2);
        code = int.tryParse(sub2) ?? -1;
        if (code >= 10 && code <= 99) {
          charLength = 2;
        } else {
          code = -1;
        }
      }

      if (code != -1 && charLength > 0) {
        buffer.writeCharCode(code);
        currentIndex += charLength;
      } else {
        print(
            'Decoder Error: Could not parse chunk starting at index $currentIndex. Remaining: ${cleanStr.substring(currentIndex)}');
        return encodedStr;
      }
    }

    final result = buffer.toString();

    if (result.trim().startsWith('{')) {
      return result;
    }

    return encodedStr;
  }

  Future<void> _fetchServerMetrics() async {
    if (_selectedConnection == null || _selectedCredential == null) return;

    try {
      String rawOutput = await _sshService.executeCommand(_monitorScriptPath);

      if (rawOutput.isEmpty) {
        throw Exception("服务器返回数据为空");
      }

      String jsonStr = rawOutput;

      final decodedStr = _decodeSshOutput(rawOutput);

      if (decodedStr.trim().startsWith('{')) {
        jsonStr = decodedStr;
      }

      final startIndex = jsonStr.indexOf('{');
      final endIndex = jsonStr.lastIndexOf('}');

      if (startIndex == -1 || endIndex == -1) {
        throw Exception("无法解析服务器返回的数据格式，此功能可能不适用于您的服务器");
      }

      final cleanJson = jsonStr.substring(startIndex, endIndex + 1);
      final Map<String, dynamic> data = jsonDecode(cleanJson);

      final cpuUsageRaw = (data['cpu'] ?? 0).toDouble();
      data['cpu'] = cpuUsageRaw;

      final network = data['network'] ?? {};
      final rxBytes = (network['rx_bytes'] ?? 0).toInt();
      final txBytes = (network['tx_bytes'] ?? 0).toInt();
      final now = DateTime.now();

      if (_lastNetworkTime != null && _lastRxBytes > 0 && _lastTxBytes > 0) {
        final timeDiff = now.difference(_lastNetworkTime!).inSeconds;
        if (timeDiff > 0) {
          _rxSpeed = (rxBytes - _lastRxBytes) / timeDiff;
          _txSpeed = (txBytes - _lastTxBytes) / timeDiff;
        }
      }

      _lastRxBytes = rxBytes;
      _lastTxBytes = txBytes;
      _lastNetworkTime = now;

      network['rx_speed'] = _rxSpeed;
      network['tx_speed'] = _txSpeed;

      if (mounted) {
        setState(() {
          _serverMetrics = ServerMetrics.fromJson(data);
          _errorMessage = '';
          _firstDataTimeoutTimer?.cancel();
          _firstDataTimeoutTimer = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '获取数据失败: $e\n(服务器返回了非标准数据或解码失败)';
          _stopMonitoring();
          _cleanupRemoteScript();
          _sshService.disconnect();
          _isMonitoring = false;
        });
      }
    }
  }

  void _showQuickConnectDialog() {
    showDialog(
      context: context,
      builder: (context) => const QuickConnectDialog(),
    ).then((_) {
      _loadSavedConnections();
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildConnectionPanel() {
    final colorScheme = Theme.of(context).colorScheme;
    final Map<String, ConnectionInfo> uniqueMap = {};
    for (var conn in _savedConnections) {
      final String key =
          '${conn.name}-${conn.host}-${conn.port}-${conn.credentialId}';

      if (!uniqueMap.containsKey(key)) {
        uniqueMap[key] = conn;
      }
    }
    final List<ConnectionInfo> filteredConnections = uniqueMap.values.toList();

    if (_selectedConnection != null &&
        !filteredConnections.contains(_selectedConnection)) {
      final String selectedKey =
          '${_selectedConnection!.name}-${_selectedConnection!.host}-${_selectedConnection!.port}-${_selectedConnection!.credentialId}';
      _selectedConnection = uniqueMap[selectedKey] ??
          (filteredConnections.isNotEmpty ? filteredConnections.first : null);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择服务器连接',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ConnectionInfo>(
              value: _selectedConnection,
              decoration: InputDecoration(
                labelText: '已保存的连接',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
              ),
              items: [
                if (filteredConnections.isEmpty)
                  const DropdownMenuItem(
                    value: null,
                    child: Text('请选择连接'),
                  ),
                ...filteredConnections.map((connection) {
                  return DropdownMenuItem(
                    value: connection,
                    child: Text(connection.name),
                  );
                }),
              ],
              onChanged: _isMonitoring
                  ? null
                  : (value) {
                      setState(() {
                        _selectedConnection = value;
                      });
                    },
            ),
            const SizedBox(height: 16),
            if (_needsTwoFactorAuth)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    Icon(Icons.security, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '需要双因素认证 (2FA)\n请在弹出的对话框中输入验证码',
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            if (_errorMessage.isNotEmpty && !_needsTwoFactorAuth)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.error),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _isMonitoring ? null : _showQuickConnectDialog,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 16),
                    side: BorderSide(
                      color: _isMonitoring
                          ? colorScheme.onSurface.withOpacity(0.12)
                          : colorScheme.outline,
                    ),
                  ),
                  child: const Text('快速连接'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _isMonitoring
                      ? OutlinedButton.icon(
                          onPressed:
                              _isLoading ? null : _handleConnectOrDisconnect,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          icon: _isLoading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        colorScheme.onPrimary),
                                  ),
                                )
                              : const Icon(Icons.stop),
                          label: Text(
                            _isLoading ? '连接中...' : '停止监控',
                            style: const TextStyle(fontSize: 16),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: _isLoading || _selectedConnection == null
                              ? null
                              : _handleConnectOrDisconnect,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: colorScheme.primary),
                          ),
                          icon: _isLoading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        colorScheme.primary),
                                  ),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(
                            _isLoading ? '连接中...' : '开始监控',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataPanel() {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isMonitoring && _serverMetrics != null) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _buildUptimeCard(_serverMetrics!.uptime),
            const SizedBox(height: 12),
            _buildAnimatedMetricCard(
              title: 'CPU使用率',
              currentUsage: _serverMetrics!.cpuUsage,
              icon: Icons.memory,
              subtitle:
                  '15分钟负载: ${_serverMetrics!.loadAverage15.toStringAsFixed(2)}%',
            ),
            const SizedBox(height: 12),
            _buildAnimatedMetricCard(
              title: '内存使用',
              currentUsage: _serverMetrics!.memoryUsage,
              icon: Icons.sd_storage,
              subtitle:
                  '已用: ${_serverMetrics!.memoryUsed.toStringAsFixed(0)} MB / ${_serverMetrics!.memoryTotal.toStringAsFixed(0)} MB',
            ),
            const SizedBox(height: 12),
            _buildDiskUsageCard(),
            const SizedBox(height: 12),
            _buildNetworkSpeedCard(),
            const SizedBox(height: 12),
            _buildProcessListCard(),
          ],
        ),
      );
    } else if (_isMonitoring) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在获取服务器信息...'),
          ],
        ),
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.monitor_heart_outlined,
                size: 64, color: colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              '请选择一个服务器连接并开始监控',
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据面板'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isLandscape
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 320,
                    child: _buildConnectionPanel(),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDataPanel(),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildConnectionPanel(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _buildDataPanel(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildUptimeCard(String uptime) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey, width: 1),
        color: Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '运行时间',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              uptime,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedMetricCard({
    required String title,
    required double currentUsage,
    required IconData icon,
    String? subtitle,
  }) {
    final color = _getColorByUsage(context, currentUsage);
    final colorScheme = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: currentUsage),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, child) {
        final animatedValue = value.toStringAsFixed(1);
        final animatedProgressValue = (value / 100).clamp(0.0, 1.0);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey, width: 1),
            color: Colors.transparent,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$animatedValue%',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: animatedProgressValue,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNetworkSpeedCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final network = _serverMetrics?.networkSpeed;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey, width: 1),
        color: Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '网络速度',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (network != null)
              Row(
                children: [
                  Expanded(
                    child: _buildNetworkSpeedItem(
                      '下载速度',
                      network.rxSpeed,
                      Icons.download,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildNetworkSpeedItem(
                      '上传速度',
                      network.txSpeed,
                      Icons.upload,
                    ),
                  ),
                ],
              )
            else
              const Text('无网络信息'),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkSpeedItem(String title, double speed, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    String formattedSpeed;
    String unit;

    if (speed < 1024) {
      formattedSpeed = speed.toStringAsFixed(1);
      unit = 'B/s';
    } else if (speed < 1024 * 1024) {
      formattedSpeed = (speed / 1024).toStringAsFixed(1);
      unit = 'KB/s';
    } else {
      formattedSpeed = (speed / (1024 * 1024)).toStringAsFixed(1);
      unit = 'MB/s';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formattedSpeed,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiskUsageCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey, width: 1),
        color: Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '磁盘使用情况',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_serverMetrics!.diskUsage.isEmpty)
              const Text("无磁盘信息")
            else
              ..._serverMetrics!.diskUsage.map((disk) {
                final usagePercent = double.tryParse(
                      disk.usePercent.replaceAll('%', ''),
                    ) ??
                    0;
                return _buildDiskUsageItem(disk, usagePercent);
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDiskUsageItem(DiskUsage disk, double usagePercent) {
    final color = _getColorByUsage(context, usagePercent);
    final colorScheme = Theme.of(context).colorScheme;
    final progressValue = (usagePercent / 100).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${disk.mounted} (${disk.filesystem})',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Text(
              '${disk.used}/${disk.size}',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: progressValue),
          duration: const Duration(milliseconds: 500),
          builder: (context, value, child) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildProcessListCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final processes = _serverMetrics?.processes ?? [];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey, width: 1),
        color: Colors.transparent,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.data_array, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '进程列表',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            if (processes.isEmpty)
              const Text('无进程信息')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  horizontalMargin: 0,
                  columns: const [
                    DataColumn(label: Text('用户')),
                    DataColumn(label: Text('PID')),
                    DataColumn(label: Text('CPU（%）')),
                    DataColumn(label: Text('MEM（%）')),
                    DataColumn(
                        label: Text('命令'), numeric: false, tooltip: '进程命令'),
                  ],
                  rows: processes
                      .take(10)
                      .map((process) => DataRow(cells: [
                            DataCell(Text(process.user)),
                            DataCell(Text(process.pid)),
                            DataCell(Text(process.cpu)),
                            DataCell(Text(process.mem)),
                            DataCell(
                              Tooltip(
                                message: process.command,
                                child: SizedBox(
                                  width: 150,
                                  child: Text(
                                    process.command,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          ]))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getColorByUsage(BuildContext context, double usage) {
    final colorScheme = Theme.of(context).colorScheme;
    if (usage < 70) return colorScheme.primary;
    if (usage < 85) return colorScheme.secondary;
    return colorScheme.error;
  }
}
