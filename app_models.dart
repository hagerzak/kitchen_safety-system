enum SensorType { gas, flame, temperature, humidity }

enum SensorStatus { online, offline }

enum SystemStatus { safe, warning, danger }

enum LogStatus { safe, warning, danger }

class User {
  final String email;
  final String username;

  User({
    required this.email,
    required this.username,
  });
}

class Sensor {
  final SensorType type;
  final SensorStatus status;
  final String lastUpdate;
  final String? value;

  Sensor({
    required this.type,
    required this.status,
    required this.lastUpdate,
    this.value,
  });

  String get typeName {
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

  String get typeIcon {
    switch (type) {
      case SensorType.gas:
        return '🔴';
      case SensorType.flame:
        return '🔥';
      case SensorType.temperature:
        return '🌡';
      case SensorType.humidity:
        return '💧';
    }
  }

  Sensor copyWith({
    SensorType? type,
    SensorStatus? status,
    String? lastUpdate,
    String? value,
  }) {
    return Sensor(
      type: type ?? this.type,
      status: status ?? this.status,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      value: value ?? this.value,
    );
  }
}

class SensorLog {
  final String id;
  final SensorType sensorType;
  final String value;
  final LogStatus status;
  final DateTime timestamp;
  final double? rawValue;

  SensorLog({
    required this.id,
    required this.sensorType,
    required this.value,
    required this.status,
    required this.timestamp,
    this.rawValue,
  });

  String get sensorTypeName {
    switch (sensorType) {
      case SensorType.gas:
        return 'Gas';
      case SensorType.flame:
        return 'Flame';
      case SensorType.temperature:
        return 'Temperature';
      case SensorType.humidity:
        return 'Humidity';
    }
  }
}

class AlertSettings {
  final SensorType sensorType;
  final bool enabled;
  final String threshold;

  AlertSettings({
    required this.sensorType,
    required this.enabled,
    required this.threshold,
  });

  AlertSettings copyWith({
    SensorType? sensorType,
    bool? enabled,
    String? threshold,
  }) {
    return AlertSettings(
      sensorType: sensorType ?? this.sensorType,
      enabled: enabled ?? this.enabled,
      threshold: threshold ?? this.threshold,
    );
  }
}
