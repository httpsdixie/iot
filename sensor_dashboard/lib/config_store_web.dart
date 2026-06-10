import 'dart:html' as html;

Future<void> platformSave(String key, String value) async {
  try {
    html.window.localStorage[key] = value;
  } catch (e) {
    // Ignore storage errors on web
  }
}

Future<String?> platformLoad(String key) async {
  try {
    return html.window.localStorage[key];
  } catch (e) {
    return null;
  }
}
