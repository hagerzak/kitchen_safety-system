import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_theme.dart';

class DeleteSensorPage extends StatefulWidget {
  const DeleteSensorPage({super.key});

  @override
  State<DeleteSensorPage> createState() => _DeleteSensorPageState();
}

class _DeleteSensorPageState extends State<DeleteSensorPage> {
  Future<List<Map<String, dynamic>>> fetchSensors() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final data = await Supabase.instance.client
        .from('user_sensors')
        .select('sensor_type, profiles(username)')
        .eq('user_id', user.id);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> deleteSensor(String type) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await Supabase.instance.client
        .from('user_sensors')
        .delete()
        .eq('user_id', user.id)
        .eq('sensor_type', type);

    setState(() {}); // refresh UI after deletion
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Delete Sensor',
          style: TextStyle(fontFamily: 'Pacifico'),
        ),
        backgroundColor: theme.colorScheme.primary,
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchSensors(),
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final sensors = snapshot.data!;
          if (sensors.isEmpty) {
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
                      'No Sensors Found',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: AppColors.burgundy700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sensors.length,
            itemBuilder: (ctx, i) {
              final type = sensors[i]['sensor_type'];
              final username = sensors[i]['profiles']['username'];

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.only(bottom: 16),
                color: AppColors.burgundy50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.burgundy200.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.sensors,
                            color: AppColors.burgundy700),
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
                                color: AppColors.burgundy800,
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
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.danger),
                        onPressed: () =>
                            _showDeleteConfirmDialog(context, type),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, String type) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Sensor'),
        content: Text(
          'Are you sure you want to remove the "$type" sensor? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              deleteSensor(type);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$type removed successfully'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
