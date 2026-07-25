import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'package:lbjconsole/models/merged_record.dart';
import 'package:lbjconsole/services/database_service.dart';
import 'package:lbjconsole/services/background_service.dart';
import 'package:lbjconsole/services/audio_input_service.dart';
import 'package:lbjconsole/services/rtl_tcp_service.dart';
import 'package:lbjconsole/services/ble_service.dart';
import 'package:lbjconsole/themes/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  final bool temporaryRecordsEnabled;
  final ValueChanged<bool>? onTemporaryRecordsChanged;

  const SettingsScreen({
    super.key,
    this.onSettingsChanged,
    this.temporaryRecordsEnabled = false,
    this.onTemporaryRecordsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late DatabaseService _databaseService;
  late TextEditingController _deviceNameController;
  late TextEditingController _rtlTcpHostController;
  late TextEditingController _rtlTcpPortController;

  bool _settingsLoaded = false;

  String _deviceName = '';
  bool _backgroundServiceEnabled = false;
  bool _notificationsEnabled = true;
  bool _mergeRecordsEnabled = false;
  bool _hideTimeOnlyRecords = false;
  bool _hideUngroupableRecords = false;
  GroupBy _groupBy = GroupBy.trainAndLoco;
  TimeWindow _timeWindow = TimeWindow.unlimited;

  InputSource _inputSource = InputSource.bluetooth;

  String _rtlTcpHost = '127.0.0.1';
  String _rtlTcpPort = '14423';
  int _aboutIconTapCount = 0;
  Timer? _aboutIconTapTimer;

  StreamSubscription<Map<String, dynamic>>? _bleRespSub;
  StreamSubscription<bool>? _bleConnSub;
  Map<String, dynamic>? _sdStatus;
  bool _sdBusy = false;

  @override
  void initState() {
    super.initState();
    _databaseService = DatabaseService.instance;
    _deviceNameController = TextEditingController();
    _rtlTcpHostController = TextEditingController();
    _rtlTcpPortController = TextEditingController();
    _loadSettings();
    _bindReceiverLinks();
  }

  bool get _receiverLinkConnected {
    if (_inputSource != InputSource.bluetooth) return false;
    return BLEService().isConnected;
  }

  String get _receiverLinkLabel {
    if (_inputSource != InputSource.bluetooth) {
      return '请先在信号源中选择蓝牙设备';
    }
    return BLEService().isConnected ? '蓝牙已连接' : '请先连接蓝牙';
  }

  void _onReceiverResp(Map<String, dynamic> resp) {
    if (!mounted) return;
    final cmd = resp['cmd']?.toString();
    setState(() {
      if (cmd == 'sd_status' || cmd == 'sd_clear') {
        _sdStatus = resp;
        _sdBusy = false;
      }
      if (cmd == 'sync') {
        _sdBusy = false;
      }
    });
  }

  void _bindReceiverLinks() {
    final ble = BLEService();
    _sdStatus = ble.lastSdStatus;
    _bleRespSub = ble.responseStream.listen(_onReceiverResp);
    _bleConnSub = ble.connectionStream.listen((connected) {
      if (!mounted) return;
      if (_inputSource != InputSource.bluetooth) return;
      if (connected) {
        ble.requestSdStatus();
      } else {
        setState(() {
          _sdStatus = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _bleRespSub?.cancel();
    _bleConnSub?.cancel();
    _deviceNameController.dispose();
    _rtlTcpHostController.dispose();
    _rtlTcpPortController.dispose();
    _aboutIconTapTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settingsMap = await _databaseService.getAllSettings() ?? {};
    final settings = MergeSettings.fromMap(settingsMap);
    if (mounted) {
      setState(() {
        _deviceName = settingsMap['deviceName'] ?? 'LBJReceiver';
        _deviceNameController.text = _deviceName;
        _backgroundServiceEnabled =
            (settingsMap['backgroundServiceEnabled'] ?? 0) == 1;
        _notificationsEnabled = (settingsMap['notificationEnabled'] ?? 1) == 1;
        _mergeRecordsEnabled = settings.enabled;
        _hideTimeOnlyRecords = (settingsMap['hideTimeOnlyRecords'] ?? 0) == 1;
        _hideUngroupableRecords = settings.hideUngroupableRecords;
        _groupBy = settings.groupBy;
        _timeWindow = settings.timeWindow;

        _rtlTcpHost = settingsMap['rtlTcpHost']?.toString() ?? '127.0.0.1';
        _rtlTcpPort = settingsMap['rtlTcpPort']?.toString() ?? '14423';
        _rtlTcpHostController.text = _rtlTcpHost;
        _rtlTcpPortController.text = _rtlTcpPort;

        final sourceStr = settingsMap['inputSource'] as String? ?? 'bluetooth';
        _inputSource = InputSource.values.firstWhere(
          (e) => e.name == sourceStr,
          orElse: () => InputSource.bluetooth,
        );

        _settingsLoaded = true;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_settingsLoaded) return;

    await _databaseService.updateSettings({
      'deviceName': _deviceName,
      'backgroundServiceEnabled': _backgroundServiceEnabled ? 1 : 0,
      'notificationEnabled': _notificationsEnabled ? 1 : 0,
      'mergeRecordsEnabled': _mergeRecordsEnabled ? 1 : 0,
      'hideTimeOnlyRecords': _hideTimeOnlyRecords ? 1 : 0,
      'hideUngroupableRecords': _hideUngroupableRecords ? 1 : 0,
      'groupBy': _groupBy.name,
      'timeWindow': _timeWindow.name,
      'inputSource': _inputSource.name,
      'rtlTcpHost': _rtlTcpHost,
      'rtlTcpPort': _rtlTcpPort,
    });
    widget.onSettingsChanged?.call();
  }

  Future<void> _switchInputSource(InputSource newSource) async {
    await AudioInputService().stopListening();
    await RtlTcpService().disconnect();
    setState(() {
      _inputSource = newSource;
    });

    switch (newSource) {
      case InputSource.audioInput:
        await AudioInputService().startListening();
        break;
      case InputSource.rtlTcp:
        await RtlTcpService().connect(host: _rtlTcpHost, port: _rtlTcpPort);
        break;
      case InputSource.bluetooth:
        break;
    }

    await _saveSettings();
  }

  Widget _buildInputSourceSettings() {
    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.input, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text('信号源设置', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('信号源', style: AppTheme.bodyLarge),
                DropdownButton<InputSource>(
                  value: _inputSource,
                  items: const [
                    DropdownMenuItem(
                      value: InputSource.bluetooth,
                      child: Text('蓝牙设备', style: AppTheme.bodyMedium),
                    ),
                    DropdownMenuItem(
                      value: InputSource.rtlTcp,
                      child: Text('RTL-TCP', style: AppTheme.bodyMedium),
                    ),
                    DropdownMenuItem(
                      value: InputSource.audioInput,
                      child: Text('音频输入', style: AppTheme.bodyMedium),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _switchInputSource(value);
                    }
                  },
                  dropdownColor: AppTheme.secondaryBlack,
                  style: AppTheme.bodyMedium,
                  underline: Container(height: 0),
                ),
              ],
            ),
            if (_inputSource == InputSource.bluetooth) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _deviceNameController,
                decoration: InputDecoration(
                  labelText: '蓝牙设备名称',
                  hintText: '输入设备名称',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white54),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white54),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) {
                  setState(() {
                    _deviceName = value;
                  });
                  _saveSettings();
                },
              ),
            ],
            if (_inputSource == InputSource.rtlTcp) ...[
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: '127.0.0.1',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white54),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white54),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                controller: _rtlTcpHostController,
                onChanged: (value) {
                  setState(() {
                    _rtlTcpHost = value;
                  });
                  _saveSettings();
                },
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: InputDecoration(
                  labelText: '服务器端口',
                  hintText: '14423',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white54),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white54),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                controller: _rtlTcpPortController,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  setState(() {
                    _rtlTcpPort = value;
                  });
                  _saveSettings();
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    RtlTcpService()
                        .connect(host: _rtlTcpHost, port: _rtlTcpPort);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text("重新连接 RTL-TCP"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondaryBlack,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              )
            ],
            if (_inputSource == InputSource.audioInput) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.mic, color: Colors.blue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '音频解调已启用。请通过音频线 (Line-in) 或麦克风输入信号。',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputSourceSettings(),
          if (_inputSource == InputSource.bluetooth) ...[
            const SizedBox(height: 20),
            _buildReceiverSdSettings(),
          ],
          const SizedBox(height: 20),
          _buildAppSettings(),
          const SizedBox(height: 20),
          _buildMergeSettings(),
          const SizedBox(height: 20),
          _buildDataManagement(),
          const SizedBox(height: 20),
          _buildAboutSection(),
        ],
      ),
    );
  }

  Widget _buildAppSettings() {
    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text('应用设置', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('后台保活服务', style: AppTheme.bodyLarge),
                  ],
                ),
                Switch(
                  value: _backgroundServiceEnabled,
                  onChanged: (value) async {
                    setState(() {
                      _backgroundServiceEnabled = value;
                    });
                    await _saveSettings();

                    if (value) {
                      await BackgroundService.startService();
                    } else {
                      await BackgroundService.stopService();
                    }
                  },
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('通知服务', style: AppTheme.bodyLarge),
                  ],
                ),
                Switch(
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _notificationsEnabled = value;
                    });
                    _saveSettings();
                  },
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('隐藏只有时间有效的记录', style: AppTheme.bodyLarge),
                  ],
                ),
                Switch(
                  value: _hideTimeOnlyRecords,
                  onChanged: (value) {
                    setState(() {
                      _hideTimeOnlyRecords = value;
                    });
                    _saveSettings();
                  },
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMergeSettings() {
    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.merge_type,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text('记录合并', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('启用记录合并', style: AppTheme.bodyLarge),
                  ],
                ),
                Switch(
                  value: _mergeRecordsEnabled,
                  onChanged: (value) {
                    setState(() {
                      _mergeRecordsEnabled = value;
                    });
                    _saveSettings();
                  },
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            Visibility(
              visible: _mergeRecordsEnabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('分组方式', style: AppTheme.bodyLarge),
                      DropdownButton<GroupBy>(
                        value: _groupBy,
                        items: const [
                          DropdownMenuItem(
                              value: GroupBy.trainOnly,
                              child: Text('仅车次号', style: AppTheme.bodyMedium)),
                          DropdownMenuItem(
                              value: GroupBy.locoOnly,
                              child: Text('仅机车号', style: AppTheme.bodyMedium)),
                          DropdownMenuItem(
                              value: GroupBy.trainOrLoco,
                              child:
                                  Text('车次号或机车号', style: AppTheme.bodyMedium)),
                          DropdownMenuItem(
                              value: GroupBy.trainAndLoco,
                              child:
                                  Text('车次号与机车号', style: AppTheme.bodyMedium)),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _groupBy = value;
                            });
                            _saveSettings();
                          }
                        },
                        dropdownColor: AppTheme.secondaryBlack,
                        style: AppTheme.bodyMedium,
                        underline: Container(height: 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('时间窗口', style: AppTheme.bodyLarge),
                      DropdownButton<TimeWindow>(
                        value: _timeWindow,
                        items: const [
                          DropdownMenuItem(
                              value: TimeWindow.oneHour,
                              child: Text('1小时内', style: AppTheme.bodyMedium)),
                          DropdownMenuItem(
                              value: TimeWindow.twoHours,
                              child: Text('2小时内', style: AppTheme.bodyMedium)),
                          DropdownMenuItem(
                              value: TimeWindow.sixHours,
                              child: Text('6小时内', style: AppTheme.bodyMedium)),
                          DropdownMenuItem(
                              value: TimeWindow.twelveHours,
                              child: Text('12小时内', style: AppTheme.bodyMedium)),
                          DropdownMenuItem(
                              value: TimeWindow.oneDay,
                              child: Text('24小时内', style: AppTheme.bodyMedium)),
                          DropdownMenuItem(
                              value: TimeWindow.unlimited,
                              child: Text('不限时间', style: AppTheme.bodyMedium)),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _timeWindow = value;
                            });
                            _saveSettings();
                          }
                        },
                        dropdownColor: AppTheme.secondaryBlack,
                        style: AppTheme.bodyMedium,
                        underline: Container(height: 0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('隐藏不可分组记录', style: AppTheme.bodyLarge),
                        ],
                      ),
                      Switch(
                        value: _hideUngroupableRecords,
                        onChanged: (value) {
                          setState(() {
                            _hideUngroupableRecords = value;
                          });
                          _saveSettings();
                        },
                        activeThumbColor: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _receiverRequestSdStatus() => BLEService().requestSdStatus();

  Future<bool> _receiverRequestSync() => BLEService().requestSync();

  Future<bool> _receiverClearSd() => BLEService().clearSdHistory();

  Widget _buildReceiverSdSettings() {
    final connected = _receiverLinkConnected;
    final present = _sdStatus?['present'] == true;
    final total = _sdStatus?['total_mb'];
    final used = _sdStatus?['used_mb'];
    final free = _sdStatus?['free_mb'];
    final pending = _sdStatus?['sync_pending'];

    String statusText;
    if (!connected) {
      statusText = '$_receiverLinkLabel以查询 SD 状态';
    } else if (_sdStatus == null) {
      statusText = '尚未收到 SD 状态，可点刷新';
    } else if (!present) {
      statusText = '未检测到 SD 卡（无卡时仅实时推送，不缓存离线数据）';
    } else {
      statusText =
          '已挂载 · 共 ${total ?? "-"} MB · 已用 ${used ?? "-"} MB · 剩余 ${free ?? "-"} MB · 待同步 ${pending ?? 0} 条';
    }

    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sd_card,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text('接收机 SD 卡', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(statusText,
                style: AppTheme.caption.copyWith(color: Colors.grey)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (!connected || _sdBusy)
                        ? null
                        : () async {
                            setState(() => _sdBusy = true);
                            await _receiverRequestSdStatus();
                            Future.delayed(const Duration(seconds: 3), () {
                              if (mounted && _sdBusy) {
                                setState(() => _sdBusy = false);
                              }
                            });
                          },
                    child: const Text('刷新状态'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: (!connected || _sdBusy)
                        ? null
                        : () async {
                            setState(() => _sdBusy = true);
                            await _receiverRequestSync();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已请求同步离线数据')),
                              );
                            }
                            Future.delayed(const Duration(seconds: 5), () {
                              if (mounted && _sdBusy) {
                                setState(() => _sdBusy = false);
                              }
                            });
                          },
                    child: const Text('同步离线数据'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              icon: Icons.delete_sweep,
              title: '清除接收机 SD 历史',
              subtitle: '删除接收机上的同步队列/日志/CSV，不影响手机 App 内记录',
              onTap: _clearReceiverSdHistory,
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearReceiverSdHistory() async {
    if (!_receiverLinkConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_receiverLinkLabel)),
      );
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除接收机 SD 历史'),
        content: const Text(
            '将清除接收机 SD 上的同步队列、LOG 与 CSV 历史。手机 App 内已保存的列车记录不会受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;

    setState(() => _sdBusy = true);
    final ok = await _receiverClearSd();
    if (!mounted) return;
    if (!ok) {
      setState(() => _sdBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下发失败')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已请求清除接收机 SD 历史')),
    );
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _sdBusy) setState(() => _sdBusy = false);
    });
  }

  Widget _buildDataManagement() {
    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text('数据管理', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            _buildActionButton(
              icon: Icons.share,
              title: '分享数据',
              subtitle: '将记录分享为 JSON 文件',
              onTap: _shareData,
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              icon: Icons.file_download,
              title: '导入数据',
              subtitle: '从 JSON 文件导入记录和设置',
              onTap: _importData,
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              icon: Icons.delete_outline,
              title: '清空 App 列车记录',
              subtitle: '仅删除手机内列车记录，不影响设置与接收机 SD',
              onTap: _clearAppRecords,
              isDestructive: true,
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              icon: Icons.settings_backup_restore,
              title: '重置 App 设置',
              subtitle: '恢复默认设置，保留列车记录',
              onTap: _resetAppSettings,
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: isDestructive
              ? Colors.red.withValues(alpha: 0.1)
              : AppTheme.secondaryBlack,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: isDestructive
                ? Colors.red.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive
                  ? Colors.red
                  : Theme.of(context).colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.bodyLarge.copyWith(
                      color: isDestructive ? Colors.red : Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.white54,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return 'v${packageInfo.version}';
    } catch (e) {
      return '';
    }
  }

  void _handleAboutIconTap() {
    _aboutIconTapTimer?.cancel();
    _aboutIconTapTimer = Timer(const Duration(seconds: 2), () {
      _aboutIconTapCount = 0;
    });

    _aboutIconTapCount += 1;
    if (_aboutIconTapCount < 5) return;

    _aboutIconTapCount = 0;
    _aboutIconTapTimer?.cancel();
    _showTemporaryRecordsPanel();
  }

  void _showTemporaryRecordsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      builder: (context) {
        bool enabled = widget.temporaryRecordsEnabled;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.science,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        const Text('临时测试', style: AppTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      value: enabled,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('生成临时列车记录'),
                      subtitle: const Text('每 5 秒新增一条真实记录，包含随机移动坐标'),
                      onChanged: (value) {
                        setSheetState(() {
                          enabled = value;
                        });
                        widget.onTemporaryRecordsChanged?.call(value);
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _shareData() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在准备分享数据...'),
            ],
          ),
        ),
      );

      try {
        final exportedPath = await _databaseService.exportDataAsJson();
        if (!mounted) return;
        Navigator.pop(context);

        if (exportedPath != null) {
          final file = File(exportedPath);

          await Share.shareXFiles(
            [XFile(file.path)],
            subject: 'LBJ Console Data',
            text: '',
          );
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('分享失败：无法生成数据文件'),
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('分享错误：$e'),
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('分享错误：$e'),
        ),
      );
    }
  }

  Future<void> _importData() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入数据'),
        content: const Text('导入将替换所有现有数据，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );

    if (result != true) return;

    final resultFile = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (resultFile == null) return;
    final selectedFile = resultFile.files.single.path;
    if (selectedFile == null) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在导入数据...'),
          ],
        ),
      ),
    );

    try {
      final success = await _databaseService.importDataFromJson(selectedFile);
      if (!mounted) return;
      Navigator.pop(context);

      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('数据导入成功'),
          ),
        );

        await _loadSettings();
        setState(() {});
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('数据导入失败'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('导入错误：$e'),
        ),
      );
    }
  }

  Future<void> _clearAppRecords() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空 App 列车记录'),
        content: const Text('仅删除手机内列车记录，不会修改设置，也不会清除接收机 SD。是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (result != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在清空记录...'),
          ],
        ),
      ),
    );

    try {
      await _databaseService.deleteAllRecords();
      if (!mounted) return;
      Navigator.pop(context);
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('App 列车记录已清空')),
      );
      widget.onSettingsChanged?.call();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('清空错误：$e')),
      );
    }
  }

  Future<void> _resetAppSettings() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置 App 设置'),
        content: const Text('将恢复默认设置，保留列车记录。是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认重置'),
          ),
        ],
      ),
    );

    if (result != true) return;
    if (!mounted) return;

    try {
      await _databaseService.updateSettings({
        'deviceName': 'LBJReceiver',
        'backgroundServiceEnabled': 0,
        'notificationEnabled': 1,
        'mergeRecordsEnabled': 0,
        'groupBy': 'trainAndLoco',
        'timeWindow': 'unlimited',
        'inputSource': 'bluetooth',
        'hideTimeOnlyRecords': 0,
        'hideUngroupableRecords': 0,
      });

      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('App 设置已重置')),
      );
      await _loadSettings();
      widget.onSettingsChanged?.call();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('重置错误：$e')),
      );
    }
  }

  Widget _buildAboutSection() {
    return Card(
      color: AppTheme.tertiaryBlack,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleAboutIconTap,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(Icons.info,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('关于', style: AppTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            const Text('LBJ Console', style: AppTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<String>(
              future: _getAppVersion(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Text(snapshot.data!, style: AppTheme.bodyMedium);
                } else {
                  return const Text('v0.1.3-flutter',
                      style: AppTheme.bodyMedium);
                }
              },
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                final url = Uri.parse('https://github.com/undef-i/LBJConsole');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                }
              },
              child: const Text(
                'https://github.com/undef-i/LBJConsole',
                style: AppTheme.caption,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
