import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_models.dart';
import 'app_theme.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class LiveStatusScreen extends StatefulWidget {
  const LiveStatusScreen({super.key});

  @override
  State<LiveStatusScreen> createState() => _LiveStatusScreenState();
}

class _LiveStatusScreenState extends State<LiveStatusScreen> {
  late List<Sensor> sensors;
  late SystemStatus systemStatus;
  late MqttServerClient client;

  // Map to hold latest sensor & actuator values
  Map<String, String> sensorValues = {
    'temp': '--',
    'humidity': '--',
    'gas': '--',
    'flame': '--',
    'led': '0',
    'buzzer': '0',
    'servo': '0',
  };

  // thresholds
  final double gasThreshold = 2000;
  final double flameThreshold = 2500;
  final double tempThreshold = 40;

  @override
  void initState() {
    super.initState();

    sensors = [
      Sensor(
          type: SensorType.gas,
          status: SensorStatus.online,
          lastUpdate: '—',
          value: '--'),
      Sensor(
          type: SensorType.flame,
          status: SensorStatus.online,
          lastUpdate: '—',
          value: '--'),
      Sensor(
          type: SensorType.temperature,
          status: SensorStatus.online,
          lastUpdate: '—',
          value: '--'),
      Sensor(
          type: SensorType.humidity,
          status: SensorStatus.online,
          lastUpdate: '—',
          value: '--'),
    ];

    systemStatus = SystemStatus.safe;

    _connectMqtt();
  }

