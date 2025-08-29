// lib/dashboard.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'app_models.dart';

import 'add_sensor_page.dart';
import 'view_sensors_page.dart';
import 'live_status_screen.dart';
import 'alerts_page.dart';
import 'delete_sensor_page.dart';
import 'sensor_logs_screen.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late MqttServerClient client;

  // sensor values (strings for display). Defaults match "no data"
  Map<String, String> sensorValues = {
    "temp": "--",
    "humidity": "--",
    "gas": "--",
    "flame": "--",
    "buzzer": "0",
    "led": "0",
    "servo": "0",
  };

  int sensorCount = 0;
  int alertCount = 0;
  SystemStatus systemStatus = SystemStatus.safe;

  // thresholds same as ESP32 code
  final double gasThreshold = 2000.0; // raw analog
  final double flameThreshold = 2500.0; // flame: below this => danger
  final double tempThreshold = 40.0; // °C

  @override
  void initState() {
    super.initState();
    _connectMqtt();
    _fetchCounts();
  }

  @override
  void dispose() {
    client.disconnect();
    super.dispose();
  }

  Future<void> _fetchCounts() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        sensorCount = 0;
        alertCount = 0;
      });
      return;
    }

    try {
      final sensors = await Supabase.instance.client
          .from('user_sensors')
          .select()
          .eq('user_id', user.id);

      final alerts = await Supabase.instance.client
          .from('user_alerts')
          .select()
          .eq('user_id', user.id);

      setState(() {
        sensorCount = sensors is List ? sensors.length : 0;
        alertCount = alerts is List ? alerts.length : 0;
      });
    } catch (e) {
      debugPrint('Supabase fetch counts failed: $e');
    }
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
      // subscribe to the JSON topic and control/state topics
      client.subscribe('sensors/data', MqttQos.atMostOnce);
      client.subscribe('led', MqttQos.atMostOnce);
      client.subscribe('buzzer', MqttQos.atMostOnce);
      client.subscribe('servo', MqttQos.atMostOnce);

      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final recMsg = c[0].payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
        final topic = c[0].topic;
        if (!mounted) return;
        try {
          setState(() {
            if (topic == 'sensors/data') {
              // parse JSON
              final dynamic parsed = jsonDecode(payload);
              if (parsed is Map<String, dynamic>) {
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
              }
            } else if (topic == 'led' ||
                topic == 'buzzer' ||
                topic == 'servo') {
              // payload might be "ON"/"OFF" or "1"/"0" or an angle number for servo
              final trimmed = payload.trim();
              if (trimmed.toUpperCase() == 'ON') {
                sensorValues[topic] = '1';
              } else if (trimmed.toUpperCase() == 'OFF') {
                sensorValues[topic] = '0';
              } else {
                // numeric (angle or 0/1)
                sensorValues[topic] = trimmed;
              }
            }

            // Recompute systemStatus using thresholds and device states
            _recomputeSystemStatus();
          });
        } catch (e) {
          debugPrint('MQTT payload parse error on topic $topic: $e');
        }
      });
    }
  }

  void _recomputeSystemStatus() {
    // parse device states
    final int buzzer = int.tryParse(sensorValues['buzzer'] ?? '0') ?? 0;
    final int led = int.tryParse(sensorValues['led'] ?? '0') ?? 0;
    final double servo = double.tryParse(sensorValues['servo'] ?? '0') ?? 0;

    // parse sensor numeric values
    final double gasVal =
        double.tryParse(sensorValues['gas'] ?? '') ?? double.nan;
    final double tempVal =
        double.tryParse(sensorValues['temp'] ?? '') ?? double.nan;
    final double flameVal =
        double.tryParse(sensorValues['flame'] ?? '') ?? double.nan;

    // If any actuator is active -> consider danger (real device alarm)
    if (buzzer == 1 || led == 1 || servo > 0) {
      systemStatus = SystemStatus.danger;
      return;
    }

    // Evaluate sensor thresholds (match ESP thresholds)
    bool gasDanger = !gasVal.isNaN && gasVal > gasThreshold;
    bool flameDanger = !flameVal.isNaN &&
        flameVal < flameThreshold; // low flame reading => danger
    bool tempDanger = !tempVal.isNaN && tempVal > tempThreshold;

    if (gasDanger || flameDanger || tempDanger) {
      systemStatus = SystemStatus
          .warning; // show warning; AlertsPage can escalate / publish actuators
      // If you want immediate danger state when sensors exceed, change to SystemStatus.danger
    } else {
      systemStatus = SystemStatus.safe;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen Safety Dashboard'),
        backgroundColor: AppColors.burgundy700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSystemStatusCard(systemStatus),
            const SizedBox(height: 24),
            _buildQuickStats(),
            const SizedBox(height: 24),
            Text(
              'Quick Access',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.burgundy700,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildNavigationGrid(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemStatusCard(SystemStatus status) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case SystemStatus.safe:
        statusColor = AppColors.success;
        statusText = 'All Systems Safe';
        statusIcon = Icons.check_circle;
        break;
      case SystemStatus.warning:
        statusColor = AppColors.warning;
        statusText = 'Warning Detected';
        statusIcon = Icons.warning;
        break;
      case SystemStatus.danger:
        statusColor = AppColors.danger;
        statusText = 'Danger Alert!';
        statusIcon = Icons.error;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(statusIcon, size: 48, color: Colors.white),
          const SizedBox(height: 12),
          Text(
            statusText,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Last updated: ${DateTime.now().toString().substring(11, 16)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                ),
          ),
          const SizedBox(height: 12),
          // quick telemetry row
          Text(
            'T: ${sensorValues['temp']}°  •  H: ${sensorValues['humidity']}%  •  Gas: ${sensorValues['gas']}  •  Flame: ${sensorValues['flame']}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withOpacity(0.95),
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Sensors',
            '$sensorCount',
            Icons.sensors,
            AppColors.burgundy700,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Active Alerts',
            '$alertCount',
            Icons.warning_amber_rounded,
            AppColors.danger,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mediumGrey,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationGrid(BuildContext context) {
    final navigationItems = [
      _NavigationItem(
        title: 'Add Sensor',
        subtitle: 'Connect new IoT sensors',
        icon: Icons.add_circle,
        color: AppColors.burgundy700,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const AddSensorPage()),
        ),
      ),
      _NavigationItem(
        title: 'My Sensors',
        subtitle: 'Manage connected sensors',
        icon: Icons.devices,
        color: AppColors.burgundy600,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const ViewSensorsPage()),
        ),
      ),
      _NavigationItem(
        title: 'Live Status',
        subtitle:
            'T:${sensorValues['temp']}° H:${sensorValues['humidity']}%\nG:${sensorValues['gas']} F:${sensorValues['flame']}',
        icon: Icons.monitor_heart,
        color: AppColors.success,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const LiveStatusScreen()),
        ),
      ),
      _NavigationItem(
        title: 'Alert Settings',
        subtitle: 'Configure notifications',
        icon: Icons.notifications,
        color: AppColors.warning,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const AlertsPage()),
        ),
      ),
      _NavigationItem(
        title: 'Sensor Logs',
        subtitle: 'View historical data',
        icon: Icons.history,
        color: AppColors.mediumGrey,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const SensorLogsScreen()),
        ),
      ),
      _NavigationItem(
        title: 'Delete Sensor',
        subtitle: 'Remove a sensor',
        icon: Icons.delete,
        color: AppColors.danger,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const DeleteSensorPage()),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: navigationItems.length,
      itemBuilder: (context, index) {
        final item = navigationItems[index];
        return Card(
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, size: 40, color: item.color),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkGrey,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.mediumGrey,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavigationItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _NavigationItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
