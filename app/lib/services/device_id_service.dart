import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Manages a local random UUID for this device installation.
///
/// PRIVACY & SECURITY NOTE:
/// - This UUID identifies no personal data and is stored solely in local storage.
/// - It must NEVER be sent to public-readable Supabase tables.
class DeviceIdService {
  DeviceIdService._();
  static final DeviceIdService instance = DeviceIdService._();

  static const _key = 'tariqmap_device_id';
  String? _cachedId;

  /// Retrieves the existing device UUID, or generates and persists a new one on first launch.
  Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_key);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await prefs.setString(_key, id);
      }
      _cachedId = id;
      return id;
    } catch (_) {
      // Fallback in test or restricted environments
      _cachedId ??= const Uuid().v4();
      return _cachedId!;
    }
  }
}
