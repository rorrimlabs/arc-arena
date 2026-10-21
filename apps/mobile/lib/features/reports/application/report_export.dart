/// Writes an [ArenaReport] to a real `.xlsx` workbook (brief §13).
///
/// The workbook is generated from the **same** [ArenaReport] the screen is
/// showing, so the export can never disagree with what staff just read, and
/// both trace back to the persisted rows. Money is written as rupees with two
/// decimals, converted once from integer paise.
library;

import 'dart:io';

import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/reports/report_models.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';

/// Paise → rupees, for a spreadsheet cell that should still be a number.
double _rupees(int paise) => paise / 100.0;

String _statusLabel(PaymentStatus s) => switch (s) {
      PaymentStatus.paid => 'Paid',
      PaymentStatus.partial => 'Partial',
      PaymentStatus.unpaid => 'Pending',
      PaymentStatus.waived => 'Waived',
    };

class ReportExporter {
  const ReportExporter();

  /// Builds the workbook bytes. Pure apart from the `excel` encoder, so it can
  /// be asserted on in a test without touching the file system.
  List<int> buildWorkbook(ArenaReport report) {
    final book = Excel.createExcel();
    // Excel always starts with one sheet; rename it rather than leaving an
    // empty "Sheet1" behind.
    final firstName = book.getDefaultSheet()!;
    book.rename(firstName, 'Summary');

    _summary(book['Summary'], report);
    _byDay(book['By day'], report);
    _breakdown(book['Revenue'], report);
    _usage(book['Stations'], report);
    _games(book['Games'], report);
    _history(book['Sessions'], report);

    return book.encode() ?? const <int>[];
  }

  /// Writes the workbook to a file and returns it.
  Future<File> writeToFile(ArenaReport report, {Directory? directory}) async {
    final dir = directory ?? await getApplicationDocumentsDirectory();
    final stamp = '${report.range.from.iso}_${report.range.to.iso}';
    final file = File('${dir.path}/arena-report-$stamp.xlsx');
    await file.writeAsBytes(buildWorkbook(report), flush: true);
    return file;
  }

  // --- sheets ----------------------------------------------------------------

  void _row(Sheet sheet, List<CellValue?> cells) =>
      sheet.appendRow(cells);

  void _summary(Sheet sheet, ArenaReport r) {
    _row(sheet, [TextCellValue('404 Arena — report')]);
    _row(sheet, [
      TextCellValue('Period'),
      TextCellValue(r.range.label),
      TextCellValue('${r.range.from.iso} to ${r.range.to.iso}'),
    ]);
    _row(sheet, []);
    _row(sheet, [TextCellValue('Measure'), TextCellValue('Value')]);
    _row(sheet, [TextCellValue('Billed (₹)'), DoubleCellValue(_rupees(r.billedPaise))]);
    _row(sheet,
        [TextCellValue('Collected (₹)'), DoubleCellValue(_rupees(r.collectedPaise))]);
    _row(sheet,
        [TextCellValue('Pending (₹)'), DoubleCellValue(_rupees(r.pendingPaise))]);
    _row(sheet, [TextCellValue('Waived (₹)'), DoubleCellValue(_rupees(r.waivedPaise))]);
    _row(sheet,
        [TextCellValue('Refunded (₹)'), DoubleCellValue(_rupees(r.refundedPaise))]);
    _row(sheet, [TextCellValue('Sessions'), IntCellValue(r.sessionCount)]);
    _row(sheet, [
      TextCellValue('Gaming hours'),
      DoubleCellValue(double.parse(r.gamingHours.toStringAsFixed(2))),
    ]);
    _row(sheet, [TextCellValue('Customers served'), IntCellValue(r.uniqueCustomers)]);
    _row(sheet, [TextCellValue('New customers'), IntCellValue(r.newCustomers)]);
    _row(sheet, [
      TextCellValue('Average utilisation (%)'),
      DoubleCellValue(
          double.parse((r.averageUtilisation * 100).toStringAsFixed(1))),
    ]);
  }

  void _byDay(Sheet sheet, ArenaReport r) {
    _row(sheet, [
      TextCellValue('Date'),
      TextCellValue('Billed (₹)'),
      TextCellValue('Collected (₹)'),
      TextCellValue('Sessions'),
      TextCellValue('Gaming hours'),
    ]);
    for (final d in r.byDay) {
      _row(sheet, [
        TextCellValue(d.day.iso),
        DoubleCellValue(_rupees(d.billedPaise)),
        DoubleCellValue(_rupees(d.collectedPaise)),
        IntCellValue(d.sessions),
        DoubleCellValue(double.parse((d.gamingMinutes / 60).toStringAsFixed(2))),
      ]);
    }
  }

