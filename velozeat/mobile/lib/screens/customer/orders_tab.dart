import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'order_tracking_screen.dart';

class CustomerOrdersTab extends StatefulWidget {
  const CustomerOrdersTab({super.key});

  @override
  State<CustomerOrdersTab> createState() => _CustomerOrdersTabState();
}

class _CustomerOrdersTabState extends State<CustomerOrdersTab> {
  bool _loading = true;
  String? _error;
  List<Order> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _orders.isEmpty;
      _error = null;
    });
    try {
      final res = await context.read<AppState>().api.orders();
      final raw = res['orders'];
      setState(() {
        _orders = raw is List
            ? raw.whereType<Map<String, dynamic>>().map(Order.fromJson).toList()
            : [];
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _openOrder(Order order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderTrackingScreen(orderId: order.id, initialOrder: order),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = _orders.where((o) => o.isActive).toList();
    final history = _orders.where((o) => !o.isActive).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: kBrand,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text('Mis pedidos', style: Theme.of(context).textTheme.headlineMedium)),
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
              ],
            ),
            const SizedBox(height: 4),
            if (_loading)
              const LoadingBox(label: 'Cargando tus pedidos...')
            else if (_error != null)
              EmptyState(
                emoji: '',
                title: 'No pudimos cargar tus pedidos',
                subtitle: _error!,
                action: FilledButton(
                  onPressed: _load,
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 46)),
                  child: const Text('Reintentar'),
                ),
              )
            else if (_orders.isEmpty)
              const EmptyState(
                emoji: '',
                title: 'Aún no tienes pedidos',
                subtitle: 'Explora los restaurantes y pide tu primer antojo.',
              )
            else ...[
              if (active.isNotEmpty) ...[
                const SectionTitle('En curso'),
                const SizedBox(height: 8),
                ...active.map((order) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OrderCard(order: order, onTap: () => _openOrder(order), active: true),
                    )),
                const SizedBox(height: 14),
              ],
              if (history.isNotEmpty) ...[
                const SectionTitle('Historial'),
                const SizedBox(height: 8),
                ...history.map((order) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OrderCard(order: order, onTap: () => _openOrder(order), active: false),
                    )),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  final bool active;
  const _OrderCard({required this.order, required this.onTap, required this.active});

  @override
  Widget build(BuildContext context) {
    final itemsPreview = order.items.take(2).map((i) => '${i.qty}x ${i.name}').join(' · ');
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EmojiBox(emoji: order.restaurantEmoji, size: 44, color: colorFromHex(order.restaurantColor)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.restaurantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('#${order.code} · ${relativeTime(order.createdAt)}',
                        style: const TextStyle(fontSize: 11.5, color: kMuted)),
                  ],
                ),
              ),
              StatusPill(order.status, small: true),
            ],
          ),
          const SizedBox(height: 10),
          Text(itemsPreview + (order.items.length > 2 ? ' +${order.items.length - 2} más' : ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: kMuted)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(money(order.total),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: kInk)),
              const Spacer(),
              Text(active ? 'Ver seguimiento' : 'Ver detalle',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kBrand)),
              const SizedBox(width: 3),
              const Icon(Icons.arrow_forward_rounded, size: 15, color: kBrand),
            ],
          ),
        ],
      ),
    );
  }
}
