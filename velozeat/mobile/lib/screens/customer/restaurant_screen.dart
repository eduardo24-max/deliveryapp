import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'cart_screen.dart';

class RestaurantScreen extends StatefulWidget {
  final String restaurantId;
  const RestaurantScreen({super.key, required this.restaurantId});

  @override
  State<RestaurantScreen> createState() => _RestaurantScreenState();
}

class _RestaurantScreenState extends State<RestaurantScreen> {
  Restaurant? _restaurant;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await context.read<AppState>().api.restaurant(widget.restaurantId);
      final raw = res['restaurant'];
      setState(() {
        _restaurant = raw is Map<String, dynamic> ? Restaurant.fromJson(raw) : null;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _openCart() {
    final app = context.read<AppState>();
    if (app.cartCount == 0 || app.cartRestaurant == null) {
      showSnack(context, 'Tu carrito está vacío.', error: true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CartScreen(restaurant: app.cartRestaurant!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final restaurant = _restaurant;
    final color = colorFromHex(restaurant?.color ?? '#FF6A00');
    final cartQty = (restaurant != null && app.cartRestaurant?.id == restaurant.id) ? app.cartCount : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(restaurant?.name ?? 'Restaurante'),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: _openCart,
                icon: const Icon(Icons.shopping_bag_outlined),
              ),
              if (app.cartCount > 0)
                Positioned(
                  right: 5,
                  top: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: kBrand, borderRadius: BorderRadius.circular(20)),
                    child: Text('${app.cartCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const LoadingBox(label: 'Abriendo el menú...')
          : _error != null
              ? EmptyState(
                  emoji: '',
                  title: 'No pudimos abrir el restaurante',
                  subtitle: _error!,
                  action: FilledButton(
                    onPressed: _load,
                    style: FilledButton.styleFrom(minimumSize: const Size(160, 46)),
                    child: const Text('Reintentar'),
                  ),
                )
              : restaurant == null
                  ? const EmptyState(emoji: '', title: 'Restaurante no disponible')
                  : RefreshIndicator(
                      color: kBrand,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [color.withValues(alpha: 0.18), Colors.white],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: kLine),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    EmojiBox(emoji: restaurant.emoji, size: 72, color: color),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(restaurant.name,
                                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kInk)),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.star_rounded, size: 16, color: kAccent),
                                              const SizedBox(width: 2),
                                              Text(restaurant.rating.toStringAsFixed(1),
                                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kInk)),
                                              Text(' (${restaurant.ratingCount}) · ${restaurant.category}',
                                                  style: const TextStyle(fontSize: 11.5, color: kMuted)),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              _MiniStat('', '${restaurant.etaMinutes} min'),
                                              const SizedBox(width: 10),
                                              _MiniStat('', 'Envío desde ${money(restaurant.deliveryFee)}'),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(restaurant.description,
                                    style: const TextStyle(fontSize: 12.5, color: kMuted, height: 1.4)),
                                const SizedBox(height: 8),
                                InfoRow(Icons.location_on_outlined, restaurant.address),
                                if (!restaurant.isOpen)
                                  Container(
                                    margin: const EdgeInsets.only(top: 6),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: kRed.withValues(alpha: 0.07),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.schedule_rounded, size: 16, color: kRed),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text('Este restaurante está cerrado. Vuelve más tarde.',
                                              style: TextStyle(fontSize: 12, color: kRed, fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text('Menú', style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 4),
                          Text('${restaurant.menu.where((m) => m.available).length} platillos disponibles',
                              style: const TextStyle(fontSize: 12.5, color: kMuted)),
                          const SizedBox(height: 12),
                          ..._buildMenu(restaurant, app, color),
                        ],
                      ),
                    ),
      bottomNavigationBar: cartQty > 0 && restaurant != null
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: FilledButton(
                  onPressed: _openCart,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: Text('$cartQty',
                            style: const TextStyle(color: kBrand, fontWeight: FontWeight.w900, fontSize: 12)),
                      ),
                      const SizedBox(width: 10),
                      const Text('Ver carrito'),
                      const Spacer(),
                      Text(money(app.cartSubtotal), style: const TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }

  List<Widget> _buildMenu(Restaurant restaurant, AppState app, Color color) {
    final groups = <String, List<MenuItem>>{};
    for (final item in restaurant.menu.where((m) => m.available)) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    if (groups.isEmpty) {
      return [
        const EmptyState(
          emoji: '',
          title: 'Menú en preparación',
          subtitle: 'Este restaurante todavía no publica platillos.',
        ),
      ];
    }

    final widgets = <Widget>[];
    groups.forEach((category, items) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(category.toUpperCase(),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: kMuted, letterSpacing: 0.8)),
      ));
      for (final item in items) {
        final qty = app.qtyOf(item.id);
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SurfaceCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  EmojiBox(emoji: item.emoji, size: 48, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kInk)),
                        if (item.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(item.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: kMuted, height: 1.3)),
                        ],
                        const SizedBox(height: 5),
                        Text(money(item.price),
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: kBrand)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (qty == 0)
                    _AddButton(
                      enabled: restaurant.isOpen,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        app.addToCart(restaurant, item);
                      },
                    )
                  else
                    _QtyControl(
                      qty: qty,
                      onMinus: () => app.decreaseCart(item),
                      onPlus: () => app.addToCart(restaurant, item),
                    ),
                ],
              ),
            ),
          ),
        );
      }
    });
    return widgets;
  }
}

class _MiniStat extends StatelessWidget {
  final String emoji;
  final String text;
  const _MiniStat(this.emoji, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _AddButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? kBrand : kLine,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.add_rounded, color: enabled ? Colors.white : kMuted, size: 22),
        ),
      ),
    );
  }
}

class _QtyControl extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _QtyControl({required this.qty, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: kLine),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(Icons.remove_rounded, onMinus),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('$qty', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: kInk)),
          ),
          _button(Icons.add_rounded, onPlus),
        ],
      ),
    );
  }

  Widget _button(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: SizedBox(
        width: 32,
        height: 34,
        child: Icon(icon, size: 18, color: kBrand),
      ),
    );
  }
}
