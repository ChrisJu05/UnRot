import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Storage for sensitive values such as AI API keys.
///
/// The default [FileSecretStore] keeps keys in a separate file that is only
/// readable by the current user. Platform keychains (libsecret, Keychain,
/// Windows Credential Manager, Android Keystore) can be plugged in by
/// implementing this interface — see docs/ARCHITECTURE.md.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class FileSecretStore implements SecretStore {
  FileSecretStore(Directory directory) : _file = File(p.join(directory.path, 'secrets.json'));

  final File _file;
  Map<String, String>? _cache;

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          return _cache = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (_) {}
    return _cache = {};
  }

  @override
  Future<String?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, String? value) async {
    final map = await _load();
    if (value == null || value.isEmpty) {
      map.remove(key);
    } else {
      map[key] = value;
    }
    await _file.parent.create(recursive: true);
    if (!await _file.exists()) {
      // Restrict permissions before any secret is written to the file.
      await _file.create();
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          await Process.run('chmod', ['600', _file.path]);
        } catch (_) {}
      }
    }
    await _file.writeAsString(jsonEncode(map), flush: true);
  }
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
