import 'dart:io';
import 'dart:convert';

File _getConfigFile() {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
  return File('$home/.sensor_dashboard_config.json');
}

Future<void> platformSave(String key, String value) async {
  try {
    final file = _getConfigFile();
    Map<String, dynamic> data = {};
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
        data = Map<String, dynamic>.from(json.decode(content));
      }
    }
    data[key] = value;
    await file.writeAsString(json.encode(data));
  } catch (e) {
    // Ignore write errors to prevent app crashes
  }
}

Future<String?> platformLoad(String key) async {
  try {
    final file = _getConfigFile();
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
        final data = json.decode(content) as Map;
        return data[key]?.toString();
      }
    }
  } catch (e) {
    // Ignore read errors
  }
  return null;
}
