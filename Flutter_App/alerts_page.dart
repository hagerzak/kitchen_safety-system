// alerts_page.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_theme.dart';
import 'app_models.dart';

/// Combined Alerts page:
/// - Uses UI from AlertsSettingsScreen (cards, shapes, dynamic buttons)
/// - Integrates Supabase logic for user_alerts
/// - Integrates MQTT connection and matches ESP32 topics & thresholds
/// - No Provider usage. Uses app_theme & app_models.

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  // Supabase client
  final _supa = Supabase.instance.client;

  // MQTT client
  late final MqttServerClient _mqtt;
  bool _mqttConnected = false;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _mqttSubscription;

  // Local state
  Map<String, String> sensorValues = {
    'temp': '--',
    'humidity': '--',
    'gas': '--',
    'flame': '--',
  };

  String lastAlert = 'All Safe';
  MaterialColor bannerColor = Colors.green;

  // Alert settings loaded from Supabase (or default)
  List<AlertSettings> alertSettings = [];

  Map<String, String> lastSentMessage = {};

  // Local UI controllers for thresholds
  final Map<SensorType, TextEditingController> _thresholdControllers = {};

  // Which alert methods user selected (from DB) per sensor string key
  Map<String, String?> selectedMethods = {
    'gas': null,
    'flame': null,
    'temperature': null,
    'humidity': null,
  };

  // enabled flags for UI switches (defaults true)
  Map<String, bool> alertsEnabled = {
    'gas': true,
    'flame': true,
    'temperature': true,
    'humidity': true,
  };

  // Audio & notifications
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Threshold defaults (match ESP32 code you posted)
  final Map<String, double> thresholds = {
    // ESP thresholds used:
    // gas > 2000 -> danger
    // flame < 2500 -> danger
    // temp > 40 -> danger
    'gas': 2000.0,
    'flame': 2500.0, // for flame we treat "below this" as danger
    'temp': 40.0,
    'humidity': 80.0, // keep a safe default
  };

  // MQTT credentials (kept from your earlier flutter logic)
  static const String _mqttServer =
      '436aa7eaa3cb4577bd3567b46af719b1.s1.eu.hivemq.cloud';
  static const int _mqttPort = 8883;
  static const String _mqttUser = 'hivemq.webclient.1756106226262';
  static const String _mqttPass = 'sC6QPKpD3*cuI%@l81;y';

  @override
  void initState() {
    super.initState();

    // initialize threshold controllers for all SensorType values
    for (final t in SensorType.values) {
      _thresholdControllers[t] = TextEditingController();
    }

    _initNotifications();
    _initMqtt();
    _fetchAlertSettingsFromSupabase();
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    for (var c in _thresholdControllers.values) {
      c.dispose();
    }
    _mqtt.disconnect();
    _audioPlayer.dispose();
    super.dispose();
  }

  // -------------------------
  // Supabase: load/save alert settings
  // -------------------------
  Future<void> _fetchAlertSettingsFromSupabase() async {
    final user = _supa.auth.currentUser;

    if (user == null) {
      // not logged in => keep defaults
      _loadDefaultsToControllers();
      return;
    }

    try {
      final res = await _supa
          .from('user_alerts')
          .select()
          .eq('user_id', user.id)
          .order('sensor_type');

      // res likely a List<Map<String, dynamic>>
      final List<AlertSettings> loaded = [];

      for (var item in res) {
        final sensorTypeStr = (item['sensor_type'] as String?) ?? '';
        final alertType = (item['alert_type'] as String?) ?? '';
        final threshold = (item['threshold'] as String?) ?? '';
        final sensorType = _stringToSensorType(sensorTypeStr);

        if (sensorType != null) {
          loaded.add(AlertSettings(
              sensorType: sensorType,
              enabled: true,
              threshold: threshold.isEmpty
                  ? _defaultThresholdFor(sensorType)
                  : threshold));

          // reflect method selection in UI map
          selectedMethods[sensorTypeStr] = alertType.isEmpty ? null : alertType;
          alertsEnabled[sensorTypeStr] = true;
        }
      }

      if (mounted) {
        // Add this check
        setState(() {
          alertSettings = loaded;
        });
      }
      for (var s in alertSettings) {
        if (mounted) {
          // Optional: add if controller updates trigger rebuild
          _thresholdControllers[s.sensorType]?.text = s.threshold;
        }
      }
    } catch (e) {
      // fallback: keep defaults in UI
      _loadDefaultsToControllers();
    }
  }

  Future<void> _saveOrUpdateAlertInSupabase(
      SensorType sensorType, bool enabled, String threshold,
      {String? method}) async {
    final user = _supa.auth.currentUser;

    if (user == null) return;

    final sensorStr = _sensorTypeToString(sensorType);

    try {
      // upsert row in user_alerts with fields: user_id, sensor_type, alert_type, threshold
      await _supa.from('user_alerts').upsert({
        'user_id': user.id,
        'sensor_type': sensorStr,
        'alert_type': method ?? selectedMethods[sensorStr],
        'threshold': threshold,
      });
    } catch (e) {
      // ignore for now
    }
  }

  // -------------------------
  // Notifications & audio
  // -------------------------
  Future<void> _initNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'alert_channel',
      'Kitchen Alerts',
      importance: Importance.max,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(0, title, body, details);
  }

  Future<void> _playSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/alert.mp3'));
    } catch (e) {
      // ignore if asset missing
    }
  }

  // -------------------------
  // MQTT: connect, subscribe, parse sensor JSON (sensors/data)
  // -------------------------
  Future<void> _initMqtt() async {
    _mqtt = MqttServerClient(_mqttServer,
        'flutter_alerts_client_${DateTime.now().millisecondsSinceEpoch}');

    _mqtt.port = _mqttPort;
    _mqtt.secure = true;
    _mqtt.logging(on: false);
    _mqtt.keepAlivePeriod = 20;
    _mqtt.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_alerts_client_${DateTime.now().millisecondsSinceEpoch}')
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    _mqtt.onConnected = () {
      if (mounted) {
        setState(() => _mqttConnected = true);
      }

      // subscribe to ESP32 topics: sensors/data (JSON), and confirm topics
      _mqtt.subscribe('sensors/data', MqttQos.atMostOnce);
      _mqtt.subscribe('led', MqttQos.atMostOnce);
      _mqtt.subscribe('servo', MqttQos.atMostOnce);
      _mqtt.subscribe('buzzer', MqttQos.atMostOnce);
    };

    _mqtt.onDisconnected = () {
      if (mounted) {
        setState(() => _mqttConnected = false);
      }
    };

    _mqttSubscription =
        _mqtt.updates?.listen((List<MqttReceivedMessage<MqttMessage>> events) {
      final recMess = events[0].payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      final topic = events[0].topic;

      // parse messages
      _handleMqttMessage(topic, payload);
    });

    try {
      await _mqtt.connect(_mqttUser, _mqttPass);
    } catch (e) {
      debugPrint('MQTT connect failed: $e');
      _mqtt.disconnect();
    }
  }

  void _handleMqttMessage(String topic, String payload) {
    if (topic == 'sensors/data') {
      try {
        final Map<String, dynamic> map = json.decode(payload);
        if (mounted) {
          // Add this check
          setState(() {
            if (map.containsKey('temp'))
              sensorValues['temp'] = map['temp'].toString();
            if (map.containsKey('hum'))
              sensorValues['humidity'] = map['hum'].toString();
            if (map.containsKey('gas'))
              sensorValues['gas'] = map['gas'].toString();
            if (map.containsKey('flame'))
              sensorValues['flame'] = map['flame'].toString();
            if (map.containsKey('status')) {
              lastAlert = map['status'].toString();
              bannerColor = lastAlert.toLowerCase().contains('danger')
                  ? Colors.red
                  : Colors.green;
            }
          });
          _evaluateThresholdsAndAct();
        }
      } catch (e) {
        debugPrint('Failed to decode sensors/data: $e');
      }
      return;
    }
    if (topic == 'led' || topic == 'servo' || topic == 'buzzer') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device: ($topic) -> $payload')),
        );
      }
      return;
    }
  }

  // Publish to control topics: led, servo, buzzer
  void _publishControl(String topic, String message) async {
    if (_mqtt.connectionStatus?.state != MqttConnectionState.connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MQTT not connected')),
        );
      }
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    try {
      // publish message with QoS 1 (guaranteed delivery)
      _mqtt.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);

      // بعد التأكد من إرسال الرسالة (QoS 1 يضمن التسليم لل broker)
      if (mounted) {
        setState(() {
          lastSentMessage[topic] = message; // خزن آخر رسالة اتبعت
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message sent to $topic: $message')),
        );
      }
    } catch (e) {
      debugPrint('Failed to publish $topic: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send $topic')),
        );
      }
    }
  }

  // Evaluate thresholds using thresholds map and sensorValues
  void _evaluateThresholdsAndAct() {
    bool isDanger = false;

    // gas: danger if numeric > thresholds['gas']
    final gasStr = sensorValues['gas'] ?? '--';
    final flameStr = sensorValues['flame'] ?? '--';
    final tempStr = sensorValues['temp'] ?? '--';
    final humStr = sensorValues['humidity'] ?? '--';

    final gasVal = double.tryParse(gasStr) ?? double.nan;
    final flameVal = double.tryParse(flameStr) ?? double.nan;
    final tempVal = double.tryParse(tempStr) ?? double.nan;
    final humVal = double.tryParse(humStr) ?? double.nan;

    if (!gasVal.isNaN && gasVal > (thresholds['gas'] ?? 2000.0))
      isDanger = true;
    if (!flameVal.isNaN && flameVal < (thresholds['flame'] ?? 2500.0))
      isDanger = true;
    if (!tempVal.isNaN && tempVal > (thresholds['temp'] ?? 40.0))
      isDanger = true;
    if (!humVal.isNaN && humVal > (thresholds['humidity'] ?? 80.0))
      isDanger = true;

    // publish LED and buzzer states
    final builder = MqttClientPayloadBuilder();
    builder.addString(isDanger ? '1' : '0');

    if (_mqtt.connectionStatus?.state == MqttConnectionState.connected) {
      _mqtt.publishMessage('led', MqttQos.atMostOnce, builder.payload!);
      _mqtt.publishMessage('buzzer', MqttQos.atMostOnce, builder.payload!);
    }

    if (isDanger) {
      // play sound + show notification if user has selected method Notification/Sound
      final methods = selectedMethods.values.where((m) => m != null).toList();

      if (methods.contains('Sound')) _playSound();

      if (methods.contains('Notification')) {
        // figure which sensor triggered (priority gas -> flame -> temp -> hum)
        String triggered = 'unknown';
        if (!gasVal.isNaN && gasVal > (thresholds['gas'] ?? 2000.0))
          triggered = 'Gas';
        else if (!flameVal.isNaN && flameVal < (thresholds['flame'] ?? 2500.0))
          triggered = 'Flame';
        else if (!tempVal.isNaN && tempVal > (thresholds['temp'] ?? 40.0))
          triggered = 'Temp';
        else if (!humVal.isNaN && humVal > (thresholds['humidity'] ?? 80.0))
          triggered = 'Humidity';

        _showNotification('Kitchen Alert', '$triggered threshold exceeded');
      }
    }

    if (mounted) {
      // Add this check
      setState(() {
        lastAlert = isDanger ? 'Danger' : 'Normal';
        bannerColor = isDanger ? Colors.red : Colors.green;
      });
    }
  }

  // -------------------------
  // Helpers
  // -------------------------
  String _sensorTypeToString(SensorType t) {
    switch (t) {
      case SensorType.gas:
        return 'gas';
      case SensorType.flame:
        return 'flame';
      case SensorType.temperature:
        return 'temperature';
      case SensorType.humidity:
        return 'humidity';
    }
  }

  SensorType? _stringToSensorType(String s) {
    switch (s.toLowerCase()) {
      case 'gas':
        return SensorType.gas;
      case 'flame':
        return SensorType.flame;
      case 'temperature':
      case 'temp':
        return SensorType.temperature;
      case 'humidity':
        return SensorType.humidity;
      default:
        return null;
    }
  }

  String _defaultThresholdFor(SensorType t) {
    final key = _sensorTypeToString(t);
    final v = thresholds[key] ?? 0.0;
    return v.toString();
  }

  void _loadDefaultsToControllers() {
    for (var t in SensorType.values) {
      _thresholdControllers[t]?.text = _defaultThresholdFor(t);
    }
  }

  // -------------------------
  // UI Building (kept 1:1 look & cards)
  // -------------------------
  Widget _buildGlobalSettingsCard(BuildContext context) {
    return Card(
      color: AppColors.burgundy50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Icon(Icons.settings, color: AppColors.burgundy700),
              const SizedBox(width: 8),
              Text(
                'Global Alert Settings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.burgundy700,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Alert Methods:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.burgundy700,
                ),
          ),
          const SizedBox(height: 8),
          _buildAlertMethodTile(
            'Push Notifications',
            'Receive instant alerts on your device',
            Icons.notifications,
            true,
            true,
            (v) {},
          ),
          const SizedBox(height: 16),
          Text(
            'Alert Timing:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.burgundy700,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.burgundy200)),
            child: Row(
              children: [
                Icon(Icons.access_time, color: AppColors.burgundy600),
                const SizedBox(width: 8),
                Text('Instant alerts (real-time monitoring)',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.burgundy700)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildAlertMethodTile(String title, String subtitle, IconData icon,
      bool value, bool isEnabled, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: value ? AppColors.burgundy700 : AppColors.burgundy200),
      ),
      child: Row(children: [
        Icon(icon, color: value ? AppColors.burgundy700 : AppColors.mediumGrey),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: value ? AppColors.burgundy700 : AppColors.mediumGrey,
                  )),
          Text(subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mediumGrey,
                  )),
        ])),
        Switch(
            value: value,
            onChanged: isEnabled ? onChanged : null,
            activeColor: AppColors.burgundy700)
      ]),
    );
  }

  Widget _buildSensorAlertCard(
      BuildContext context, AlertSettings setting, bool isConnected) {
    final sensorColor = _getSensorColor(setting.sensorType);
    final sensorIcon = _getSensorIcon(setting.sensorType);
    final sensorName = _getSensorName(setting.sensorType);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: sensorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(sensorIcon, color: sensorColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(sensorName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.darkGrey,
                          )),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: isConnected
                              ? AppColors.success
                              : AppColors.mediumGrey,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(isConnected ? 'Connected' : 'Not Connected',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white, fontSize: 10)),
                    )
                  ])
                ])),
            // switch: enabled/disabled for this setting
            Switch(
              value: setting.enabled,
              onChanged: (value) async {
                // update local model and save to supabase
                final idx = alertSettings
                    .indexWhere((s) => s.sensorType == setting.sensorType);

                if (idx >= 0) {
                  setState(() {
                    alertSettings[idx] = setting.copyWith(enabled: value);
                  });
                } else {
                  setState(() {
                    alertSettings.add(setting.copyWith(enabled: value));
                  });
                }

                // Save into Supabase (threshold from controller)
                final threshold =
                    _thresholdControllers[setting.sensorType]?.text ??
                        _defaultThresholdFor(setting.sensorType);

                await _saveOrUpdateAlertInSupabase(
                    setting.sensorType, value, threshold,
                    method: selectedMethods[
                        _sensorTypeToString(setting.sensorType)]);
              },
              activeColor: AppColors.burgundy700,
            )
          ]),
          const SizedBox(height: 16),
          if (setting.enabled) ...[
            Text('Alert Threshold:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    )),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _thresholdControllers[setting.sensorType],
                  decoration: InputDecoration(
                    hintText: _getThresholdHint(setting.sensorType),
                    suffixText: _getThresholdUnit(setting.sensorType),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  enabled: isConnected,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: isConnected
                    ? () {
                        _updateThreshold(setting);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16)),
                child: const Text('Update'),
              )
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.burgundy50,
                  borderRadius: BorderRadius.circular(6)),
              child: Text(_getThresholdDescription(setting.sensorType),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.burgundy600,
                      )),
            )
          ] else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.mediumGrey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.notifications_off,
                    color: AppColors.mediumGrey, size: 16),
                const SizedBox(width: 8),
                Text('Alerts disabled for this sensor',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mediumGrey,
                          fontStyle: FontStyle.italic,
                        )),
              ]),
            )
        ]),
      ),
    );
  }

  Widget _buildNoSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(children: [
          Icon(Icons.notifications_none, size: 48, color: AppColors.mediumGrey),
          const SizedBox(height: 16),
          Text('No Alert Settings Available',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.mediumGrey,
                    fontWeight: FontWeight.bold,
                  )),
          const SizedBox(height: 8),
          Text('Add sensors to configure alert settings.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mediumGrey,
                  ),
              textAlign: TextAlign.center)
        ]),
      ),
    );
  }

  Widget _buildAlertHistoryCard() {
    // Demo static history (kept from UI)
    return Card(
      color: AppColors.burgundy50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.history, color: AppColors.burgundy700),
            const SizedBox(width: 8),
            Text('Recent Alert Activity',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.burgundy700,
                      fontWeight: FontWeight.bold,
                    )),
          ]),
          const SizedBox(height: 12),
          _buildAlertHistoryItem('Gas Sensor', 'Normal levels restored',
              '2 minutes ago', AppColors.success, Icons.check_circle),
          _buildAlertHistoryItem(
              'Temperature Sensor',
              'High temperature detected',
              '15 minutes ago',
              AppColors.warning,
              Icons.warning),
          _buildAlertHistoryItem('Flame Sensor', 'System check completed',
              '1 hour ago', AppColors.success, Icons.check_circle),
        ]),
      ),
    );
  }

  Widget _buildAlertHistoryItem(
      String sensor, String message, String time, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$sensor: $message',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.burgundy700)),
          Text(time,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.mediumGrey, fontSize: 10))
        ]))
      ]),
    );
  }

  // -------------------------
  // UI: main build (keeps the original structure)
  // -------------------------
  @override
  Widget build(BuildContext context) {
    // If we didn't load any settings from DB, create defaults for UI display
    if (alertSettings.isEmpty) {
      alertSettings = SensorType.values.map((t) {
        return AlertSettings(
            sensorType: t, enabled: true, threshold: _defaultThresholdFor(t));
      }).toList();

      // populate controllers once
      for (var s in alertSettings) {
        _thresholdControllers[s.sensorType]?.text = s.threshold;
      }
    }

    // connectedSensors: infer from whether sensors have values (simple heuristic)
    final connectedSensors = <SensorType>[];
    sensorValues.forEach((key, value) {
      final st = _stringToSensorType(key == 'humidity' ? 'humidity' : key);
      if (st != null) connectedSensors.add(st);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert Settings'),
        actions: [
          TextButton(
            onPressed: () {
              // Save all local settings to Supabase
              for (var setting in alertSettings) {
                final thr = _thresholdControllers[setting.sensorType]?.text ??
                    setting.threshold;

                _saveOrUpdateAlertInSupabase(
                    setting.sensorType, setting.enabled, thr,
                    method: selectedMethods[
                        _sensorTypeToString(setting.sensorType)]);
              }

              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('All alert settings saved successfully'),
                backgroundColor: AppColors.success,
              ));
            },
            child: const Text('Save All',
                style: TextStyle(color: AppColors.cream)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Live status banner (from logic)
          Card(
            color: bannerColor.shade50,
            margin: const EdgeInsets.only(bottom: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Icon(
                    lastAlert.toLowerCase().contains('danger')
                        ? Icons.warning
                        : Icons.check_circle,
                    color: bannerColor,
                    size: 56),
                const SizedBox(height: 12),
                Text(
                  lastAlert.toLowerCase().contains('danger')
                      ? 'Danger Detected!'
                      : 'Kitchen is Safe',
                  style: TextStyle(
                      color: bannerColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Temp: ${sensorValues['temp']}  •  Humidity: ${sensorValues['humidity']}  •  Gas: ${sensorValues['gas']}  •  Flame: ${sensorValues['flame']}',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                )
              ]),
            ),
          ),

          // Global settings card
          _buildGlobalSettingsCard(context),

          const SizedBox(height: 16),

          // Sensor-specific cards (kept layout)
          Text('Sensor Alert Settings',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.burgundy700,
                    fontWeight: FontWeight.bold,
                  )),

          const SizedBox(height: 12),

          // For each alert setting show the card (preserve ordering)
          ...alertSettings.map((setting) {
            final isConnected = connectedSensors.contains(setting.sensorType);

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildSensorAlertCard(context, setting, isConnected),
            );
          }).toList(),

          const SizedBox(height: 16),

          _buildAlertHistoryCard(),

          const SizedBox(height: 16),

          // Controls for direct device actions (only servo as requested)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Manual Controls',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      ElevatedButton(
                          onPressed: () {
                            // open servo -> per ESP expects numeric angle, set to 90 for open
                            _publishControl('servo', '90');
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.burgundy700),
                          child: const Text('Open Servo')),
                      ElevatedButton(
                          onPressed: () {
                            _publishControl('servo', '0');
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.burgundy700),
                          child: const Text('Close Servo')),
                    ]),
                  ]),
            ),
          ),

          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  // -------------------------
  // Small helper UI update functions
  // -------------------------
  void _updateThreshold(AlertSettings setting) {
    final controller = _thresholdControllers[setting.sensorType];

    if (controller != null && controller.text.isNotEmpty) {
      final idx =
          alertSettings.indexWhere((s) => s.sensorType == setting.sensorType);

      if (idx >= 0) {
        setState(() {
          alertSettings[idx] =
              alertSettings[idx].copyWith(threshold: controller.text);
        });
      } else {
        setState(() {
          alertSettings.add(setting.copyWith(threshold: controller.text));
        });
      }

      // Save to Supabase
      _saveOrUpdateAlertInSupabase(
          setting.sensorType, setting.enabled, controller.text,
          method: selectedMethods[_sensorTypeToString(setting.sensorType)]);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('${_getSensorName(setting.sensorType)} threshold updated'),
        backgroundColor: AppColors.success,
      ));
    }
  }

  // UI helpers mapping sensortype -> color/icon/name/hints (copied from your UI)
  Color _getSensorColor(SensorType type) {
    switch (type) {
      case SensorType.gas:
        return AppColors.danger;
      case SensorType.flame:
        return AppColors.warning;
      case SensorType.temperature:
        return AppColors.burgundy700;
      case SensorType.humidity:
        return AppColors.burgundy600;
    }
  }

  IconData _getSensorIcon(SensorType type) {
    switch (type) {
      case SensorType.gas:
        return Icons.gas_meter;
      case SensorType.flame:
        return Icons.local_fire_department;
      case SensorType.temperature:
        return Icons.thermostat;
      case SensorType.humidity:
        return Icons.water_drop;
    }
  }

  String _getSensorName(SensorType type) {
    switch (type) {
      case SensorType.gas:
        return 'Gas Sensor';
      case SensorType.flame:
        return 'Flame Sensor';
      case SensorType.temperature:
        return 'Temperature Sensor';
      case SensorType.humidity:
        return 'Humidity Sensor';
    }
  }

  String _getThresholdHint(SensorType type) {
    switch (type) {
      case SensorType.gas:
        return 'Enter gas concentration limit';
      case SensorType.flame:
        return 'Flame triggers immediately if below threshold';
      case SensorType.temperature:
        return 'Enter temperature limit';
      case SensorType.humidity:
        return 'Enter humidity limit';
    }
  }

  String _getThresholdUnit(SensorType type) {
    switch (type) {
      case SensorType.gas:
        return 'raw';
      case SensorType.flame:
        return '';
      case SensorType.temperature:
        return '°C';
      case SensorType.humidity:
        return '%';
    }
  }

  String _getThresholdDescription(SensorType type) {
    switch (type) {
      case SensorType.gas:
        return 'Alert triggers when gas analog value exceeds this raw value. (ESP default: 2000)';
      case SensorType.flame:
        return 'Alert triggers when flame analog value falls below this raw value. (ESP default: 2500)';
      case SensorType.temperature:
        return 'Alert triggers when temperature exceeds this value. (ESP default: 40°C)';
      case SensorType.humidity:
        return 'Alert triggers when humidity exceeds this value.';
    }
  }
}
