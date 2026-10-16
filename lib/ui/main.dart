import 'package:flutter/material.dart';

import '../app/pos_service.dart';
import '../data/catalog_seed.dart';
import '../data/store.dart';
import '../domain/cart.dart';
import '../domain/money.dart';
import '../domain/tax_engine.dart';
import 'day_close_screen.dart';
import 'receipt_screen.dart';

void main() => runApp(const KedaiPosApp());

class KedaiPosApp extends StatelessWidget {
  const KedaiPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KedaiPOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6366F1)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const PosHomePage(),
    );
  }
}

class PosHomePage extends StatefulWidget {
  const PosHomePage({super.key, this.initialRepository});

  /// Injectable for widget tests.
  final PosRepository? initialRepository;

  @override
  State<PosHomePage> createState() => _PosHomePageState();
}

class _PosHomePageState extends State<PosHomePage> {
  PosService? _service;
  final Cart _cart = Cart();
  List<Product> _products = const [];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final repo = widget.initialRepository ?? InMemoryStore();
    final service = await PosService.open(repo);
    final existing = await service.products();
    final products = existing.isEmpty ? seedCatalog() : existing;
    if (existing.isEmpty) {
      await repo.saveProducts(products);
    }
    if (!mounted) return;
    setState(() {
      _service = service;
      _products = products;
    });
  }

  Future<void> _checkout(TenderType tender) async {
    final service = _service;
    if (service == null || _cart.isEmpty) return;
    final receipt = await service.checkout(_cart, tender: tender);
    _cart.clear();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReceiptScreen(receipt: receipt)),
    );
  }

  void _openDayClose() async {
    final service = _service;
    if (service == null) return;
    final receipts = await service.receipts();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DayCloseScreen(receipts: receipts),
      ),
    );
  }

  Totals get _totals {
    final service = _service;
    return service == null
        ? const TaxEngine().price(_cart)
        : service.price(_cart);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('KedaiPOS'),
        actions: [
          IconButton(
            tooltip: 'Day close (Z-report)',
            onPressed: _service == null ? null : _openDayClose,
            icon: const Icon(Icons.calculate_outlined),
          ),
        ],
      ),
      body: _service == null
          ? const Center(child: CircularProgressIndicator())
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 170,
                          childAspectRatio: 1.05,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: _products.length,
                    itemBuilder: (context, index) {
                      final p = _products[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => setState(() => _cart.add(p)),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  p.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  p.unitPrice.toString(),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  p.taxPercent > 0
                                      ? 'SST ${p.taxPercent}%'
                                      : 'SST 0%',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: _CartPanel(
                    cart: _cart,
                    totals: _totals,
                    onQuantity: (id, qty) =>
                        setState(() => _cart.setQuantity(id, qty)),
                    onDiscount: (d) => setState(() {
                      if (d == null) {
                        _cart.clearDiscount();
                      } else {
                        _cart.applyDiscount(d);
                      }
                    }),
                    onCheckout: _checkout,
                  ),
                ),
              ],
            ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.totals,
    required this.onQuantity,
    required this.onDiscount,
    required this.onCheckout,
  });

  final Cart cart;
  final Totals totals;
  final void Function(String productId, int qty) onQuantity;
  final void Function(Discount? discount) onDiscount;
  final Future<void> Function(TenderType tender) onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: cart.isEmpty
              ? const Center(child: Text('Cart kosong'))
              : ListView(
                  children: [
                    for (final line in cart.lines)
                      ListTile(
                        dense: true,
                        title: Text(line.product.name),
                        subtitle: Text(
                          '${line.quantity} x ${line.product.unitPrice}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => onQuantity(
                                line.product.id,
                                line.quantity - 1,
                              ),
                            ),
                            Text('${line.quantity}'),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => onQuantity(
                                line.product.id,
                                line.quantity + 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ListTile(
                      dense: true,
                      title: const Text('Discount'),
                      trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'none', label: Text('—')),
                          ButtonSegment(value: '10%', label: Text('10%')),
                          ButtonSegment(value: 'RM1', label: Text('RM1')),
                        ],
                        selected: {
                          switch (cart.discount) {
                            PercentDiscount() => '10%',
                            FlatDiscount() => 'RM1',
                            _ => 'none',
                          },
                        },
                        showSelectedIcon: false,
                        onSelectionChanged: (sel) {
                          switch (sel.first) {
                            case '10%':
                              onDiscount(const PercentDiscount(10));
                            case 'RM1':
                              onDiscount(const FlatDiscount(Money(100)));
                            default:
                              onDiscount(null);
                          }
                        },
                      ),
                    ),
                  ],
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              _row(theme, 'Subtotal', totals.subtotal.toString()),
              if (totals.discount.isPositive)
                _row(theme, 'Discount', '-${totals.discount}'),
              for (final g in totals.taxGroups)
                if (g.percent > 0)
                  _row(theme, 'SST ${g.percent}%', g.tax.toString()),
              if (!totals.rounding.isZero)
                _row(theme, 'Rounding', totals.rounding.toString()),
              const SizedBox(height: 4),
              _row(theme, 'TOTAL', totals.total.toString(), bold: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: cart.isEmpty
                      ? null
                      : () => onCheckout(TenderType.cash),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Cash'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: cart.isEmpty
                      ? null
                      : () => onCheckout(TenderType.card),
                  icon: const Icon(Icons.credit_card),
                  label: const Text('Card'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    ThemeData theme,
    String label,
    String value, {
    bool bold = false,
  }) {
    final style = bold
        ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
