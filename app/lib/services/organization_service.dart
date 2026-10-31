import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/organization.dart';

class OrganizationService {
  OrganizationService({
    SupabaseClient? client,
    SharedPreferences? prefs,
  }) : _client = client,
       _prefs = prefs;

  final SupabaseClient? _client;
  SharedPreferences? _prefs;

  static const prefKeyOrgId = 'selected_organization_id';
  static const prefKeyOrgName = 'selected_organization_name';
  static const prefKeyOrgCode = 'selected_organization_code';

  List<Organization>? _cachedOrganizations;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  SupabaseClient? get _supabaseClient {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Fetches available organizations.
  /// Attempts a read-only Supabase query, falling back safely to the canonical
  /// list if offline or if the database is unreachable.
  Future<List<Organization>> fetchOrganizations({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedOrganizations != null && _cachedOrganizations!.isNotEmpty) {
      return _cachedOrganizations!;
    }

    final client = _supabaseClient;
    if (client != null) {
      try {
        final response = await client
            .from('organizations')
            .select('id, name, code, name_fr, is_active')
            .eq('is_active', true)
            .order('name');

        if (response.isNotEmpty) {
          final list = response
              .map((row) => Organization.fromJson(Map<String, dynamic>.from(row as Map)))
              .where((org) => org.isActive)
              .toList();
          if (list.isNotEmpty) {
            _cachedOrganizations = list;
            return list;
          }
        }
      } catch (e) {
        debugPrint('[OrganizationService] Offline or failed to fetch organizations from Supabase: $e');
      }
    }

    _cachedOrganizations = Organization.canonicalList;
    return Organization.canonicalList;
  }

  /// Returns the currently persisted organization, or null if none is selected
  /// or if the stored ID is invalid.
  Future<Organization?> getSelectedOrganization() async {
    final prefs = await _getPrefs();
    final storedId = prefs.getString(prefKeyOrgId);
    if (storedId == null || storedId.isEmpty) {
      return null;
    }

    final available = await fetchOrganizations();
    for (final org in available) {
      if (org.id == storedId) return org;
    }

    // Check canonical fallback list
    final canonical = Organization.findById(storedId);
    if (canonical != null) return canonical;

    // Stored ID is no longer valid
    debugPrint('[OrganizationService] Stored organization ID $storedId not found in valid list');
    return null;
  }

  /// Validates and persists the selected organization.
  Future<bool> setSelectedOrganization(Organization org) async {
    final available = await fetchOrganizations();
    final isValid = available.any((o) => o.id == org.id) ||
        Organization.canonicalList.any((o) => o.id == org.id);

    if (!isValid) {
      debugPrint('[OrganizationService] Rejected invalid organization: ${org.id}');
      return false;
    }

    final prefs = await _getPrefs();
    await prefs.setString(prefKeyOrgId, org.id);
    await prefs.setString(prefKeyOrgName, org.name);
    await prefs.setString(prefKeyOrgCode, org.code);
    return true;
  }

  /// Clears the selected organization (e.g. for testing or reset).
  Future<void> clearSelectedOrganization() async {
    final prefs = await _getPrefs();
    await prefs.remove(prefKeyOrgId);
    await prefs.remove(prefKeyOrgName);
    await prefs.remove(prefKeyOrgCode);
  }

  /// Validates whether an organization exists by ID.
  Future<bool> isValidOrganizationId(String id) async {
    final available = await fetchOrganizations();
    return available.any((o) => o.id == id);
  }
}
