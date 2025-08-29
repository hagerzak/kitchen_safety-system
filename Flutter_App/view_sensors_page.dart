import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'app_theme.dart';
import 'add_sensor_page.dart';

class ViewSensorsPage extends StatefulWidget {
  const ViewSensorsPage({super.key});

  @override
  State<ViewSensorsPage> createState() => _ViewSensorsPageState();
}

class _ViewSensorsPageState extends State<ViewSensorsPage> {
  final client = MqttServerClient(
    '436aa7eaa3cb4577bd3567b46af719b1.s1.eu.hivemq.cloud',
    'flutterClient',
  );

  Map<String, dynamic> mqttValues = {};

  @override
  void initState() {
    super.initState();
    _connectMQTT();
  }

  Future<void> _connectMQTT() async {
    client.port = 8883;
    client.secure = true;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.setProtocolV311();
    client.connectionMessage = MqttConnectMessage()
        .authenticateAs(
            'hivemq.webclient.1756106226262', 'sC6QPKpD3*cuI%@l81;y')
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    try {
      await client.connect();

      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        client.subscribe('sensors/data', MqttQos.atMostOnce);

        client.updates?.listen((messages) {
          if (messages.isEmpty) return;
          final recMsg = messages[0].payload as MqttPublishMessage;
          final payload =
              MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);

          debugPrint('MQTT payload: $payload');

          try {
            final data = jsonDecode(payload);
            if (data is Map<String, dynamic>) {
              setState(() => mqttValues = data);
            } else {
              debugPrint('Unexpected payload format');
            }
          } catch (e) {
            debugPrint("JSON parse error: $e");
          }
        });
      }
    } catch (e) {
      debugPrint('MQTT connection failed: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchSensors() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final data = await Supabase.instance.client
        .from('user_sensors')
        .select('sensor_type, profiles(username)')
        .eq('user_id', user.id);

    return List<Map<String, dynamic>>.from(data);
  }

  bool _isDanger(String type, String value) {
    final val = double.tryParse(value);
    if (val == null) return false;

    switch (type.toLowerCase()) {
      case 'gas':
        return val > 2000;
      case 'flame':
        return val < 2000; // لو الفلام أقل من حد معين يعتبر خطر
      case 'temp':
        return val > 50;
      case 'hum':
        return val < 20 || val > 80;
      default:
        return false;
    }
  }

  Color _getSensorColor(String type) {
    switch (type.toLowerCase()) {
      case 'gas':
        return AppColors.danger;
      case 'flame':
        return AppColors.warning;
      case 'temp':
        return AppColors.burgundy700;
      case 'hum':
        return AppColors.burgundy600;
      default:
        return AppColors.mediumGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Sensors',
          style: TextStyle(fontFamily: 'OpenSans'),
        ),
        backgroundColor: theme.colorScheme.primary,
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchSensors(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final sensors = snapshot.data!;
          if (sensors.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: sensors.map((sensor) {
              final type = sensor['sensor_type'];
              final username = sensor['profiles']['username'];
              final value = mqttValues[type]?.toString() ?? '--';
              final isDanger = _isDanger(type, value);

              return _buildSensorCard(context, type, value, username, isDanger);
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddSensorPage()),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.burgundy100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.sensors_off,
                size: 64,
                color: AppColors.burgundy700,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Sensors Connected',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.burgundy700,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start by adding your first IoT sensor to begin monitoring your kitchen safety.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mediumGrey,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (context) => const AddSensorPage()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Sensor'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard(BuildContext context, String type, String value,
      String username, bool isDanger) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getSensorColor(type).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.sensors, color: _getSensorColor(type)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.toUpperCase(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'User: $username',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.mediumGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDanger ? AppColors.danger : AppColors.success,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isDanger ? 'Danger' : 'Normal',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.burgundy50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.burgundy200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Reading:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.burgundy600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.burgundy800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
