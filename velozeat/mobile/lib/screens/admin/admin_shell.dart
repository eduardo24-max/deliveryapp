import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _stats = {};
  List<Restaurant> _pending = [];
  List<Order> _recent = [];
  String? _processingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _stats.isEmpty;
      _error = null;
    });
    try {
      final res = await context.read<AppState>().api.adminStats();
      final rawStats = res['stats'];
      final rawPending = res['pendingRestaurants'];
      final rawRecent = res['recentOrders'];
      if (!mounted) return;
      setState(() {
        _stats = rawStats is Map<String, dynamic> ? rawStats : {};
        _pending = rawPending is List
            ? rawPending.whereType<Map<String, dynamic>>().map(Restaurant.fromJson).toList()
            : [];
        _recent = rawRecent is List
            ? rawRecent.whereType<Map<String, dynamic>>().map(Order.fromJson).toList()
            : [];
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _approve(Restaurant restaurant) async {
    setState(() => _processingId = restaurant.id);
    try {
      final res = await context.read<AppState>().api.approveRestaurant(restaurant.id, true);
      if (mounted) showSnack(context, (res['message'] ?? 'Restaurante aprobado').toString());
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _processingId = null);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir del panel de administración?'),
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
    if (confirmed == true && mounted) {
      await context.read<AppState>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_loading) return const Scaffold(body: LoadingBox(label: 'Cargando operación VelozEat...'));
    if (_error != null && _stats.isEmpty) {
      return Scaffold(
        body: EmptyState(
          emoji: '',
          title: 'No pudimos cargar el panel',
          subtitle: _error!,
          action: FilledButton(
            onPressed: _load,
            style: FilledButton.styleFrom(minimumSize: const Size(160, 46)),
            child: const Text('Reintentar'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const AppLogo(size: 19),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: kBrand,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          children: [
            Text('Operación', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('Hola, ${app.user?.name ?? 'equipo'} · resumen de hoy',
                style: const TextStyle(fontSize: 12.5, color: kMuted)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
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
                        const Text('VENTAS DEL DÍA (GMV)',
                            style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text(money(asDouble(_stats['gmvToday'])),
                            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text('${asInt(_stats['deliveredToday'])} pedidos entregados',
                            style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('COMISIÓN',
                          style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                      const SizedBox(height: 4),
                      Text(money(asDouble(_stats['commissionToday'])),
                          style: const TextStyle(color: kAccent, fontSize: 20, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.75,
              children: [
                _AdminStat(emoji: '', label: 'Pedidos hoy', value: '${asInt(_stats['ordersToday'])}'),
                _AdminStat(emoji: '', label: 'Pedidos activos', value: '${asInt(_stats['activeOrders'])}'),
                _AdminStat(emoji: '', label: 'Restaurantes', value: '${asInt(_stats['restaurants'])}'),
                _AdminStat(emoji: '⏳', label: 'Por aprobar', value: '${asInt(_stats['pendingRestaurants'])}'),
                _AdminStat(emoji: '', label: 'Clientes', value: '${asInt(_stats['customers'])}'),
                _AdminStat(emoji: '', label: 'Repartidores', value: '${asInt(_stats['drivers'])}'),
              ],
            ),
            const SizedBox(height: 18),
            SectionTitle('Restaurantes por aprobar', action: '${_pending.length}'),
            const SizedBox(height: 6),
            if (_pending.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('Todo al día. No hay solicitudes pendientes.',
                      style: TextStyle(fontSize: 12.5, color: kMuted)),
                ),
              )
            else
              ..._pending.map((restaurant) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              EmojiBox(emoji: restaurant.emoji, size: 44, color: colorFromHex(restaurant.color)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(restaurant.name,
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                    Text('${restaurant.category} · ${restaurant.address}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10.5, color: kMuted)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const BrandBadge('Pendiente', icon: Icons.hourglass_empty_rounded),
                              const Spacer(),
                              FilledButton(
                                onPressed: _processingId == restaurant.id ? null : () => _approve(restaurant),
                                style: FilledButton.styleFrom(minimumSize: const Size(120, 42), backgroundColor: kGreen),
                                child: _processingId == restaurant.id
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('Aprobar'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )),
            const SizedBox(height: 18),
            SectionTitle('Pedidos recientes', action: '${_recent.length}'),
            const SizedBox(height: 6),
            if (_recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('Aún no hay pedidos.', style: TextStyle(fontSize: 12.5, color: kMuted)),
                ),
              )
            else
              ..._recent.map((order) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SurfaceCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Text(order.restaurantEmoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('#${order.code} · ${order.restaurantName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                Text('${order.customerName} · ${relativeTime(order.createdAt)}',
                                    style: const TextStyle(fontSize: 10.5, color: kMuted)),
                              ],
                            ),
                          ),
                          StatusPill(order.status, small: true),
                          const SizedBox(width: 8),
                          Text(money(order.total), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  )),
            const SizedBox(height: 20),
            Center(
              child: Text('VelozEat Admin · ${app.api.baseUrl}',
                  style: const TextStyle(fontSize: 10.5, color: kMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminStat extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  const _AdminStat({required this.emoji, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kInk)),
          Text(label, style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