  Future<void> _connectMqtt() async {
    client = MqttServerClient(
      '436aa7eaa3cb4577bd3567b46af719b1.s1.eu.hivemq.cloud',
      'flutter_dashboard_${DateTime.now().millisecondsSinceEpoch}',
    );
    client.port = 8883;
    client.secure = true;
    client.logging(on: false);

    client.onConnected = () => debugPrint('MQTT Connected');
    client.onDisconnected = () => debugPrint('MQTT Disconnected');

    final connMess = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_dashboard_${DateTime.now().millisecondsSinceEpoch}')
        .startClean();
    client.connectionMessage = connMess;

    try {
      await client.connect(
        'hivemq.webclient.1756106226262',
        'sC6QPKpD3*cuI%@l81;y',
      );
    } catch (e) {
      debugPrint('MQTT connect failed: $e');
      try {
        client.disconnect();
      } catch (_) {}
      return;
    }

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      // subscribe only to JSON topic
      client.subscribe('sensors/data', MqttQos.atMostOnce);

      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final recMsg = c[0].payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
        final topic = c[0].topic;

        if (!mounted) return;

        if (topic == 'sensors/data') {
          try {
            final parsed = jsonDecode(payload);
            if (parsed is Map<String, dynamic>) {
              setState(() {
                // update sensorValues
                sensorValues['temp'] =
                    (parsed['temp'] ?? sensorValues['temp']).toString();
                sensorValues['humidity'] = (parsed['hum'] ??
                        parsed['humidity'] ??
                        sensorValues['humidity'])
                    .toString();
                sensorValues['gas'] =
                    (parsed['gas'] ?? sensorValues['gas']).toString();
                sensorValues['flame'] =
                    (parsed['flame'] ?? sensorValues['flame']).toString();

                // update sensors list for UI
                sensors = sensors.map((s) {
                  final val = sensorValues[s.type.name.toLowerCase()] ?? '--';
                  return s.copyWith(
                      value: val,
                      lastUpdate:
                          DateTime.now().toIso8601String().substring(11, 16),
                      status: SensorStatus.online);
                }).toList();

                _recomputeSystemStatus();
              });
            }
          } catch (e) {
            debugPrint('JSON parse error: $e');
          }
        }
      });
    }
  }

  void _recomputeSystemStatus() {
    // parse actuator states
    final int buzzer = int.tryParse(sensorValues['buzzer'] ?? '0') ?? 0;
    final int led = int.tryParse(sensorValues['led'] ?? '0') ?? 0;
    final double servo = double.tryParse(sensorValues['servo'] ?? '0') ?? 0;

    final double gasVal =
        double.tryParse(sensorValues['gas'] ?? '') ?? double.nan;
    final double tempVal =
        double.tryParse(sensorValues['temp'] ?? '') ?? double.nan;
    final double flameVal =
        double.tryParse(sensorValues['flame'] ?? '') ?? double.nan;

    // immediate danger if actuators active
    if (buzzer == 1 || led == 1 || servo > 0) {
      systemStatus = SystemStatus.danger;
      return;
    }

    bool gasDanger = !gasVal.isNaN && gasVal > gasThreshold;
    bool flameDanger = !flameVal.isNaN && flameVal < flameThreshold;
    bool tempDanger = !tempVal.isNaN && tempVal > tempThreshold;

    if (gasDanger || flameDanger || tempDanger) {
      systemStatus = SystemStatus.warning;
    } else {
      systemStatus = SystemStatus.safe;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount =
        sensors.where((s) => s.status == SensorStatus.online).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // optional: you can manually trigger a refresh here
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Sensor data will update automatically via MQTT')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSystemStatusHeader(context, systemStatus),
            const SizedBox(height: 24),
            Text(
              'Live Sensor Readings',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.burgundy700,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ...sensors.map((sensor) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildLiveSensorCard(context, sensor),
                )),
            const SizedBox(height: 24),
            _buildSystemInfoCard(context, sensors),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemStatusHeader(BuildContext context, SystemStatus status) {
    Color statusColor;
    String statusText;
    String statusDescription;
    IconData statusIcon;

    switch (status) {
      case SystemStatus.safe:
        statusColor = AppColors.success;
        statusText = 'System Safe';
        statusDescription = 'All sensors are operating normally';
        statusIcon = Icons.check_circle;
        break;
      case SystemStatus.warning:
        statusColor = AppColors.warning;
        statusText = 'Warning';
        statusDescription = 'Some sensors require attention';
        statusIcon = Icons.warning;
        break;
      case SystemStatus.danger:
        statusColor = AppColors.danger;
        statusText = 'Danger Alert!';
        statusDescription = 'Immediate attention required';
        statusIcon = Icons.error;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: statusColor.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Icon(statusIcon, size: 56, color: Colors.white),
          const SizedBox(height: 12),
          Text(
            statusText,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            statusDescription,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white.withOpacity(0.9)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Last updated: ${DateTime.now().toIso8601String().substring(11, 16)}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveSensorCard(BuildContext context, Sensor sensor) {
    final isOnline = sensor.status == SensorStatus.online;
    final sensorColor = _getSensorColor(sensor.type);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: sensorColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10)),
                child:
                    Text(sensor.typeIcon, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sensor.typeName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.darkGrey)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: isOnline
                                  ? AppColors.success
                                  : AppColors.mediumGrey,
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text(isOnline ? 'LIVE' : 'OFFLINE',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Text('Updated ${sensor.lastUpdate}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.mediumGrey)),
                      ]),
                    ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                sensorColor.withOpacity(0.08),
                sensorColor.withOpacity(0.03)
              ], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: sensorColor.withOpacity(0.25)),
            ),
            child: Column(children: [
              Text('Current Reading',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: sensorColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(sensor.value ?? '—',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: sensorColor, fontWeight: FontWeight.bold)),
              if (!isOnline) ...[
                const SizedBox(height: 8),
                Text('Sensor is currently offline',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mediumGrey,
                        fontStyle: FontStyle.italic)),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _buildStatusIndicator(
                    context,
                    'Connection',
                    isOnline ? 'Stable' : 'Lost',
                    isOnline ? AppColors.success : AppColors.danger,
                    isOnline ? Icons.wifi : Icons.wifi_off)),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatusIndicator(
                context,
                'Signal',
                isOnline ? 'Strong' : 'Weak',
                isOnline ? AppColors.success : AppColors.warning,
                isOnline
                    ? Icons.signal_cellular_4_bar
                    : Icons.signal_cellular_alt,
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context, String label, String value,
      Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.mediumGrey)),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _buildSystemInfoCard(BuildContext context, List<Sensor> sensors) {
    final onlineSensors =
        sensors.where((s) => s.status == SensorStatus.online).length;
    final totalSensors = sensors.length;

    return Card(
      color: AppColors.burgundy50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.info_outline, color: AppColors.burgundy700),
            const SizedBox(width: 8),
            Text('System Information',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.burgundy700, fontWeight: FontWeight.bold))
          ]),
          const SizedBox(height: 12),
          _buildInfoRow(context, 'Total Sensors', '$totalSensors'),
          _buildInfoRow(context, 'Online Sensors', '$onlineSensors'),
          _buildInfoRow(
              context,
              'System Health',
              totalSensors > 0
                  ? '${((onlineSensors / totalSensors) * 100).round()}%'
                  : '0%'),
          _buildInfoRow(context, 'Last System Check',
              DateTime.now().toIso8601String().substring(11, 16)),
          _buildInfoRow(context, 'MQTT Connection', '—'),
        ]),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.burgundy600)),
        Text(value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.burgundy800, fontWeight: FontWeight.bold)),
      ]),
    );
  }

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
}
