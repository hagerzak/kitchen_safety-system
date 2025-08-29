import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_theme.dart';
import 'app_models.dart';

class AddSensorPage extends StatefulWidget {
  const AddSensorPage({super.key});

  @override
  State<AddSensorPage> createState() => _AddSensorPageState();
}

class _AddSensorPageState extends State<AddSensorPage> {
  SensorType? selectedSensorType;
  bool isConnecting = false;
  List<SensorType> existingSensorTypes = [];

  final List<_SensorOption> sensorOptions = [
    _SensorOption(
      type: SensorType.gas,
      title: 'Gas Sensor',
      description: 'Detects gas leaks and harmful gas concentrations',
      icon: Icons.gas_meter,
      color: AppColors.danger,
      features: [
        'Detects LPG, natural gas, and propane',
        'Real-time concentration monitoring',
        'Configurable alert thresholds',
        'High sensitivity and accuracy',
      ],
    ),
    _SensorOption(
      type: SensorType.flame,
      title: 'Flame Sensor',
      description: 'Detects fire and flame presence in the kitchen',
      icon: Icons.local_fire_department,
      color: AppColors.warning,
      features: [
        'Infrared flame detection',
        'Wide detection angle',
        'Fast response time',
        'Reliable fire safety monitoring',
      ],
    ),
    _SensorOption(
      type: SensorType.temperature,
      title: 'Temperature Sensor',
      description: 'Monitors kitchen temperature and heat levels',
      icon: Icons.thermostat,
      color: AppColors.burgundy700,
      features: [
        'High precision temperature reading',
        'Wide temperature range',
        'Heat alert notifications',
        'Energy efficiency monitoring',
      ],
    ),
    _SensorOption(
      type: SensorType.humidity,
      title: 'Humidity Sensor',
      description: 'Monitors kitchen humidity and moisture',
      icon: Icons.water_drop,
      color: AppColors.burgundy600,
      features: [
        'Accurate humidity measurement',
        'Helps prevent mold formation',
        'Configurable alert thresholds',
        'Supports data logging',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fetchExistingSensors();
  }

  Future<void> _fetchExistingSensors() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final existing = await Supabase.instance.client
        .from('user_sensors')
        .select('sensor_type')
        .eq('user_id', user.id);

    setState(() {
      existingSensorTypes = existing
          .map<SensorType>((e) => SensorType.values.firstWhere(
                (t) => t.name == e['sensor_type'],
                orElse: () => SensorType.gas,
              ))
          .toList();
    });
  }

  Future<void> _handleAddSensor() async {
    if (selectedSensorType == null) return;

    setState(() {
      isConnecting = true;
    });

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      setState(() => isConnecting = false);
      return;
    }

    try {
      if (existingSensorTypes.length > 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximum number of sensors already connected'),
          ),
        );
        setState(() => isConnecting = false);
        return;
      }

      if (existingSensorTypes.contains(selectedSensorType)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${sensorOptions.firstWhere((o) => o.type == selectedSensorType).title} is already connected',
            ),
          ),
        );
        setState(() => isConnecting = false);
        return;
      }

      await Supabase.instance.client.from('user_sensors').insert({
        'user_id': user.id,
        'sensor_type': selectedSensorType!.name,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${sensorOptions.firstWhere((o) => o.type == selectedSensorType).title} connected successfully!',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Sensor')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Sensor Type',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.burgundy700,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the type of IoT sensor you want to connect to your kitchen safety system.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mediumGrey,
                  ),
            ),
            const SizedBox(height: 24),
            ...sensorOptions.map((option) {
              final isAlreadyAdded = existingSensorTypes.contains(option.type);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildSensorCard(
                  context,
                  option,
                  isAlreadyAdded,
                  selectedSensorType == option.type,
                  () {
                    if (!isAlreadyAdded) {
                      setState(() {
                        selectedSensorType = option.type;
                      });
                    }
                  },
                ),
              );
            }),
            const SizedBox(height: 24),
            if (selectedSensorType != null) ...[
              Card(
                color: AppColors.burgundy100,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: AppColors.burgundy700),
                          const SizedBox(width: 8),
                          Text(
                            'Connection Instructions',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppColors.burgundy700,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._getConnectionInstructions(selectedSensorType!)
                          .map((instruction) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(
                                          top: 6, right: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.burgundy700,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        instruction,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: AppColors.burgundy800,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: selectedSensorType != null && !isConnecting
                    ? _handleAddSensor
                    : null,
                child: isConnecting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.cream),
                        ),
                      )
                    : const Text('Connect Sensor'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard(
    BuildContext context,
    _SensorOption option,
    bool isAlreadyAdded,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Card(
      color: isSelected ? AppColors.burgundy100 : null,
      child: InkWell(
        onTap: isAlreadyAdded ? null : onTap,
        borderRadius: BorderRadius.circular(12),
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
                      color: option.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(option.icon, color: option.color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.darkGrey,
                                    ),
                              ),
                            ),
                            if (isAlreadyAdded)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Added',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                            if (isSelected && !isAlreadyAdded)
                              Icon(Icons.check_circle,
                                  color: AppColors.burgundy700, size: 20),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          option.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.mediumGrey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Key Features:',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
                    ),
              ),
              const SizedBox(height: 8),
              ...option.features.map((feature) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check, size: 16, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            feature,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.mediumGrey),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _getConnectionInstructions(SensorType sensorType) {
    switch (sensorType) {
      case SensorType.gas:
        return [
          'Connect the gas sensor to your ESP32 microcontroller',
          'Ensure proper ventilation during installation',
          'Position sensor near gas sources (stove, gas lines)',
          'Configure MQTT settings for data transmission',
          'Test sensor calibration before final setup',
        ];
      case SensorType.flame:
        return [
          'Mount flame sensor with clear line of sight',
          'Position away from direct sunlight interference',
          'Connect to ESP32 digital input pin',
          'Set appropriate detection sensitivity',
          'Test detection range and response time',
        ];
      case SensorType.temperature:
        return [
          'Install temperature sensor in representative location',
          'Avoid direct heat sources for accurate readings',
          'Connect to ESP32 analog input',
          'Calibrate temperature offset if needed',
          'Set up periodic reading intervals',
        ];
      case SensorType.humidity:
        return [
          'Place humidity sensor away from steam sources',
          'Connect to ESP32 analog/digital input',
          'Calibrate sensor reading if needed',
          'Set threshold alerts for high/low humidity',
          'Verify readings with a trusted device',
        ];
    }
  }
}

class _SensorOption {
  final SensorType type;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<String> features;

  _SensorOption({
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.features,
  });
}
