import 'dart:typed_data';

import '../core/dates.dart';
import '../core/i18n.dart';
import '../data/models.dart';
import '../domain/engine.dart';
import '../domain/rules.dart';
import 'zip_writer.dart';

/// Builds a standards-compliant single-sheet .xlsx for one child
/// (FRS-DOC-01..03). Strings are inline, so no shared-strings part is needed.
class XlsxExport {
  static String statusLabel(DoseStatus s) => switch (s) {
        DoseStatus.given => t('st_given'),
        DoseStatus.due => t('st_due'),
        DoseStatus.overdue => t('st_overdue'),
        DoseStatus.upcoming => t('st_upcoming'),
        DoseStatus.notEligible => t('st_noelig'),
      };

  static Uint8List build({
    required Child child,
    required Facility? facility,
    required Schedule schedule,
    required List<DoseRecord> campaignDoses,
    required String user,
  }) {
    final lang = Lang.current.value;
    final rows = <List<_Cell>>[];
    void row(List<Object?> values, {bool bold = false}) =>
        rows.add([for (final v in values) _Cell(v == null ? '' : '$v', bold)]);

    row([lang == 'ar' ? 'الجمهورية اليمنية - وزارة الصحة العامة والسكان' : 'Republic of Yemen - Ministry of Public Health & Population'], bold: true);
    row([lang == 'ar' ? 'البرنامج الوطني للتحصين الموسع' : 'Expanded Programme on Immunization (EPI)'], bold: true);
    row([]);
    row([t('child_id'), child.id], bold: false);
    row([t('child_name'), child.name]);
    if ((child.nameLatin ?? '').isNotEmpty) row([t('child_name_latin'), child.nameLatin]);
    row([t('sex'), child.sex == 'M' ? t('male') : t('female')]);
    row([t('dob'), fmt(child.dob)]);
    row([t('birth_weight'), child.birthWeight]);
    row([t('governorate'), facility?.governorate]);
    row([t('district'), facility?.district]);
    row([t('facility'), facility == null ? '' : '${facility.name} (${facility.code})']);
    row([t('area'), child.area]);
    row([t('guardian_name'), child.guardianName]);
    row([t('phone'), child.phone]);
    row([]);
    row([
      lang == 'ar' ? 'المرحلة' : 'Milestone',
      lang == 'ar' ? 'اللقاح' : 'Vaccine',
      lang == 'ar' ? 'تاريخ الاستحقاق' : 'Due date',
      t('given_date'),
      lang == 'ar' ? 'الحالة' : 'Status',
    ], bold: true);
    for (final d in schedule.doses) {
      final m = RuleSet.milestone(d.rule.milestone);
      row([
        lang == 'ar' ? m.ar : m.en,
        d.rule.label(lang),
        d.status == DoseStatus.notEligible ? '-' : fmt(d.dueDate),
        d.givenDate == null ? '' : fmt(d.givenDate),
        statusLabel(d.status),
      ]);
    }
    for (final c in campaignDoses) {
      row([t('campaign_dose'), c.campaignName, '', fmt(c.givenDate), t('st_given')]);
    }
    row([]);
    row([t('rule_version'), schedule.ruleVersion]);
    row([lang == 'ar' ? 'تاريخ التصدير' : 'Exported on', fmt(today())]);
    row([lang == 'ar' ? 'المستخدم' : 'User', user]);

    final zip = ZipWriter()
      ..addString('[Content_Types].xml', _contentTypes)
      ..addString('_rels/.rels', _rootRels)
      ..addString('xl/workbook.xml', _workbook(lang == 'ar' ? 'سجل التطعيم' : 'Immunization'))
      ..addString('xl/_rels/workbook.xml.rels', _workbookRels)
      ..addString('xl/styles.xml', _styles)
      ..addString('xl/worksheets/sheet1.xml', _sheet(rows, rtl: lang == 'ar'));
    return zip.build();
  }

  static String esc(String s) {
    final clean = s.replaceAll(RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '');
    return clean
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String _col(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _sheet(List<List<_Cell>> rows, {required bool rtl}) {
    final b = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
      ..write('<sheetViews><sheetView workbookViewId="0"${rtl ? ' rightToLeft="1"' : ''}/></sheetViews>')
      ..write('<cols><col min="1" max="1" width="28" customWidth="1"/><col min="2" max="2" width="34" customWidth="1"/>'
          '<col min="3" max="5" width="16" customWidth="1"/></cols>')
      ..write('<sheetData>');
    for (var r = 0; r < rows.length; r++) {
      b.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        final cell = rows[r][c];
        if (cell.text.isEmpty) continue;
        b.write('<c r="${_col(c)}${r + 1}" t="inlineStr"${cell.bold ? ' s="1"' : ''}><is><t xml:space="preserve">${esc(cell.text)}</t></is></c>');
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  static String _workbook(String sheetName) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="${esc(sheetName)}" sheetId="1" r:id="rId1"/></sheets></workbook>';

  static const _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';

  static const _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  static const _workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  static const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>';
}

class _Cell {
  final String text;
  final bool bold;
  const _Cell(this.text, this.bold);
}
