import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class RestaurantShell extends StatefulWidget {
  const RestaurantShell({super.key});

  @override
  State<RestaurantShell> createState() => _RestaurantShellState();
}

class _RestaurantShellState extends State<RestaurantShell> {
  int _index = 0;
  bool _loading = true;
  String? _error;
  Restaurant? _restaurant;
  Map<String, dynamic> _stats = {};
  List<Order> _active = [];
  List<Order> _recent = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _restaurant == null;
        _error = null;
      });
    }
    try {
      final res = await context.read<AppState>().api.restaurantDashboard();
      final rawRestaurant = res['restaurant'];
      final rawStats = res['stats'];
      final rawActive = res['activeOrders'];
      final rawRecent = res['recentOrders'];
      if (!mounted) return;
      setState(() {
        if (rawRestaurant is Map<String, dynamic>) _restaurant = Restaurant.fromJson(rawRestaurant);
        _stats = rawStats is Map<String, dynamic> ? rawStats : {};
        _active = rawActive is List
            ? rawActive.whereType<Map<String, dynamic>>().map(Order.fromJson).toList()
            : [];
        _recent = rawRecent is List
            ? rawRecent.whereType<Map<String, dynamic>>().map(Order.fromJson).toList()
            : [];
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!silent && mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    try {
      final res = await action();
      await _load(silent: true);
      if (mounted) showSnack(context, (res['message'] ?? 'Listo').toString());
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _toggleOpen(bool value) async {
    final restaurant = _restaurant;
    if (restaurant == null) return;
    await _run(() => context.read<AppState>().api.updateRestaurant(restaurant.id, {'isOpen': value}));
  }

  Future<void> _editRestaurant() async {
    final restaurant = _restaurant;
    if (restaurant == null) return;
    final name = TextEditingController(text: restaurant.name);
    final description = TextEditingController(text: restaurant.description);
    final address = TextEditingController(text: restaurant.address);
    final deliveryFee = TextEditingController(text: restaurant.deliveryFee.toStringAsFixed(0));
    final minOrder = TextEditingController(text: restaurant.minOrder.toStringAsFixed(0));
    final eta = TextEditingController(text: restaurant.etaMinutes.toString());

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Editar restaurante'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 10),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Dirección')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: deliveryFee,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Envío \$'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: minOrder,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Mínimo \$'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: eta,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tiempo estimado (min)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 42)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (save == true && mounted) {
      await _run(() => context.read<AppState>().api.updateRestaurant(restaurant.id, {
            'name': name.text.trim(),
            'description': description.text.trim(),
            'address': address.text.trim(),
            'deliveryFee': double.tryParse(deliveryFee.text) ?? restaurant.deliveryFee,
            'minOrder': double.tryParse(minOrder.text) ?? restaurant.minOrder,
            'etaMinutes': int.tryParse(eta.text) ?? restaurant.etaMinutes,
          }));
    }
    name.dispose();
    description.dispose();
    address.dispose();
    deliveryFee.dispose();
    minOrder.dispose();
    eta.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = _restaurant;
    if (_loading && restaurant == null) return const Scaffold(body: LoadingBox(label: 'Abriendo tu restaurante...'));
    if (_error != null && restaurant == null) {
      return Scaffold(
        body: EmptyState(
          emoji: '📡',
          title: 'No pudimos cargar tu panel',
          subtitle: _error!,
          action: FilledButton(
            onPressed: () => _load(),
            style: FilledButton.styleFrom(minimumSize: const Size(160, 46)),
            child: const Text('Reintentar'),
          ),
        ),
      );
    }
    if (restaurant == null) {
      return const Scaffold(body: EmptyState(emoji: '🍽️', title: 'Restaurante no encontrado'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(restaurant.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(restaurant.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5)),
                  Text(
                    restaurant.approved
                        ? (restaurant.isOpen ? 'Abierto · recibiendo pedidos' : 'Cerrado')
                        : 'En revisión por VelozEat',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: restaurant.approved ? (restaurant.isOpen ? kGreen : kMuted) : kBrand,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: () => _load(), icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          _OrdersTab(
            orders: _active,
            onAccept: (id) => _run(() => context.read<AppState>().api.acceptOrder(id)),
            onPrepare: (id) => _run(() => context.read<AppState>().api.prepareOrder(id)),
            onReady: (id) => _run(() => context.read<AppState>().api.readyOrder(id)),
            onRefresh: _load,
            onOpenMenu: () => setState(() => _index = 1),
          ),
          _MenuTab(
            restaurant: restaurant,
            onAdd: () => _editMenuItem(null),
            onEdit: (item) => _editMenuItem(item),
            onToggle: (item, value) => _run(() =>
                context.read<AppState>().api.updateMenuItem(restaurant.id, item.id, {'available': value})),
            onDelete: (item) => _deleteMenuItem(item),
          ),
          _PanelTab(
            restaurant: restaurant,
            stats: _stats,
            recent: _recent,
            onToggleOpen: _toggleOpen,
            onEdit: _editRestaurant,
            onRefresh: _load,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _active.isNotEmpty,
              backgroundColor: kBrand,
              label: Text('${_active.length}'),
              child: const Icon(Icons.receipt_long_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _active.isNotEmpty,
              backgroundColor: kBrand,
              label: Text('${_active.length}'),
              child: const Icon(Icons.receipt_long_rounded),
            ),
            label: 'Pedidos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Menú',
          ),
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Panel',
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMenuItem(MenuItem item) async {
    final restaurant = _restaurant;
    if (restaurant == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Eliminar platillo'),
        content: Text('¿Quieres quitar "${item.name}" de tu menú?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: kRed, minimumSize: const Size(100, 42)),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() => context.read<AppState>().api.deleteMenuItem(restaurant.id, item.id));
    }
  }

  Future<void> _editMenuItem(MenuItem? item) async {
    final restaurant = _restaurant;
    if (restaurant == null) return;

    final name = TextEditingController(text: item?.name ?? '');
    final description = TextEditingController(text: item?.description ?? '');
    final price = TextEditingController(text: item == null ? '' : item.price.toStringAsFixed(0));
    final category = TextEditingController(text: item?.category ?? 'Menú');
    String emoji = item?.emoji ?? '🍽️';
    bool available = item?.available ?? true;

    const emojis = ['🍽️', '🌮', '🍔', '🍕', '🍣', '🍜', '🥗', '🍟', '🍗', '🥤', '🍺', '☕', '🍰', '🍩', '🍦', '🥩', '🫔', '🍱', '🌯', '🧀'];

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text(item == null ? 'Nuevo platillo' : 'Editar platillo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre')),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: price,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Precio \$'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: category,
                        decoration: const InputDecoration(labelText: 'Categoría'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Ícono',
                      style: TextStyle(fontSize: 11.5, color: kMuted.withValues(alpha: 0.9), fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: emojis.map((e) {
                    final active = e == emoji;
                    return GestureDetector(
                      onTap: () => setDialogState(() => emoji = e),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: active ? kBrand.withValues(alpha: 0.12) : kBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: active ? kBrand : kLine),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 18)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Disponible', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  value: available,
                  activeTrackColor: kBrand,
                  onChanged: (value) => setDialogState(() => available = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(minimumSize: const Size(100, 42)),
              child: Text(item == null ? 'Agregar' : 'Guardar'),
            ),
          ],
        ),
      ),
    );

    if (save == true && mounted) {
      final data = {
        'name': name.text.trim(),
        'description': description.text.trim(),
        'price': double.tryParse(price.text) ?? 0,
        'category': category.text.trim(),
        'emoji': emoji,
        'available': available,
      };
      if (item == null) {
        await _run(() => context.read<AppState>().api.addMenuItem(restaurant.id, data));
      } else {
        await _run(() => context.read<AppState>().api.updateMenuItem(restaurant.id, item.id, data));
      }
    }

    name.dispose();
    description.dispose();
    price.dispose();
    category.dispose();
  }
}

class _OrdersTab extends StatelessWidget {
  final List<Order> orders;
  final void Function(String id) onAccept;
  final void Function(String id) onPrepare;
  final void Function(String id) onReady;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenMenu;

  const _OrdersTab({
    required this.orders,
    required this.onAccept,
    required this.onPrepare,
    required this.onReady,
    required this.onRefresh,
    required this.onOpenMenu,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: kBrand,
      onRefresh: onRefresh,
      child: orders.isEmpty
          ? ListView(
              children: [
                const SizedBox(height: 70),
                EmptyState(
                  emoji: '🧾',
                  title: 'No hay pedidos activos',
                  subtitle: 'Los pedidos nuevos aparecen aquí automáticamente cada 5 segundos.',
                  action: OutlinedButton(
                    onPressed: onOpenMenu,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(180, 46)),
                    child: const Text('Revisar mi menú'),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                Text('Pedidos activos', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text('${orders.length} en curso · se actualiza automáticamente',
                    style: const TextStyle(fontSize: 12.5, color: kMuted)),
                const SizedBox(height: 14),
                ...orders.map((order) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RestaurantOrderCard(
                        order: order,
                        onAccept: () => onAccept(order.id),
                        onPrepare: () => onPrepare(order.id),
                        onReady: () => onReady(order.id),
                      ),
                    )),
              ],
            ),
    );
  }
}

class _RestaurantOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onAccept;
  final VoidCallback onPrepare;
  final VoidCallback onReady;

  const _RestaurantOrderCard({
    required this.order,
    required this.onAccept,
    required this.onPrepare,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    final (label, callback, color) = switch (order.status) {
      'pending' => ('Aceptar pedido', onAccept, kBrand),
      'accepted' => ('Empezar preparación', onPrepare, kBlue),
      'preparing' => ('Marcar como listo', onReady, const Color(0xFF7C3AED)),
      _ => ('', null, kMuted),
    };

    return SurfaceCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${order.code}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Text(relativeTime(order.createdAt), style: const TextStyle(fontSize: 11, color: kMuted)),
              const Spacer(),
              StatusPill(order.status, small: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 15, color: kMuted),
              const SizedBox(width: 5),
              Text(order.customerName, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              if (order.customerPhone.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text('· ${order.customerPhone}', style: const TextStyle(fontSize: 11.5, color: kMuted)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          InfoRow(Icons.location_on_outlined, order.address),
          if (order.distanceKm > 0)
            InfoRow(Icons.route_rounded, '${order.distanceKm.toStringAsFixed(1)} km · ${order.zoneName}'),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: order.items
                  .map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text('${item.qty}x', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: kBrand)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('${item.emoji} ${item.name}',
                                  style: const TextStyle(fontSize: 12, color: kInk)),
                            ),
                            Text(money(item.price * item.qty), style: const TextStyle(fontSize: 11.5, color: kMuted)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            InfoRow(Icons.sticky_note_2_outlined, 'Nota: ${order.notes}', color: kBrand),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (order.paymentMethod == 'cash')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: kGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('💵 Efectivo',
                      style: TextStyle(fontSize: 10.5, color: kGreen, fontWeight: FontWeight.w800)),
                ),
              const Spacer(),
              Text(money(order.total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
          if (callback != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: callback,
                style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(46)),
                child: Text(label),
              ),
            ),
          ] else if (order.status == 'ready')
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.timer_outlined, size: 15, color: Color(0xFF0D9488)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Pedido listo. Esperando que un repartidor lo recoja.',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF0D9488), fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MenuTab extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onAdd;
  final void Function(MenuItem item) onEdit;
  final void Function(MenuItem item, bool value) onToggle;
  final void Function(MenuItem item) onDelete;

  const _MenuTab({
    required this.restaurant,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 90),
          children: [
            Text('Mi menú', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('${restaurant.menu.length} platillos · ${restaurant.menu.where((m) => m.available).length} disponibles',
                style: const TextStyle(fontSize: 12.5, color: kMuted)),
            const SizedBox(height: 16),
            if (restaurant.menu.isEmpty)
              const EmptyState(
                emoji: '📋',
                title: 'Tu menú está vacío',
                subtitle: 'Agrega tu primer platillo para empezar a recibir pedidos.',
              )
            else
              ...restaurant.menu.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          EmojiBox(emoji: item.emoji, size: 48, color: colorFromHex(restaurant.color)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                                Text(item.category, style: const TextStyle(fontSize: 10.5, color: kMuted)),
                                const SizedBox(height: 3),
                                Text(money(item.price),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: kBrand)),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              Switch(
                                value: item.available,
                                activeTrackColor: kBrand,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                onChanged: (value) => onToggle(item, value),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () => onEdit(item),
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(Icons.edit_outlined, size: 17, color: kMuted),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => onDelete(item),
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(Icons.delete_outline_rounded, size: 17, color: kRed),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
        Positioned(
          right: 18,
          bottom: 18,
          child: FloatingActionButton.extended(
            onPressed: onAdd,
            backgroundColor: kBrand,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Agregar platillo', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }
}

class _PanelTab extends StatelessWidget {
  final Restaurant restaurant;
  final Map<String, dynamic> stats;
  final List<Order> recent;
  final Future<void> Function(bool value) onToggleOpen;
  final VoidCallback onEdit;
  final Future<void> Function() onRefresh;

  const _PanelTab({
    required this.restaurant,
    required this.stats,
    required this.recent,
    required this.onToggleOpen,
    required this.onEdit,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final ordersToday = asInt(stats['ordersToday']);
    final salesToday = asDouble(stats['salesToday']);
    final commission = asDouble(stats['commissionToday']);
    final menuCount = asInt(stats['menuCount']);

    return RefreshIndicator(
      color: kBrand,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          if (!restaurant.approved)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kBrand.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBrand.withValues(alpha: 0.25)),
              ),
              child: const Row(
                children: [
                  Text('⏳', style: TextStyle(fontSize: 24)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tu restaurante está en revisión. El equipo VelozEat lo aprobará pronto para que aparezca en la app.',
                      style: TextStyle(fontSize: 12, color: kBrand, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kInk, Color(0xFF2C303A)]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restaurant.isOpen ? 'Recibiendo pedidos' : 'Restaurante cerrado',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        restaurant.approved
                            ? (restaurant.isOpen
                                ? 'Los clientes pueden ordenar ahora.'
                                : 'Activa el interruptor para abrir.')
                            : 'Esperando aprobación de VelozEat.',
                        style: const TextStyle(color: Colors.white60, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: restaurant.isOpen,
                  activeTrackColor: kGreen,
                  onChanged: restaurant.approved ? (value) => onToggleOpen(value) : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.65,
            children: [
              _StatCard(emoji: '🧾', label: 'Pedidos hoy', value: '$ordersToday'),
              _StatCard(emoji: '💵', label: 'Ventas hoy', value: money(salesToday)),
              _StatCard(emoji: '⚡', label: 'Comisión VelozEat', value: money(commission)),
              _StatCard(emoji: '📋', label: 'Platillos', value: '$menuCount'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Text('Mi restaurante', style: Theme.of(context).textTheme.titleLarge)),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(foregroundColor: kBrand),
                child: const Text('Editar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              ),
            ],
          ),
          SurfaceCard(
            child: Column(
              children: [
                InfoRow(Icons.storefront_outlined, '${restaurant.emoji} ${restaurant.name} · ${restaurant.category}'),
                InfoRow(Icons.star_rounded, '${restaurant.rating.toStringAsFixed(1)} (${restaurant.ratingCount} reseñas)',
                    color: kAccent),
                InfoRow(Icons.location_on_outlined, restaurant.address),
                InfoRow(Icons.two_wheeler_outlined,
                    'Envío ${money(restaurant.deliveryFee)} · Mínimo ${money(restaurant.minOrder)} · ${restaurant.etaMinutes} min'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionTitle('Pedidos recientes', action: '${recent.length}'),
          const SizedBox(height: 6),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('Aún no hay pedidos completados.', style: TextStyle(fontSize: 12.5, color: kMuted)),
              ),
            )
          else
            ...recent.map((order) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('#${order.code} · ${order.customerName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                              Text(relativeTime(order.createdAt),
                                  style: const TextStyle(fontSize: 10.5, color: kMuted)),
                            ],
                          ),
                        ),
                        StatusPill(order.status, small: true),
                        const SizedBox(width: 8),
                        Text(money(order.total), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ),
                )),
          const SizedBox(height: 22),
          OutlinedButton(
            onPressed: () => _confirmLogout(context),
            style: OutlinedButton.styleFrom(foregroundColor: kRed, side: const BorderSide(color: kRed)),
            child: const Text('Cerrar sesión'),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('VelozEat para restaurantes',
                style: TextStyle(fontSize: 10.5, color: kMuted.withValues(alpha: 0.9))),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de tu panel de restaurante?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 42)),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppState>().logout();
    }
  }
}

class _StatCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  const _StatCard({required this.emoji, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: kInk)),
          Text(label, style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
