// sensor_logs_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:intl/intl.dart';

import 'app_theme.dart';

/// Sensor logs page to display real-time and historical sensor data from Supabase and MQTT
class SensorLogsScreen extends StatefulWidget {
  const SensorLogsScreen({super.key});

  @override
  State<SensorLogsScreen> createState() => _SensorLogsScreenState();
}

class _SensorLogsScreenState extends State<SensorLogsScreen> {
  // Supabase client
  final _supa = Supabase.instance.client;

  // MQTT client
  late final MqttServerClient _mqtt;
  bool _mqttConnected = false;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _mqttSubscription;

  // Supabase real-time subscription
  RealtimeChannel? _realtimeChannel;

  // Local state for sensor data
  List<Map<String, dynamic>> sensorData = []; // Historical data from Supabase
  Map<String, String> latestSensorValues = {
    'temp': '--',
    'humidity': '--',
    'gas': '--',
    'flame': '--',
    'led': '--',
    'buzzer': '--',
    'servo': '--',
    'status': 'All Safe',
  };
  MaterialColor bannerColor = Colors.green;

  // MQTT credentials
  static const String _mqttServer =
      '436aa7eaa3cb4577bd3567b46af719b1.s1.eu.hivemq.cloud';
  static const int _mqttPort = 8883;
  static const String _mqttUser = 'hivemq.webclient.1756106226262';
  static const String _mqttPass = 'sC6QPKpD3*cuI%@l81;y';

  @override
  void initState() {
    super.initState();
    _initMqtt();
    _fetchSensorDataFromSupabase();
    _subscribeToRealtimeSupabase();
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    _realtimeChannel?.unsubscribe();
    _mqtt.disconnect();
    super.dispose();
  }

