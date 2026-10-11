/// Seed catalog: realistic Malaysian kedai items with SST flags.
///
/// SST treatment here follows the common service-tax practice for a kedai:
/// prepared food & drinks served for immediate consumption are taxable at
/// 8% in a cafe setting, while packaged grocery essentials (bottled water,
/// instant noodles, canned drinks, rice) are zero-rated. The flags are
/// per-item and configurable — that is the point of the design.
library;

import '../domain/money.dart';
import '../domain/cart.dart';

List<Product> seedCatalog() => const [
  Product(
    id: 'nasi-lemak',
    name: 'Nasi Lemak',
    unitPrice: Money(650),
    taxPercent: 8,
  ),
  Product(
    id: 'milo-ais',
    name: 'Milo Ais',
    unitPrice: Money(320),
    taxPercent: 8,
  ),
  Product(id: 'kopi-o', name: 'Kopi O', unitPrice: Money(250), taxPercent: 8),
  Product(
    id: 'teh-tarik',
    name: 'Teh Tarik',
    unitPrice: Money(300),
    taxPercent: 8,
  ),
  Product(
    id: 'roti-can',
    name: 'Roti Can',
    unitPrice: Money(250),
    taxPercent: 8,
  ),
  Product(
    id: 'mee-goreng',
    name: 'Mee Goreng',
    unitPrice: Money(700),
    taxPercent: 8,
  ),
  Product(
    id: 'indomie',
    name: 'Indomie Kuah',
    unitPrice: Money(310),
    taxPercent: 0,
  ),
  Product(
    id: 'air-mineral',
    name: 'Mineral Water 500ml',
    unitPrice: Money(100),
    taxPercent: 0,
  ),
  Product(
    id: 'milo-kotak',
    name: 'Milo Kotak',
    unitPrice: Money(350),
    taxPercent: 0,
  ),
  Product(
    id: 'telur-seping',
    name: 'Telur Seping',
    unitPrice: Money(550),
    taxPercent: 0,
  ),
  Product(
    id: 'kopi-instant',
    name: 'Kopi Sachet (5)',
    unitPrice: Money(450),
    taxPercent: 0,
  ),
  Product(
    id: 'keropok',
    name: 'Keropok Lekor 100g',
    unitPrice: Money(500),
    taxPercent: 0,
  ),
];
