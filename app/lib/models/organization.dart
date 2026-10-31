/// Model representing an administrative authority or municipality in TariqMap.
class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.code,
    this.nameFr,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String code;
  final String? nameFr;
  final bool isActive;

  String localizedName({bool french = false}) =>
      (french ? nameFr : name) ?? name;

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
    id: json['id'] as String,
    name: json['name'] as String,
    code: (json['code'] as String?) ?? json['name'] as String,
    nameFr: json['name_fr'] as String?,
    isActive: (json['is_active'] as bool?) ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'name_fr': nameFr,
    'is_active': isActive,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Organization &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Organization(id: $id, name: $name, code: $code)';

  // ── Canonical Authorities ──────────────────────────────────────────────────
  static const municipality = Organization(
    id: '11111111-1111-4111-8111-111111111111',
    name: 'Municipality',
    code: 'MUNICIPALITY',
    nameFr: 'Commune',
    isActive: true,
  );

  static const ministryOfEquipment = Organization(
    id: '22222222-2222-4222-8222-222222222222',
    name: 'Ministry of Equipment',
    code: 'MINISTRY_OF_EQUIPMENT',
    nameFr: 'Ministère de l’Équipement',
    isActive: true,
  );

  static const tunisiaAutoroutes = Organization(
    id: '33333333-3333-4333-8333-333333333333',
    name: 'Tunisia Autoroutes',
    code: 'TUNISIA_AUTOROUTES',
    nameFr: 'Tunisie Autoroutes',
    isActive: true,
  );

  static const canonicalList = <Organization>[
    municipality,
    ministryOfEquipment,
    tunisiaAutoroutes,
  ];

  static Organization? findById(String id) {
    for (final org in canonicalList) {
      if (org.id == id) return org;
    }
    return null;
  }

  static Organization? findByName(String name) {
    for (final org in canonicalList) {
      if (org.name.toLowerCase() == name.toLowerCase() ||
          org.code.toLowerCase() == name.toLowerCase()) {
        return org;
      }
    }
    return null;
  }
}
