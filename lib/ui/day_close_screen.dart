import 'package:flutter/material.dart';

import '../domain/receipt.dart';

/// Day-close (Z-report) screen: aggregates today's receipts.
class DayCloseScreen extends StatelessWidget {
  const DayCloseScreen({super.key, required this.receipts, this.day});

  final List<Receipt> receipts;
  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final d = day ?? DateTime.now();
    final report = DayReport.forDay(receipts, d);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Day Close — Z-Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ringkasan Hari Ini',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _kv(theme, 'Receipts', '${report.receiptCount}'),
                  _kv(
                    theme,
                    'Gross sales',
                    report.grossSales.toStringWithSeparator(),
                  ),
                  _kv(
                    theme,
                    'Discounts',
                    '-${report.totalDiscount.toStringWithSeparator()}',
                  ),
                  if (report.sstByRate.isEmpty)
                    _kv(theme, 'SST collected', 'RM0.00'),
                  for (final e in report.sstByRate.entries)
                    _kv(
                      theme,
                      'SST ${e.key}%',
                      e.value.toStringWithSeparator(),
                    ),
                  _kv(
                    theme,
                    'Rounding adjustment',
                    report.totalRounding.toStringWithSeparator(),
                  ),
                  for (final e in report.byTender.entries)
                    _kv(
                      theme,
                      e.key.name[0].toUpperCase() + e.key.name.substring(1),
                      e.value.toStringWithSeparator(),
                    ),
                  const Divider(),
                  _kv(
                    theme,
                    'NET SALES',
                    report.netSales.toStringWithSeparator(),
                    bold: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(ThemeData theme, String label, String value, {bool bold = false}) {
    final style = bold
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