  void _breakdown(Sheet sheet, ArenaReport r) {
    _row(sheet, [TextCellValue('Revenue by activity')]);
    _row(sheet, [
      TextCellValue('Activity'),
      TextCellValue('Amount (₹)'),
      TextCellValue('Charges'),
    ]);
    for (final m in r.byActivity) {
      _row(sheet, [
        TextCellValue(m.label),
        DoubleCellValue(_rupees(m.paise)),
        IntCellValue(m.count),
      ]);
    }
    _row(sheet, []);
    _row(sheet, [TextCellValue('Collected by payment method')]);
    _row(sheet, [
      TextCellValue('Method'),
      TextCellValue('Amount (₹)'),
      TextCellValue('Payments'),
    ]);
    for (final m in r.byMethod) {
      _row(sheet, [
        TextCellValue(m.label),
        DoubleCellValue(_rupees(m.paise)),
        IntCellValue(m.count),
      ]);
    }
    _row(sheet, []);
    _row(sheet, [TextCellValue('Revenue by price band')]);
    _row(sheet, [
      TextCellValue('Band'),
      TextCellValue('Amount (₹)'),
      TextCellValue('Charges'),
    ]);
    for (final m in r.byBand) {
      _row(sheet, [
        TextCellValue(m.label),
        DoubleCellValue(_rupees(m.paise)),
        IntCellValue(m.count),
      ]);
    }
  }

  void _usage(Sheet sheet, ArenaReport r) {
    _row(sheet, [
      TextCellValue('Station'),
      TextCellValue('Hours played'),
      TextCellValue('Open hours'),
      TextCellValue('Utilisation (%)'),
      TextCellValue('Sessions'),
    ]);
    for (final u in r.resourceUsage) {
      _row(sheet, [
        TextCellValue(u.resourceName),
        DoubleCellValue(double.parse(u.playedHours.toStringAsFixed(2))),
        DoubleCellValue(double.parse((u.openMinutes / 60).toStringAsFixed(2))),
        DoubleCellValue(double.parse((u.utilisation * 100).toStringAsFixed(1))),
        IntCellValue(u.sessions),
      ]);
    }
  }

  void _games(Sheet sheet, ArenaReport r) {
    _row(sheet, [
      TextCellValue('Game'),
      TextCellValue('Hours played'),
      TextCellValue('Sessions'),
    ]);
    for (final g in r.topGames) {
      _row(sheet, [
        TextCellValue(g.gameName),
        DoubleCellValue(double.parse(g.playedHours.toStringAsFixed(2))),
        IntCellValue(g.sessions),
      ]);
    }
  }

  void _history(Sheet sheet, ArenaReport r) {
    _row(sheet, [
      TextCellValue('Started'),
      TextCellValue('Ended'),
      TextCellValue('Customer'),
      TextCellValue('Type'),
      TextCellValue('Stations'),
      TextCellValue('Games'),
      TextCellValue('Minutes'),
      TextCellValue('Billed (₹)'),
      TextCellValue('Collected (₹)'),
      TextCellValue('Pending (₹)'),
      TextCellValue('Status'),
    ]);
    for (final h in r.history) {
      _row(sheet, [
        TextCellValue(_stamp(h.startedAt)),
        TextCellValue(h.endedAt == null ? '' : _stamp(h.endedAt!)),
        TextCellValue(h.customerName),
        TextCellValue(h.isGroup ? 'Group' : 'Single'),
        TextCellValue(h.resources.join(', ')),
        TextCellValue(h.games.join(', ')),
        IntCellValue(h.playedMinutes),
        DoubleCellValue(_rupees(h.billedPaise)),
        DoubleCellValue(_rupees(h.collectedPaise)),
        DoubleCellValue(_rupees(h.pendingPaise)),
        TextCellValue(_statusLabel(h.paymentStatus)),
      ]);
    }
  }

  /// `2026-10-10 19:20` in IST — the timezone staff and the owner work in.
  String _stamp(DateTime utc) {
    final t = IstTime.fromUtc(utc);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
