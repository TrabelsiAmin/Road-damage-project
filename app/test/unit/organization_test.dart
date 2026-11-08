import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tariqmap/models/organization.dart';
import 'package:tariqmap/services/organization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Organization Service & Authority Selection Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('1. First launch with no organization returns null from getSelectedOrganization', () async {
      SharedPreferences.setMockInitialValues({});
      final service = OrganizationService();

      final selected = await service.getSelectedOrganization();
      expect(selected, isNull, reason: 'First launch should not assume an authority without user choice');

      final available = await service.fetchOrganizations();
      expect(available, isNotEmpty);
      expect(available.length, greaterThanOrEqualTo(3));
    });

    test('2. Saved organization restoration retrieves the persisted organization', () async {
      final municipality = Organization.canonicalList.firstWhere((o) => o.code == 'MUNICIPALITY');
      SharedPreferences.setMockInitialValues({
        OrganizationService.prefKeyOrgId: municipality.id,
        OrganizationService.prefKeyOrgName: municipality.name,
        OrganizationService.prefKeyOrgCode: municipality.code,
      });

      final service = OrganizationService();
      final restored = await service.getSelectedOrganization();

      expect(restored, isNotNull);
      expect(restored!.id, equals(municipality.id));
      expect(restored.code, equals('MUNICIPALITY'));
      expect(restored.name, equals('Municipality'));
    });

    test('3. Organization change persists new authority correctly', () async {
      final ministry = Organization.canonicalList.firstWhere((o) => o.code == 'MINISTRY_OF_EQUIPMENT');
      SharedPreferences.setMockInitialValues({});
      final service = OrganizationService();

      final success = await service.setSelectedOrganization(ministry);
      expect(success, isTrue);

      final current = await service.getSelectedOrganization();
      expect(current, isNotNull);
      expect(current!.id, equals(ministry.id));
      expect(current.code, equals('MINISTRY_OF_EQUIPMENT'));

      // Switch to Tunisia Autoroutes
      final autoroutes = Organization.canonicalList.firstWhere((o) => o.code == 'TUNISIA_AUTOROUTES');
      final switched = await service.setSelectedOrganization(autoroutes);
      expect(switched, isTrue);

      final updated = await service.getSelectedOrganization();
      expect(updated, isNotNull);
      expect(updated!.id, equals(autoroutes.id));
      expect(updated.code, equals('TUNISIA_AUTOROUTES'));
    });

    test('4. Offline startup with an existing selection restores canonical organization', () async {
      final autoroutes = Organization.canonicalList.firstWhere((o) => o.code == 'TUNISIA_AUTOROUTES');
      SharedPreferences.setMockInitialValues({
        OrganizationService.prefKeyOrgId: autoroutes.id,
        OrganizationService.prefKeyOrgName: autoroutes.name,
        OrganizationService.prefKeyOrgCode: autoroutes.code,
      });

      // Passing client: null simulates offline / unreachable Supabase client
      final service = OrganizationService(client: null);
      final restored = await service.getSelectedOrganization();

      expect(restored, isNotNull);
      expect(restored!.id, equals(autoroutes.id));
      expect(restored.name, contains('Tunisia Autoroutes'));
    });

    test('5. Invalid organization handling rejects non-existent UUIDs', () async {
      SharedPreferences.setMockInitialValues({
        OrganizationService.prefKeyOrgId: '00000000-0000-0000-0000-000000000000',
        OrganizationService.prefKeyOrgName: 'Fake Organization',
      });

      final service = OrganizationService(client: null);
      final restored = await service.getSelectedOrganization();
      expect(restored, isNull, reason: 'Invalid or unknown org ID should not be accepted');

      const fakeOrg = Organization(
        id: 'bad-uuid-1234',
        name: 'Hacked Org',
        code: 'HACK',
      );
      final saveResult = await service.setSelectedOrganization(fakeOrg);
      expect(saveResult, isFalse, reason: 'Should reject setting an unregistered organization');
    });

    test('6. Canonical list contains all required Tunisian road authorities', () {
      const canonical = Organization.canonicalList;
      expect(canonical.length, equals(3));

      final codes = canonical.map((o) => o.code).toList();
      expect(codes, containsAll(['MUNICIPALITY', 'MINISTRY_OF_EQUIPMENT', 'TUNISIA_AUTOROUTES']));

      for (final org in canonical) {
        expect(org.id, isNotEmpty);
        expect(org.name, isNotEmpty);
        expect(org.isActive, isTrue);
      }
    });
  });
}
