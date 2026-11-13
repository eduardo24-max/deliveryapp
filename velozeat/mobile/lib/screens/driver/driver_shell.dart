import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../location_service.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _index = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _online = false;
  DriverProfile? _profile;
  double _todayEarnings = 0;
  int _todayDeliveries = 0;
  int _totalDeliveries = 0;
  double _rating = 5;
  Order? _active;
  List<Order> _available = [];
  List<Order> _recent = [];
  Timer? _timer;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted && _online) _load(silent: true);
    });
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && _online) _pushLocation();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _pushLocation() async {
    try {
      final position = await LocationService.currentPosition();
      if (position == null || !mounted) return;
      await context.read<AppState>().api.setDriverLocation(
            position.latitude,
            position.longitude,
            isOnline: _online,
          );
    } catch (_) {
      // Ignorar fallos de ubicación para no interrumpir el flujo.
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = context.read<AppState>().api;
      final summary = await api.driverSummary();
      final rawProfile = summary['profile'];
      final rawActive = summary['activeOrder'];
      final rawRecent = summary['recent'];
      List<Order> available = [];
      if (_online || (rawProfile is Map<String, dynamic> && rawProfile['isOnline'] == true)) {
        final availableRes = await api.driverAvailable();
        final rawAvailable = availableRes['orders'];
        available = rawAvailable is List
            ? rawAvailable.whereType<Map<String, dynamic>>().map(Order.fromJson).toList()
            : [];
      }
      if (!mounted) return;
      setState(() {
        _profile = rawProfile is Map<String, dynamic> ? DriverProfile.fromJson(rawProfile) : _profile;
        _online = _profile?.isOnline ?? false;
        _todayEarnings = asDouble(summary['todayEarnings']);
        _todayDeliveries = asInt(summary['todayDeliveries']);
        _totalDeliveries = asInt(summary['totalDeliveries']);
        _rating = asDouble(summary['rating']);
        _active = rawActive is Map<String, dynamic> ? Order.fromJson(rawActive) : null;
        _recent = rawRecent is List
            ? rawRecent.whereType<Map<String, dynamic>>().map(Order.fromJson).toList()
            : [];
        _available = available;
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

  Future<void> _setOnline(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await context.read<AppState>().api.setDriverOnline(value);
      if (mounted) showSnack(context, (res['message'] ?? 'Listo').toString());
      if (value) await _pushLocation();
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim(Order order) async {
    try {
      final res = await context.read<AppState>().api.claimOrder(order.id);
      if (mounted) showSnack(context, (res['message'] ?? 'Pedido asignado').toString());
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _pickup(Order order) async {
    try {
      final res = await context.read<AppState>().api.pickupOrder(order.id);
      if (mounted) showSnack(context, (res['message'] ?? 'Pedido recogido').toString());
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _deliver(Order order) async {
    final code = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Confirmar entrega'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pide al cliente su código de 4 dígitos.',
                style: TextStyle(fontSize: 12.5, color: kMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 8),
              decoration: const InputDecoration(hintText: '0000', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 42)),
            child: const Text('Entregar'),
          ),
        ],
      ),
    );
    final value = code.text.trim();
    code.dispose();
    if (confirmed != true || !mounted) return;
    if (value.length != 4) {
      showSnack(context, 'El código debe tener 4 dígitos.', error: true);
      return;
    }
    try {
      final res = await context.read<AppState>().api.deliverOrder(order.id, value);
      if (mounted) showSnack(context, (res['message'] ?? '¡Entrega completada!').toString());
      await _load(silent: true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;
    final firstName = (user?.name ?? 'Repartidor').split(' ').first;

    if (_loading && _profile == null) {
      return const Scaffold(body: LoadingBox(label: 'Conectando como repartidor...'));
    }
    if (_error != null && _profile == null) {
      return Scaffold(
        body: EmptyState(
          emoji: '',
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

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _HomeTab(
            firstName: firstName,
            profile: _profile,
            online: _online,
            busy: _busy,
            todayEarnings: _todayEarnings,
            todayDeliveries: _todayDeliveries,
            rating: _rating,
            active: _active,
            available: _available,
            onRefresh: () => _load(),
            onToggleOnline: _setOnline,
            onClaim: _claim,
            onPickup: _pickup,
            onDeliver: _deliver,
          ),
          _HistoryTab(recent: _recent, totalDeliveries: _totalDeliveries),
          _DriverProfileTab(
            profile: _profile,
            rating: _rating,
            totalDeliveries: _totalDeliveries,
            onRefresh: () => _load(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _active != null,
              backgroundColor: kBrand,
              child: const Icon(Icons.bolt_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _active != null,
              backgroundColor: kBrand,
              child: const Icon(Icons.bolt_rounded),
            ),
            label: 'Repartir',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Historial',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final String firstName;
  final DriverProfile? profile;
  final bool online;
  final bool busy;
  final double todayEarnings;
  final int todayDeliveries;
  final double rating;
  final Order? active;
  final List<Order> available;
  final Future<void> Function() onRefresh;
  final Future<void> Function(bool value) onToggleOnline;
  final Future<void> Function(Order order) onClaim;
  final Future<void> Function(Order order) onPickup;
  final Future<void> Function(Order order) onDeliver;

  const _HomeTab({
    required this.firstName,
    required this.profile,
    required this.online,
    required this.busy,
    required this.todayEarnings,
    required this.todayDeliveries,
    required this.rating,
    required this.active,
    required this.available,
    required this.onRefresh,
    required this.onToggleOnline,
    required this.onClaim,
    required this.onPickup,
    required this.onDeliver,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: kBrand,
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            Row(
              children: [
                const AppLogo(size: 21),
                const Spacer(),
                Text('${profile?.vehicleEmoji ?? ''} ${profile?.vehicleLabel ?? ''}',
                    style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),
            Text('Hola, $firstName ', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(online ? 'Estás en línea y listo para repartir.' : 'Conéctate para ver pedidos disponibles.',
                style: const TextStyle(fontSize: 12.5, color: kMuted)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: online
                      ? [const Color(0xFF16A34A), const Color(0xFF22C55E)]
                      : [const Color(0xFF3F4652), const Color(0xFF5B6472)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(online ? 'En línea' : 'Fuera de línea',
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(online ? 'Recibiendo ofertas de entrega' : 'Actívate para tomar pedidos',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5)),
                      ],
                    ),
                  ),
                  Switch(
                    value: online,
                    activeTrackColor: Colors.white,
                    activeThumbColor: kGreen,
                    onChanged: busy ? null : (value) => onToggleOnline(value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _Stat(emoji: '', value: money(todayEarnings), label: 'Ganancias hoy')),
                const SizedBox(width: 10),
                Expanded(child: _Stat(emoji: '', value: '$todayDeliveries', label: 'Entregas hoy')),
                const SizedBox(width: 10),
                Expanded(child: _Stat(emoji: '⭐', value: rating.toStringAsFixed(1), label: 'Calificación')),
              ],
            ),
            if (active != null) ...[
              const SizedBox(height: 18),
              const SectionTitle('Entrega en curso'),
              const SizedBox(height: 8),
              _ActiveOrderCard(
                order: active!,
                onPickup: () => onPickup(active!),
                onDeliver: () => onDeliver(active!),
              ),
            ],
            const SizedBox(height: 18),
            SectionTitle('Pedidos disponibles', action: online ? '${available.length}' : null),
            const SizedBox(height: 4),
            if (!online)
              EmptyState(
                emoji: '',
                title: 'Estás desconectado',
                subtitle: 'Ponte en línea para empezar a recibir pedidos listos de los restaurantes.',
                action: FilledButton(
                  onPressed: busy ? null : () => onToggleOnline(true),
                  style: FilledButton.styleFrom(minimumSize: const Size(180, 46)),
                  child: const Text('Ponerme en línea'),
                ),
              )
            else if (available.isEmpty)
              const EmptyState(
                emoji: '⏳',
                title: 'Sin pedidos por ahora',
                subtitle: 'Actualizamos automáticamente. Mantente en línea para recibir ofertas.',
              )
            else
              ...available.map((order) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AvailableOrderCard(order: order, onClaim: () => onClaim(order)),
                  )),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _Stat({required this.emoji, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kInk)),
          Text(label, style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onPickup;
  final VoidCallback onDeliver;
  const _ActiveOrderCard({required this.order, required this.onPickup, required this.onDeliver});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${order.code}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              const Spacer(),
              StatusPill(order.status, small: true),
            ],
          ),
          const SizedBox(height: 10),
          _stop(
            color: kBrand,
            label: 'Recoger en',
            title: '${order.restaurantEmoji} ${order.restaurantName}',
            subtitle: order.restaurantAddress,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Container(width: 2, height: 14, color: kLine),
          ),
          _stop(
            color: kGreen,
            label: 'Entregar a',
            title: order.customerName,
            subtitle: order.address,
          ),
          if (order.distanceKm > 0) ...[
            const SizedBox(height: 6),
            InfoRow(Icons.route_rounded, '${order.distanceKm.toStringAsFixed(1)} km de recorrido', color: kBrand),
          ],
          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            InfoRow(Icons.sticky_note_2_outlined, 'Nota: ${order.notes}', color: kBrand),
          ],
          const Divider(height: 20),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ganas', style: TextStyle(fontSize: 10.5, color: kMuted)),
                  Text(money(order.driverEarnings),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: kGreen)),
                ],
              ),
              const Spacer(),
              if (order.paymentMethod == 'cash')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: kBrand.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Cobra ${money(order.total)}',
                      style: const TextStyle(fontSize: 10.5, color: kBrand, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (order.status == 'assigned')
            FilledButton.icon(
              onPressed: onPickup,
              icon: const Icon(Icons.shopping_bag_outlined, size: 18),
              label: const Text('Ya recogí el pedido'),
            )
          else if (order.status == 'picked_up')
            FilledButton.icon(
              onPressed: onDeliver,
              style: FilledButton.styleFrom(backgroundColor: kGreen),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Confirmar entrega'),
            ),
        ],
      ),
    );
  }

  Widget _stop({required Color color, required String label, required String title, required String subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w700)),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kInk)),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: const TextStyle(fontSize: 11.5, color: kMuted, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AvailableOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onClaim;
  const _AvailableOrderCard({required this.order, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              EmojiBox(emoji: order.restaurantEmoji, size: 42, color: colorFromHex(order.restaurantColor)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.restaurantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                    Text('${order.restaurantAddress} · ${relativeTime(order.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: kMuted)),
                  ],
                ),
              ),
              StatusPill(order.status, small: true),
            ],
          ),
          const SizedBox(height: 10),
          InfoRow(Icons.location_on_outlined, order.address),
          InfoRow(Icons.shopping_bag_outlined, '${order.items.length} artículo(s) · ${order.paymentMethod == 'cash' ? 'Efectivo' : 'Tarjeta'}'),
          if (order.distanceKm > 0)
            InfoRow(Icons.route_rounded, '${order.distanceKm.toStringAsFixed(1)} km de recorrido'),
          const SizedBox(height: 4),
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ganas', style: TextStyle(fontSize: 10, color: kMuted)),
                  Text(money(order.driverEarnings),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: kGreen)),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: onClaim,
                style: FilledButton.styleFrom(minimumSize: const Size(130, 42)),
                child: const Text('Tomar pedido'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final List<Order> recent;
  final int totalDeliveries;
  const _HistoryTab({required this.recent, required this.totalDeliveries});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          Text('Mi historial', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('$totalDeliveries entregas completadas en total', style: const TextStyle(fontSize: 12.5, color: kMuted)),
          const SizedBox(height: 16),
          if (recent.isEmpty)
            const EmptyState(
              emoji: '',
              title: 'Aún no tienes entregas',
              subtitle: 'Cuando completes tu primera entrega aparecerá aquí.',
            )
          else
            ...recent.map((order) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        EmojiBox(emoji: order.restaurantEmoji, size: 42, color: colorFromHex(order.restaurantColor)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${order.restaurantName} · #${order.code}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                              Text(relativeTime(order.deliveredAt ?? order.createdAt),
                                  style: const TextStyle(fontSize: 10.5, color: kMuted)),
                            ],
                          ),
                        ),
                        Text('+${money(order.driverEarnings)}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: kGreen)),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

class _DriverProfileTab extends StatelessWidget {
  final DriverProfile? profile;
  final double rating;
  final int totalDeliveries;
  final Future<void> Function() onRefresh;

  const _DriverProfileTab({
    required this.profile,
    required this.rating,
    required this.totalDeliveries,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;
    if (user == null) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: kBrand,
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          children: [
            Text('Mi perfil', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(profile?.vehicleEmoji ?? '', style: const TextStyle(fontSize: 28)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text('${profile?.vehicleLabel ?? 'Repartidor'} VelozEat',
                              style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _Stat(emoji: '⭐', value: rating.toStringAsFixed(1), label: 'Calificación')),
                const SizedBox(width: 10),
                Expanded(child: _Stat(emoji: '', value: '$totalDeliveries', label: 'Entregas')),
                const SizedBox(width: 10),
                Expanded(child: _Stat(emoji: '', value: money(profile?.earnings ?? 0), label: 'Ganancias')),
              ],
            ),
            const SizedBox(height: 16),
            SurfaceCard(
              child: Column(
                children: [
                  InfoRow(Icons.phone_outlined, user.phone.isEmpty ? 'Sin teléfono' : user.phone),
                  InfoRow(Icons.mail_outline, user.email),
                  InfoRow(Icons.two_wheeler_outlined, 'Vehículo: ${profile?.vehicleLabel ?? 'No definido'}'),
                  InfoRow(Icons.wifi_tethering_rounded,
                      profile?.isOnline == true ? 'Estado: en línea' : 'Estado: fuera de línea',
                      color: profile?.isOnline == true ? kGreen : kMuted),
                ],
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () => _confirmLogout(context),
              style: OutlinedButton.styleFrom(foregroundColor: kRed, side: const BorderSide(color: kRed)),
              child: const Text('Cerrar sesión'),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text('VelozEat Repartidores v1.0',
                  style: TextStyle(fontSize: 10.5, color: kMuted.withValues(alpha: 0.9))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de tu cuenta de repartidor?'),
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
