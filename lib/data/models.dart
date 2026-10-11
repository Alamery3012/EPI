import '../core/dates.dart';

class Facility {
  final int id;
  final String code;
  final String name;
  final String governorate;
  final String district;
  const Facility(this.id, this.code, this.name, this.governorate, this.district);

  factory Facility.fromMap(Map<String, Object?> m) => Facility(
        m['id'] as int,
        m['code'] as String,
        m['name'] as String,
        m['governorate'] as String,
        m['district'] as String,
      );
}

class Child {
  final String id;
  final int seq;
  final String name;
  final String? nameLatin;
  final String sex;
  final DateTime dob;
  final int? birthWeight;
  final int facilityId;
  final String? area;
  final String guardianName;
  final String? guardianRelation;
  final String? phone;
  final bool historyDone;
  final bool voided;
  final String createdBy;
  final String createdAt;
  final String? modifiedBy;
  final String? modifiedAt;

  const Child({
    required this.id,
    required this.seq,
    required this.name,
    this.nameLatin,
    required this.sex,
    required this.dob,
    this.birthWeight,
    required this.facilityId,
    this.area,
    required this.guardianName,
    this.guardianRelation,
    this.phone,
    this.historyDone = false,
    this.voided = false,
    required this.createdBy,
    required this.createdAt,
    this.modifiedBy,
    this.modifiedAt,
  });

  factory Child.fromMap(Map<String, Object?> m) => Child(
        id: m['id'] as String,
        seq: m['seq'] as int,
        name: m['name'] as String,
        nameLatin: m['name_latin'] as String?,
        sex: m['sex'] as String,
        dob: parseIso(m['dob'] as String),
        birthWeight: m['birth_weight'] as int?,
        facilityId: m['facility_id'] as int,
        area: m['area'] as String?,
        guardianName: m['guardian_name'] as String,
        guardianRelation: m['guardian_relation'] as String?,
        phone: m['phone'] as String?,
        historyDone: (m['history_done'] as int? ?? 0) == 1,
        voided: (m['voided'] as int? ?? 0) == 1,
        createdBy: m['created_by'] as String,
        createdAt: m['created_at'] as String,
        modifiedBy: m['modified_by'] as String?,
        modifiedAt: m['modified_at'] as String?,
      );

  /// Editable fields as stored, used to diff changes for the audit log.
  Map<String, Object?> editable() => {
        'name': name,
        'name_latin': nameLatin,
        'sex': sex,
        'dob': iso(dob),
        'birth_weight': birthWeight,
        'facility_id': facilityId,
        'area': area,
        'guardian_name': guardianName,
        'guardian_relation': guardianRelation,
        'phone': phone,
      };
}

class DoseRecord {
  final int id;
  final String childId;
  final String code;
  final String status; // given | not_given | unknown | campaign
  final DateTime? givenDate;
  final String source;
  final String? reason;
  final String? campaignName;
  final String ruleVersion;
  final String createdBy;
  final String createdAt;
  const DoseRecord({
    required this.id,
    required this.childId,
    required this.code,
    required this.status,
    this.givenDate,
    required this.source,
    this.reason,
    this.campaignName,
    required this.ruleVersion,
    required this.createdBy,
    required this.createdAt,
  });

  factory DoseRecord.fromMap(Map<String, Object?> m) => DoseRecord(
        id: m['id'] as int,
        childId: m['child_id'] as String,
        code: m['code'] as String,
        status: m['status'] as String,
        givenDate: tryParseIso(m['given_date'] as String?),
        source: m['source'] as String,
        reason: m['reason'] as String?,
        campaignName: m['campaign_name'] as String?,
        ruleVersion: m['rule_version'] as String,
        createdBy: m['created_by'] as String,
        createdAt: m['created_at'] as String,
      );
}

class AuditEntry {
  final String ts;
  final String user;
  final String action;
  final String entity;
  final String? entityId;
  final String? detail;
  const AuditEntry(this.ts, this.user, this.action, this.entity, this.entityId, this.detail);

  factory AuditEntry.fromMap(Map<String, Object?> m) => AuditEntry(
        m['ts'] as String,
        m['user'] as String,
        m['action'] as String,
        m['entity'] as String,
        m['entity_id'] as String?,
        m['detail'] as String?,
      );
}

/// Input for a past-visit intake entry (FRS-HIS-02).
class HistoryEntry {
  final String code;
  final String status; // given | not_given | unknown
  final DateTime? date;
  const HistoryEntry(this.code, this.status, this.date);
}
