import 'package:flutter/foundation.dart';

import '../models/settings.dart';
import '../util/json.dart';
import 'json_store.dart';
import 'secret_store.dart';

/// Holds [AppSettings] (persisted as JSON) and API keys (in the [SecretStore]).
class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._store, this.secrets);

  final JsonStore _store;
  final SecretStore secrets;
  AppSettings settings = AppSettings();

  Future<void> load() async {
    settings = AppSettings.fromJson(jMap(await _store.read('settings.json')));
    notifyListeners();
  }

  /// Apply a mutation and persist.
  void update(void Function(AppSettings s) change) {
    change(settings);
    _store.scheduleWrite('settings.json', settings.toJson, delay: const Duration(milliseconds: 300));
    notifyListeners();
  }

  Future<String?> readSecret(String key) => secrets.read(key);

  Future<void> writeSecret(String key, String? value) async {
    await secrets.write(key, value);
    notifyListeners();
  }
}