  // -------------------------
  // Supabase: Fetch all sensor data and subscribe to real-time updates
  // -------------------------
  Future<void> _fetchSensorDataFromSupabase() async {
    final user = _supa.auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to view sensor data'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }

    try {
      final res = await _supa
          .from('sensors')
          .select()
          .order('created_at', ascending: false); // Fetch all rows

      if (mounted) {
        setState(() {
          sensorData = List<Map<String, dynamic>>.from(res);

          // 3) تحديث آخر القيم إذا في بيانات
          if (sensorData.isNotEmpty) {
            final latest = sensorData.first;
            latestSensorValues['temp'] = latest['temp']?.toString() ?? '--';
            latestSensorValues['humidity'] = latest['hum']?.toString() ?? '--';
            latestSensorValues['gas'] = latest['gas']?.toString() ?? '--';
            latestSensorValues['flame'] = latest['flame']?.toString() ?? '--';
            latestSensorValues['led'] = latest['led']?.toString() ?? '--';
            latestSensorValues['buzzer'] = latest['buzzer']?.toString() ?? '--';
            latestSensorValues['servo'] = latest['servo']?.toString() ?? '--';
            latestSensorValues['status'] =
                latest['status']?.toString() ?? 'All Safe';
            bannerColor =
                latestSensorValues['status']!.toLowerCase().contains('danger')
                    ? Colors.red
                    : Colors.green;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching sensor data: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _subscribeToRealtimeSupabase() {
    final user = _supa.auth.currentUser;
    if (user == null) return;

    _realtimeChannel = _supa
        .channel('sensors_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sensors',
          callback: (payload) {
            if (mounted) {
              setState(() {
                final newRecord = payload.newRecord;
                sensorData.insert(0, newRecord); // Add new row at the top
                // Update latest values
                latestSensorValues['temp'] =
                    newRecord['temp']?.toString() ?? '--';
                latestSensorValues['humidity'] =
                    newRecord['hum']?.toString() ?? '--';
                latestSensorValues['gas'] =
                    newRecord['gas']?.toString() ?? '--';
                latestSensorValues['flame'] =
                    newRecord['flame']?.toString() ?? '--';
                latestSensorValues['led'] =
                    newRecord['led']?.toString() ?? '--';
                latestSensorValues['buzzer'] =
                    newRecord['buzzer']?.toString() ?? '--';
                latestSensorValues['servo'] =
                    newRecord['servo']?.toString() ?? '--';
                latestSensorValues['status'] =
                    newRecord['status']?.toString() ?? 'All Safe';
                bannerColor = latestSensorValues['status']!
                        .toLowerCase()
                        .contains('danger')
                    ? Colors.red
                    : Colors.green;
              });
            }
          },
        )
        .subscribe();
  }

  // -------------------------
  // MQTT: Connect, subscribe, parse JSON
  // -------------------------
  Future<void> _initMqtt() async {
    _mqtt = MqttServerClient(_mqttServer,
        'flutter_sensors_client_${DateTime.now().millisecondsSinceEpoch}');
    _mqtt.port = _mqttPort;
    _mqtt.secure = true;
    _mqtt.logging(on: false);
    _mqtt.keepAlivePeriod = 20;
    _mqtt.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_sensors_client_${DateTime.now().millisecondsSinceEpoch}')
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    _mqtt.onConnected = () {
      if (mounted) {
        setState(() => _mqttConnected = true);
      }
      // Subscribe to topics
      _mqtt.subscribe('sensors/data', MqttQos.atMostOnce);
      _mqtt.subscribe('led', MqttQos.atMostOnce);
      _mqtt.subscribe('buzzer', MqttQos.atMostOnce);
      _mqtt.subscribe('servo', MqttQos.atMostOnce);
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
      _handleMqttMessage(topic, payload);
    });

    try {
      await _mqtt.connect(_mqttUser, _mqttPass);
    } catch (e) {
      debugPrint('MQTT connect failed: $e');
      _mqtt.disconnect();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('MQTT connection failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _handleMqttMessage(String topic, String payload) {
    if (topic == 'sensors/data') {
      try {
        final Map<String, dynamic> map = json.decode(payload);
        if (mounted) {
          setState(() {
            if (map.containsKey('temp'))
              latestSensorValues['temp'] = map['temp'].toString();
            if (map.containsKey('hum'))
              latestSensorValues['humidity'] = map['hum'].toString();
            if (map.containsKey('gas'))
              latestSensorValues['gas'] = map['gas'].toString();
            if (map.containsKey('flame'))
              latestSensorValues['flame'] = map['flame'].toString();
            if (map.containsKey('status')) {
              latestSensorValues['status'] = map['status'].toString();
              bannerColor = map['status'].toLowerCase().contains('danger')
                  ? Colors.red
                  : Colors.green;
            }
          });
        }
      } catch (e) {
        debugPrint('Failed to decode sensors/data: $e');
      }
    } else if (topic == 'led' || topic == 'buzzer' || topic == 'servo') {
      if (mounted) {
        setState(() {
          latestSensorValues[topic] = payload;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device: ($topic) -> $payload')),
        );
      }
    }
  }

  // Publish to servo topic
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
      _mqtt.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      if (mounted) {
        setState(() {
          latestSensorValues[topic] = message;
        });
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

  // -------------------------
  // UI Building
  // -------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor Logs'),
        backgroundColor: AppColors.burgundy700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live status banner
            Card(
              color: bannerColor.shade50,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      latestSensorValues['status']!
                              .toLowerCase()
                              .contains('danger')
                          ? Icons.warning
                          : Icons.check_circle,
                      color: bannerColor,
                      size: 56,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      latestSensorValues['status']!
                              .toLowerCase()
                              .contains('danger')
                          ? 'Danger Detected!'
                          : 'Kitchen is Safe',
                      style: TextStyle(
                        color: bannerColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Temp: ${latestSensorValues['temp']} °C • Humidity: ${latestSensorValues['humidity']} % • Gas: ${latestSensorValues['gas']} • Flame: ${latestSensorValues['flame']}',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'LED: ${latestSensorValues['led']} • Buzzer: ${latestSensorValues['buzzer']} • Servo: ${latestSensorValues['servo']}°',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            // Servo control
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Servo Control',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.burgundy700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            _publishControl('servo', '90');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.burgundy700,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: const Text('Open Servo'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () {
                            _publishControl('servo', '0');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.burgundy700,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: const Text('Close Servo'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Sensor data table
            Text(
              'Sensor History',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.burgundy700,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Card(
              color: AppColors.burgundy50,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 16,
                  headingRowColor:
                      MaterialStateProperty.all(AppColors.burgundy100),
                  columns: const [
                    DataColumn(
                      label: Text('Time',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text('Temp (°C)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text('Humidity (%)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text('Gas',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text('Flame',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text('LED',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text('Buzzer',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text('Servo (°)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    DataColumn(
                      label: Text('Status',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                  rows: sensorData.map((data) {
                    return DataRow(cells: [
                      DataCell(Text(
                        DateFormat('yyyy-MM-dd HH:mm:ss')
                            .format(DateTime.parse(data['created_at'])),
                        style: Theme.of(context).textTheme.bodySmall,
                      )),
                      DataCell(Text(
                        data['temp']?.toString() ?? '--',
                        style: Theme.of(context).textTheme.bodySmall,
                      )),
                      DataCell(Text(
                        data['hum']?.toString() ?? '--',
                        style: Theme.of(context).textTheme.bodySmall,
                      )),
                      DataCell(Text(
                        data['gas']?.toString() ?? '--',
                        style: Theme.of(context).textTheme.bodySmall,
                      )),
                      DataCell(Text(
                        data['flame']?.toString() ?? '--',
                        style: Theme.of(context).textTheme.bodySmall,
                      )),
                      DataCell(Text(
                        data['led']?.toString() ?? '--',
                        style: Theme.of(context).textTheme.bodySmall,
                      )),
                      DataCell(Text(
                        data['buzzer']?.toString() ?? '--',
                        style: Theme.of(context).textTheme.bodySmall,
                      )),
                      DataCell(Text(
                        data['servo']?.toString() ?? '--',
                        style: Theme.of(context).textTheme.bodySmall,
                      )),
                      DataCell(Text(
                        data['status']?.toString() ?? '--',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: data['status']
                                      ?.toLowerCase()
                                      .contains('danger')
                                  ? AppColors.danger
                                  : AppColors.success,
                            ),
                      )),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
