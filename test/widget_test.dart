import 'dart:convert';

import 'package:epi_app/core/dates.dart';
import 'package:epi_app/domain/child_id.dart';
import 'package:epi_app/domain/engine.dart';
import 'package:epi_app/domain/rules.dart';
import 'package:epi_app/domain/text_match.dart';
import 'package:epi_app/services/card_pdf.dart';
import 'package:epi_app/services/xlsx.dart';
import 'package:epi_app/data/models.dart';
import 'package:epi_app/services/zip_writer.dart';
import 'package:flutter_test/flutter_test.dart';

// Reference cases for the five TOR acceptance scenarios. Values follow the
// provisional rule set; they are replaced by YFCA's reference cases at Day 2.
void main() {
  final dob = DateTime.utc(2026, 1, 1);

  group('Scenario 1: routine schedule from birth', () {
    test('newborn on day 0: birth doses due, 6-week doses upcoming on day 42', () {
      final s = Engine.compute(dob: dob, given: {}, asOf: dob);
      expect(s.byCode('BCG')!.status, DoseStatus.due);
      expect(s.byCode('PENTA1')!.status, DoseStatus.upcoming);
      expect(s.byCode('PENTA1')!.dueDate, addDays(dob, 42));
      expect(s.byCode('MR1')!.dueDate, addDays(dob, 270));
      expect(s.nextVisit, dob);
    });

    test('on-time doses keep the routine dates', () {
      final given = {
        'BCG': dob,
        'OPV0': dob,
        'HEPB0': dob,
        'PENTA1': addDays(dob, 42),
        'OPV1': addDays(dob, 42),
        'ROTA1': addDays(dob, 42),
        'PCV1': addDays(dob, 42),
      };
      final s = Engine.compute(dob: dob, given: given, asOf: addDays(dob, 50));
      expect(s.byCode('PENTA2')!.dueDate, addDays(dob, 70));
      expect(s.byCode('PENTA2')!.status, DoseStatus.upcoming);
      expect(s.nextVisit, addDays(dob, 70));
    });
  });

  group('Scenario 2: older infant with Rotavirus age cut-off', () {
    test('Rota not offered after the maximum age', () {
      final s = Engine.compute(dob: dob, given: {}, asOf: addDays(dob, 200));
      expect(s.byCode('ROTA1')!.status, DoseStatus.notEligible);
      expect(s.byCode('ROTA2')!.status, DoseStatus.notEligible);
      expect(s.byCode('PENTA1')!.status, DoseStatus.overdue);
    });

    test('recording Rota-1 after the cut-off is rejected', () {
      final err = Engine.validateGiven(code: 'ROTA1', date: addDays(dob, 150), dob: dob, given: {}, asOf: addDays(dob, 200));
      expect(err, 'err_max_age');
    });
  });

  group('Scenario 3: delayed attendance moves later doses forward', () {
    test('Penta-1 given late pushes Penta-2 by the minimum interval', () {
      final given = {'PENTA1': addDays(dob, 80)};
      final s = Engine.compute(dob: dob, given: given, asOf: addDays(dob, 80));
      expect(s.byCode('PENTA2')!.dueDate, addDays(dob, 108));
      expect(s.byCode('PENTA3')!.dueDate, addDays(dob, 136));
    });

    test('an overdue dose is projected to today, so the next one starts from today', () {
      final now = addDays(dob, 100);
      final s = Engine.compute(dob: dob, given: {}, asOf: now);
      expect(s.byCode('PENTA1')!.status, DoseStatus.overdue);
      expect(s.byCode('PENTA2')!.dueDate, addDays(now, 28));
    });
  });

  group('Clinical validation', () {
    test('dose before minimum age is rejected', () {
      expect(Engine.validateGiven(code: 'PENTA1', date: addDays(dob, 30), dob: dob, given: {}, asOf: addDays(dob, 60)),
          'err_min_age');
    });
    test('dose before the interval is rejected', () {
      expect(
          Engine.validateGiven(
              code: 'PENTA2', date: addDays(dob, 75), dob: dob, given: {'PENTA1': addDays(dob, 60)}, asOf: addDays(dob, 90)),
          'err_interval');
    });
    test('second dose without the first is rejected', () {
      expect(Engine.validateGiven(code: 'PENTA2', date: addDays(dob, 90), dob: dob, given: {}, asOf: addDays(dob, 90)),
          'err_prev_missing');
    });
    test('live vaccines 10 days apart are rejected, same day is accepted', () {
      final given = {'BCG': addDays(dob, 265)};
      expect(Engine.validateGiven(code: 'MR1', date: addDays(dob, 275), dob: dob, given: given, asOf: addDays(dob, 280)),
          'err_live_spacing');
      expect(Engine.validateGiven(code: 'MR1', date: addDays(dob, 270), dob: dob, given: {'BCG': addDays(dob, 270)}, asOf: addDays(dob, 280)),
          isNull);
    });
    test('future dates are rejected', () {
      expect(Engine.validateGiven(code: 'BCG', date: addDays(dob, 5), dob: dob, given: {}, asOf: dob), 'err_future');
    });
    test('first missed milestone is reported', () {
      final s = Engine.compute(dob: dob, given: {'BCG': dob, 'OPV0': dob, 'HEPB0': dob}, asOf: addDays(dob, 120));
      expect(s.firstMissedMilestone, 1);
    });
  });

  group('Child ID', () {
    test('format and check digit', () {
      final id = makeChildId('adn07', 123);
      expect(id, startsWith('ADN07-000123-'));
      expect(isValidChildId(id), isTrue);
      expect(luhnCheckDigit('000123'), 0);
      expect(isValidChildId('ADN07-000123-5'), isFalse);
    });
  });

  group('Names and phones', () {
    test('Arabic normalisation matches spelling variants', () {
      expect(similarNames('فاطمة أحمد', 'فاطمه احمد'), isTrue);
      expect(similarNames('محمد', 'خالد'), isFalse);
    });
    test('Yemeni mobile numbers', () {
      expect(isValidYemenMobile('777123456'), isTrue);
      expect(isValidYemenMobile('+967 777 123 456'), isTrue);
      expect(isValidYemenMobile('٧٧٧١٢٣٤٥٦'), isTrue);
      expect(isValidYemenMobile('12345'), isFalse);
    });
  });

  group('Scenario 5: Excel package', () {
    test('zip has valid signatures and CRC', () {
      final z = ZipWriter()..addString('a.txt', 'hello');
      final bytes = z.build(when: DateTime(2026, 1, 1));
      expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      expect(crc32(utf8.encode('hello')), 0x3610A686);
      final end = bytes.sublist(bytes.length - 22, bytes.length - 18);
      expect(end, [0x50, 0x4B, 0x05, 0x06]);
    });
  });


  group('v0.2.0 rules', () {
    test('SCH-02: a dose old enough but inside the interval shows "waiting"', () {
      final now = addDays(dob, 100);
      final s = Engine.compute(dob: dob, given: {'PENTA1': addDays(dob, 90)}, asOf: now);
      expect(s.byCode('PENTA2')!.status, DoseStatus.waiting);
      expect(s.byCode('PENTA2')!.dueDate, addDays(dob, 118));
    });

    test('SCH-09: the next visit groups every dose due that day', () {
      final given = {'BCG': dob, 'OPV0': dob, 'HEPB0': dob};
      final s = Engine.compute(dob: dob, given: given, asOf: addDays(dob, 10));
      expect(s.nextVisit, addDays(dob, 42));
      expect(s.nextVisitDoses.map((d) => d.rule.code).toSet(), {'PENTA1', 'OPV1', 'ROTA1', 'PCV1'});
    });

    test('SCH-09: overdue doses are all offered at today\'s visit', () {
      final now = addDays(dob, 120);
      final s = Engine.compute(dob: dob, given: {'BCG': dob, 'OPV0': dob, 'HEPB0': dob}, asOf: now);
      expect(s.nextVisit, now);
      expect(s.nextVisitDoses.map((d) => d.rule.code), containsAll(['PENTA1', 'OPV1', 'PCV1']));
      expect(s.byCode('ROTA1')!.status, DoseStatus.notEligible); // past the Rota age limit
      expect(s.nextVisitDoses.any((d) => d.rule.code == 'PENTA2'), isFalse);
    });

    test('progress counts given doses against doses still possible', () {
      final s = Engine.compute(dob: dob, given: {'BCG': dob}, asOf: addDays(dob, 200));
      expect(s.givenCount, 1);
      expect(s.trackableCount, lessThan(RuleSet.doses.length)); // Rota is no longer possible
      expect(s.progress, closeTo(1 / s.trackableCount, 1e-9));
    });

    test('NFR-04/05: 5,000 schedules compute in under 1 second', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 5000; i++) {
        final d = addDays(dob, -(i % 1500));
        Engine.compute(dob: d, given: {'BCG': d, 'PENTA1': addDays(d, 45)}, asOf: addDays(dob, 30));
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000), reason: '${sw.elapsedMilliseconds} ms');
    });

    test('DOC-01..03: Excel export is a valid zip with an RTL sheet', () {
      final child = Child(
        id: 'ADN07-000001-8',
        seq: 1,
        name: 'فاطمة أحمد',
        sex: 'F',
        dob: dob,
        facilityId: 1,
        guardianName: 'أمل',
        guardianRelation: 'mother',
        createdBy: 'test',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final s = Engine.compute(dob: dob, given: {'BCG': dob}, asOf: addDays(dob, 50));
      final bytes = XlsxExport.build(child: child, facility: null, schedule: s, campaignDoses: const [], user: 'test', language: 'ar');
      expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text.contains('xl/worksheets/sheet1.xml'), isTrue);
      final en = XlsxExport.build(child: child, facility: null, schedule: s, campaignDoses: const [], user: 'test', language: 'en');
      expect(en.length, greaterThan(500));
    });
  });


  group('DOC-04: A4 card', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    Child kid(DateTime d) => Child(
          id: 'ADN07-000002-6',
          seq: 2,
          name: 'فاطمة أحمد علي سالم',
          nameLatin: 'Fatima Ahmed',
          sex: 'F',
          dob: d,
          birthWeight: 3100,
          facilityId: 1,
          area: 'ريمي',
          guardianName: 'أمل سالم',
          guardianRelation: 'mother',
          phone: '777123456',
          createdBy: 'test',
          createdAt: '2026-01-01T00:00:00Z',
        );

    test('vowel marks are removed from printed text', () {
      expect(CardPdf.printable('أُعطيت'), 'أعطيت');
      expect(CardPdf.printable('14 أسبوعًا'), '14 أسبوعا');
    });

    for (final lang in ['ar', 'en']) {
      test('is exactly one page in $lang, with every status present', () async {
        final now = addDays(dob, 300);
        final given = {
          for (final c in ['BCG', 'OPV0', 'HEPB0']) c: dob,
          for (final c in ['PENTA1', 'OPV1', 'PCV1']) c: addDays(dob, 280),
        };
        final s = Engine.compute(dob: dob, given: given, asOf: now);
        final statuses = s.doses.map((d) => d.status).toSet();
        expect(statuses, containsAll([DoseStatus.given, DoseStatus.overdue, DoseStatus.waiting, DoseStatus.notEligible]));
        final campaign = [
          DoseRecord(id: 1, childId: 'x', code: 'CAMPAIGN', status: 'campaign', givenDate: addDays(dob, 200),
              source: 'campaign', campaignName: 'حملة شلل الأطفال الوطنية', ruleVersion: 'v', createdBy: 't', createdAt: 't'),
        ];
        final bytes = await CardPdf.build(child: kid(dob), facility: const Facility(1, 'ADN07', 'مركز المنصورة الصحي', 'عدن', 'المنصورة'),
            schedule: s, campaignDoses: campaign, language: lang);
        final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;
        expect(pages, 1);
      });
    }
  });

  test('rule table is consistent', () {
    for (final r in RuleSet.doses) {
      expect(r.minAgeDays <= r.targetDays, isTrue, reason: r.code);
      if (r.maxAgeDays != null) expect(r.maxAgeDays! > r.minAgeDays, isTrue, reason: r.code);
      if (r.doseNo > 1) expect(RuleSet.previousInSeries(r), isNotNull, reason: r.code);
    }
  });
}
