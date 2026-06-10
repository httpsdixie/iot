import 'config_store_stub.dart'
    if (dart.library.io) 'config_store_io.dart'
    if (dart.library.html) 'config_store_web.dart';

class ConfigStore {
  static Future<void> save(String key, String value) => platformSave(key, value);
  static Future<String?> load(String key) => platformLoad(key);
}
