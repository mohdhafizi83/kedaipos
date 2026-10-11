import 'package:flutter/material.dart';

import '../domain/receipt.dart';

/// Printable-style receipt preview rendered from the same text renderer the
/// CLI demo uses — one source of truth for receipt layout.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final text = renderReceiptText(receipt);
    return Scaffold(
      appBar: AppBar(title: Text(receipt.number)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
