import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'models/connection_model.dart';
import 'models/credential_model.dart';
import 'services/storage_service.dart';
import 'services/ssh_service.dart';
import 'quick_connect_dialog.dart';

class ServerMetrics {
  final double cpuUsage;
  final double memoryUsage;
  final double memoryTotal;
  final double memoryUsed;
  final List<DiskUsage> diskUsage;
  final String uptime;
  final double loadAverage15;

  ServerMetrics({
    required this.cpuUsage,
    required this.memoryUsage,
    required this.memoryTotal,
    required this.memoryUsed,
    required this.diskUsage,
    required this.uptime,
    required this.loadAverage15,
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

    return ServerMetrics(
      cpuUsage: (json['cpu'] ?? 0).toDouble(),
      memoryTotal: totalMem,
      memoryUsed: usedMem,
      memoryUsage: memUsage,
      diskUsage: disks,
      uptime: json['uptime']?.toString() ?? '未知',
      loadAverage15: (load['15min'] ?? 0).toDouble(),
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

class MonitorServerPage extends StatefulWidget {
  const MonitorServerPage({super.key});

  @override
  State<MonitorServerPage> createState() => _MonitorServerPageState();
}

class _MonitorServerPageState extends State<MonitorServerPage> {
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

  final String _monitorScript = r'''
    #!/bin/bash
    export LC_ALL=C
    set +o history
    set +o vi

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
      df -h 2>/dev/null | grep -E '^/dev/|^/' | grep -vE 'loop|tmpfs|snap' | awk 'BEGIN{ORS=","} {printf "{\"filesystem\":\"%s\",\"size\":\"%s\",\"used\":\"%s\",\"available\":\"%s\",\"usePercent\":\"%s\",\"mounted\":\"%s\"}", $1, $2, $3, $4, $5, $6}' | sed 's/,$//'
    }

    get_load() {
      read l1 l5 l15 rest < /proc/loadavg 2>/dev/null
      printf "{\"1min\":%s,\"5min\":%s,\"15min\":%s}" $l1 $l5 $l15
    }

    get_uptime() {
      uptime -p 2>/dev/null | sed 's/"/\\"/g' | tr -d '\n'
    }

    CPU_RAW=$(get_cpu)
    MEM=$(get_mem)
    DISK=$(get_disk)
    LOAD=$(get_load)
    UPTIME=$(get_uptime)

    echo "{\"cpu\":$CPU_RAW, \"memory\":$MEM, \"disk\":[$DISK], \"load\":$LOAD, \"uptime\":\"$UPTIME\"}"
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
    _sshService.disconnect();
    super.dispose();
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
    });

    try {
      final credentials = await _storageService.getCredentials();
      final credential = credentials.firstWhere(
        (c) => c.id == _selectedConnection!.credentialId,
        orElse: () => throw Exception('找不到认证凭证'),
      );

      await _sshService.connect(_selectedConnection!, credential)
          .timeout(const Duration(seconds: 10));

      final setupCmd = "cat << 'EOF' > $_monitorScriptPath\n$_monitorScript\nEOF\nchmod +x $_monitorScriptPath";
      await _sshService.executeCommand(setupCmd);

      setState(() {
        _selectedCredential = credential;
        _isLoading = false;
        _isMonitoring = true;
      });

      _startMonitoring();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isMonitoring = false; 
        _errorMessage = '服务设置失败: $e';
      });
      _cleanupRemoteScript(); 
      _sshService.disconnect(); 
    }
  }

  Future<void> _cleanupRemoteScript() async {
    try {
      if (_sshService.isConnected()) {
        await _sshService.executeCommand(_cleanupScriptCommand);
        print('远程脚本清理成功: $_monitorScriptPath');
      }
    } catch (e) {
      print('远程脚本清理失败 (可能已断开连接): $e');
    }
  }

  void _disconnectFromServer() {
    _stopMonitoring();
    _cleanupRemoteScript();
    _sshService.disconnect();
    setState(() {
      _isMonitoring = false;
      _serverMetrics = null;
      _selectedCredential = null;
      _errorMessage = '';
    });
  }

  void _startMonitoring() {
    _fetchServerMetrics(); 
    _monitorTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchServerMetrics();
    });
  }

  void _stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
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
        print('Decoder Error: Could not parse chunk starting at index $currentIndex. Remaining: ${cleanStr.substring(currentIndex)}');
        return encodedStr;
      }
    }
    
    final result = buffer.toString();
    
    if (result.trim().startsWith('{')) {
      print('SSH Output SUCCESSFULLY DECODED (Variable Length): $result');
      return result;
    }
    
    print('Decoder Warning: Decoded string does not start with "{". Result: $result');
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

      // 尝试解码，如果失败则使用原始输出
      final decodedStr = _decodeSshOutput(rawOutput);

      if (decodedStr.trim().startsWith('{')) {
          jsonStr = decodedStr;
      } else {
          print('Decode failed. Attempting with raw output.');
      }
      
      final startIndex = jsonStr.indexOf('{');
      final endIndex = jsonStr.lastIndexOf('}');
      
      if (startIndex == -1 || endIndex == -1) {
        throw Exception("无法解析服务器返回的数据格式，此功能可能不适用于您的服务器");
      }

      final cleanJson = jsonStr.substring(startIndex, endIndex + 1);
      final Map<String, dynamic> data = jsonDecode(cleanJson);

      final cpuUsageRaw = (data['cpu'] ?? 0).toDouble();
      data['cpu'] = cpuUsageRaw ; //Raw数据就是正确的

      if (mounted) {
        setState(() {
          _serverMetrics = ServerMetrics.fromJson(data);
          _errorMessage = '';
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '获取数据失败: $e\n(服务器返回了非标准数据或解码失败)';
          _stopMonitoring(); 
          _cleanupRemoteScript(); // 清理脚本
          _sshService.disconnect();
          _isMonitoring = false; // 更新状态以改变按钮文本
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

  // 调整 _showError 以使用主题色
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


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据面板'),
        // 移除右上角的停止按钮
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
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
                          borderRadius: BorderRadius.circular(10.0), 
                        ),
                      ),
                      items: [
                        if (_savedConnections.isEmpty)
                          const DropdownMenuItem(
                            value: null,
                            child: Text('请选择连接'),
                          ),
                        ..._savedConnections.map((connection) {
                          return DropdownMenuItem(
                            value: connection,
                            child: Text(connection.name),
                          );
                        }),
                      ],
                      // 监控中禁止修改连接
                      onChanged: _isMonitoring ? null : (value) {
                        setState(() {
                          _selectedConnection = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_errorMessage.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16), // 增加底部边距
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
                        // 快速连接按钮
                        OutlinedButton(
                          onPressed: _isMonitoring ? null : _showQuickConnectDialog, // 监控中禁止快速连接
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            side: BorderSide(
                              color: _isMonitoring ? colorScheme.onSurface.withOpacity(0.12) : colorScheme.outline,
                            ),
                          ),
                          child: const Text('快速连接'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _isMonitoring 
                            ? ElevatedButton.icon(
                              onPressed: _isLoading ? null : _handleConnectOrDisconnect, 
                              style: ElevatedButton.styleFrom(
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
                                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary), 
                                        ),
                                      )
                                  : const Icon(Icons.stop),
                              label: Text(
                                _isLoading ? '连接中...' : '停止监控',
                                style: const TextStyle(fontSize: 16),
                              ),
                            )
                            : OutlinedButton.icon( 
                              onPressed: _isLoading || _selectedConnection == null ? null : _handleConnectOrDisconnect, 
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
                                          valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
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
            ),

            const SizedBox(height: 16),

           
            if (_isMonitoring && _serverMetrics != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                     
                      _buildUptimeCard(_serverMetrics!.uptime),
                      const SizedBox(height: 12),
                      
                      // CPU使用率
                      _buildAnimatedMetricCard(
                        title: 'CPU使用率',
                        currentUsage: _serverMetrics!.cpuUsage,
                        icon: Icons.memory,
                       
                        subtitle: '15分钟负载: ${_serverMetrics!.loadAverage15.toStringAsFixed(2)}%', 
                      ),

                      const SizedBox(height: 12),

                      // 内存使用率
                      _buildAnimatedMetricCard(
                        title: '内存使用',
                        currentUsage: _serverMetrics!.memoryUsage,
                        icon: Icons.sd_storage,
                        subtitle: '已用: ${_serverMetrics!.memoryUsed.toStringAsFixed(0)} MB /  ${_serverMetrics!.memoryTotal.toStringAsFixed(0)} MB',
                      ),

                      const SizedBox(height: 12),

                      // 磁盘使用情况
                      Card(
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
                                const Text("无磁盘信息"),
                              ..._serverMetrics!.diskUsage.map((disk) {
                                final usagePercent = double.tryParse(
                                  disk.usePercent.replaceAll('%', ''),
                                ) ?? 0;
                                return _buildDiskUsageItem(disk, usagePercent);
                              }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              )
            else if (_isMonitoring)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('正在获取服务器信息...'),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.monitor_heart_outlined, size: 64, color: colorScheme.onSurface.withOpacity(0.5)), // 使用主题色
                      const SizedBox(height: 16),
                      Text(
                        '请选择一个服务器连接并开始监控',
                        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)), // 使用主题色
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUptimeCard(String uptime) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
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

    // 使用 TweenAnimationBuilder 来实现数字的平滑变化
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: currentUsage),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, child) {
        final animatedValue = value.toStringAsFixed(1);
        final animatedProgressValue = (value / 100).clamp(0.0, 1.0);
        
        return Card(
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
                      '$animatedValue%', // 使用动画值
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
                    // 使用主题色替换 Colors.grey
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // 使用 ClipRRect 来隐式地对进度条颜色和值进行动画
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: animatedProgressValue, // Flutter 的 LinearProgressIndicator 自带动画效果
                    backgroundColor: colorScheme.surfaceVariant,
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
        // 使用 TweenAnimationBuilder 来平滑过渡进度条的值
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: progressValue),
          duration: const Duration(milliseconds: 500),
          builder: (context, value, child) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: colorScheme.surfaceVariant,
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

  Color _getColorByUsage(BuildContext context, double usage) {
    final colorScheme = Theme.of(context).colorScheme;
    if (usage < 70) return colorScheme.primary;
    if (usage < 85) return colorScheme.secondary; 
    return colorScheme.error; 
  }
}
