import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/dates.dart';
import '../core/i18n.dart';
import '../data/models.dart';
import '../domain/engine.dart';
import '../domain/rules.dart';
import 'xlsx.dart';

/// Single-page A4 immunization card (FRS-DOC-04..06). Headings and the
/// clinical notice are provisional until MoPHP/EPI supply the official text.
class CardPdf {
  static final _blue = PdfColor.fromInt(0xFF0D7CBC);
  static final _orange = PdfColor.fromInt(0xFFE77632);
  static final _line = PdfColor.fromInt(0xFFB8C4CF);
  static final _soft = PdfColor.fromInt(0xFFE6F2FA);

  static Future<Uint8List> build({
    required Child child,
    required Facility? facility,
    required Schedule schedule,
    required List<DoseRecord> campaignDoses,
  }) async {
    final lang = Lang.current.value;
    final ar = lang == 'ar';
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Bold.ttf'));
    final dir = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final doc = pw.Document(
      title: 'Immunization card ${child.id}',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pw.Widget txt(String s, {double size = 9.5, bool b = false, PdfColor? color, pw.TextAlign? align}) => pw.Text(
          s,
          textDirection: dir,
          textAlign: align,
          style: pw.TextStyle(fontSize: size, fontWeight: b ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
        );

    pw.Widget field(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(children: [
            pw.SizedBox(width: 92, child: txt(label, size: 9, color: PdfColors.grey700)),
            pw.Expanded(child: txt(value.isEmpty ? '-' : value, size: 10, b: true)),
          ]),
        );

    pw.Widget cell(String s, {bool head = false, PdfColor? color}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
          color: head ? _blue : null,
          child: txt(s, size: head ? 9 : 9, b: head, color: head ? PdfColors.white : color),
        );

    PdfColor statusColor(DoseStatus s) => switch (s) {
          DoseStatus.given => PdfColor.fromInt(0xFF2E7D4F),
          DoseStatus.overdue => PdfColor.fromInt(0xFFC0392B),
          DoseStatus.due => _blue,
          DoseStatus.upcoming => PdfColors.grey800,
          DoseStatus.notEligible => PdfColor.fromInt(0xFFB7791F),
        };

    final rows = <pw.TableRow>[
      pw.TableRow(children: [
        cell(ar ? 'المرحلة' : 'Milestone', head: true),
        cell(ar ? 'اللقاح' : 'Vaccine', head: true),
        cell(ar ? 'الموعد' : 'Due', head: true),
        cell(ar ? 'تاريخ الإعطاء' : 'Given', head: true),
        cell(ar ? 'الحالة' : 'Status', head: true),
      ]),
    ];
    var shade = false;
    var lastMilestone = -1;
    for (final d in schedule.doses) {
      if (d.rule.milestone != lastMilestone) {
        shade = !shade;
        lastMilestone = d.rule.milestone;
      }
      final m = RuleSet.milestone(d.rule.milestone);
      rows.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: shade ? _soft : PdfColors.white),
        children: [
          cell(ar ? m.ar : m.en),
          cell(d.rule.label(lang)),
          cell(d.status == DoseStatus.notEligible ? '-' : fmt(d.dueDate)),
          cell(d.givenDate == null ? '' : fmt(d.givenDate)),
          cell(XlsxExport.statusLabel(d.status), color: statusColor(d.status)),
        ],
      ));
    }
    for (final c in campaignDoses) {
      rows.add(pw.TableRow(children: [
        cell(t('campaign_dose')),
        cell(c.campaignName ?? ''),
        cell(''),
        cell(fmt(c.givenDate)),
        cell(t('st_given')),
      ]));
    }

    final columnWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.3),
      1: const pw.FlexColumnWidth(2.4),
      2: const pw.FlexColumnWidth(1.2),
      3: const pw.FlexColumnWidth(1.2),
      4: const pw.FlexColumnWidth(1.1),
    };

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 22),
      textDirection: dir,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          txt(ar ? 'الجمهورية اليمنية - وزارة الصحة العامة والسكان' : 'Republic of Yemen - Ministry of Public Health & Population',
              size: 11, b: true, align: pw.TextAlign.center),
          txt(ar ? 'البرنامج الوطني للتحصين الموسع' : 'Expanded Programme on Immunization (EPI)',
              size: 11, b: true, align: pw.TextAlign.center, color: _blue),
          pw.SizedBox(height: 4),
          txt(ar ? 'بطاقة التحصين' : 'Immunization Card', size: 16, b: true, align: pw.TextAlign.center),
          pw.Container(height: 2.5, margin: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 200), color: _orange),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(
                child: pw.Column(children: [
                  field(t('child_id'), child.id),
                  field(t('child_name'), child.name),
                  if (!ar && (child.nameLatin ?? '').isNotEmpty) field('Name (Latin)', child.nameLatin!),
                  field(t('sex'), child.sex == 'M' ? t('male') : t('female')),
                  field(t('dob'), fmt(child.dob)),
                  field(t('birth_weight'), child.birthWeight == null ? '' : '${child.birthWeight} g'),
                ]),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(children: [
                  field(t('guardian_name'), child.guardianName),
                  field(t('phone'), child.phone ?? ''),
                  field(t('governorate'), facility?.governorate ?? ''),
                  field(t('district'), facility?.district ?? ''),
                  field(t('facility'), facility == null ? '' : '${facility.name} (${facility.code})'),
                  field(t('area'), child.area ?? ''),
                ]),
              ),
            ]),
          ),
          pw.SizedBox(height: 8),
          pw.Table(border: pw.TableBorder.all(color: _line, width: 0.5), columnWidths: columnWidths, children: rows),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFFCEDE4), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              txt(ar ? 'تنبيه' : 'Clinical notice', b: true, size: 10),
              txt(
                ar
                    ? 'احتفظوا بهذه البطاقة وأحضروها في كل زيارة. التزموا بمواعيد التطعيم لحماية طفلكم. (نص مبدئي إلى حين اعتماد النص الرسمي من البرنامج)'
                    : 'Keep this card and bring it to every visit. Keep to the vaccination dates to protect your child. (Provisional text pending the official EPI notice.)',
                size: 9,
              ),
            ]),
          ),
          pw.Spacer(),
          pw.Divider(color: _line, thickness: 0.5),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            txt('${t('next_visit')}: ${fmt(schedule.nextVisit)}', size: 10, b: true, color: _blue),
            txt('${t('rule_version')}: ${schedule.ruleVersion}  |  ${fmt(today())}', size: 8.5, color: PdfColors.grey700),
          ]),
        ],
      ),
    ));
    return doc.save();
  }
}
