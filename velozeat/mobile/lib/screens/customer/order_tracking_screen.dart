import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'chat_screen.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final Order? initialOrder;
  const OrderTrackingScreen({super.key, required this.orderId, this.initialOrder});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Order? _order;
  TrackingInfo? _tracking;
  bool _loading = true;
  String? _error;
  Timer? _timer;
  int _stars = 0;
  final _comment = TextEditingController();
  bool _ratingBusy = false;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    if (_order != null) {
      _loading = false;
      _stars = _order!.rating ?? 0;
    }
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && (_order?.isActive ?? true)) _fetch(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _order == null;
        _error = null;
      });
    }
    try {
      final app = context.read<AppState>();
      final res = await app.api.order(widget.orderId);
      final raw = res['order'];
      if (raw is Map<String, dynamic>) {
        final order = Order.fromJson(raw);
        TrackingInfo? tracking;
        try {
          final tRes = await app.api.tracking(widget.orderId);
          tracking = TrackingInfo.fromJson(tRes);
        } catch (_) {
          tracking = _tracking;
        }
        if (!mounted) return;
        setState(() {
          _order = order;
          _tracking = tracking;
          _loading = false;
          _error = null;
          if (order.rating != null) _stars = order.rating!;
        });
        if (!order.isActive) _timer?.cancel();
      }
    } on ApiException catch (e) {
      if (!silent && mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  String _message(Order order) {
    final driver = order.driverName ?? 'Tu repartidor';
    return switch (order.status) {
      'pending' => 'Enviamos tu pedido al restaurante. Esperando confirmación.',
      'accepted' => '${order.restaurantName} confirmó tu pedido.',
      'preparing' => 'Están preparando tu comida con mucho cuidado.',
      'ready' => 'Tu pedido está listo. Estamos asignando un repartidor.',
      'assigned' => '$driver va al restaurante por tu pedido.',
      'picked_up' => '$driver ya va en camino con tu pedido.',
      'delivered' => '¡Buen provecho! Tu pedido llegó a su destino.',
      'cancelled' => 'Este pedido fue cancelado.',
      _ => '',
    };
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('¿Cancelar pedido?'),
        content: const Text('El restaurante dejará de prepararlo. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: kRed,
              minimumSize: const Size(100, 42),
            ),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<AppState>().api.cancelOrder(widget.orderId, reason: 'Cancelado por el cliente');
      await _fetch();
      if (mounted) showSnack(context, 'Pedido cancelado.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _rate() async {
    if (_stars == 0 || _ratingBusy) return;
    setState(() => _ratingBusy = true);
    try {
      await context.read<AppState>().api.rateOrder(widget.orderId, _stars, _comment.text.trim());
      await _fetch();
      if (mounted) showSnack(context, '¡Gracias por calificar!');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _ratingBusy = false);
    }
  }

  bool get _hasMap {
    final t = _tracking;
    if (t == null) return false;
    return (t.restaurantLat != null && t.restaurantLng != null) ||
        (t.customerLat != null && t.customerLng != null) ||
        (t.driverLat != null && t.driverLng != null);
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(
        title: Text(order == null ? 'Pedido' : 'Pedido #${order.code}'),
        actions: [
          IconButton(onPressed: () => _fetch(), icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading && order == null
          ? const LoadingBox(label: 'Consultando tu pedido...')
          : _error != null && order == null
              ? EmptyState(
                  emoji: '',
                  title: 'No pudimos cargar el pedido',
                  subtitle: _error!,
                  action: FilledButton(
                    onPressed: () => _fetch(),
                    style: FilledButton.styleFrom(minimumSize: const Size(160, 46)),
                    child: const Text('Reintentar'),
                  ),
                )
              : order == null
                  ? const EmptyState(emoji: '', title: 'Pedido no encontrado')
                  : RefreshIndicator(
                      color: kBrand,
                      onRefresh: _fetch,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
                        children: [
                          _StatusHeader(order: order, message: _message(order)),
                          if (_hasMap) ...[
                            const SizedBox(height: 14),
                            _TrackingMap(tracking: _tracking!, order: order),
                          ],
                          if (order.isActive) ...[
                            const SizedBox(height: 14),
                            _SecurityCode(order: order),
                          ],
                          const SizedBox(height: 14),
                          if (order.status == 'cancelled')
                            SurfaceCard(
                              color: kRed.withValues(alpha: 0.05),
                              child: const Row(
                                children: [
                                  Text('', style: TextStyle(fontSize: 24)),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text('Pedido cancelado. No se realizó ningún cobro.',
                                        style: TextStyle(fontSize: 13, color: kRed, fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            )
                          else
                            _Timeline(status: order.status),
                          if (order.driverName != null) ...[
                            const SizedBox(height: 14),
                            _DriverCard(order: order),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(orderId: order.id, title: 'Chat con ${order.driverName}'),
                                ),
                              ),
                              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                              label: const Text('Chat con repartidor'),
                            ),
                          ],
                          const SizedBox(height: 14),
                          _DeliveryCard(order: order),
                          const SizedBox(height: 14),
                          _SummaryCard(order: order),
                          if (order.status == 'delivered') ...[
                            const SizedBox(height: 14),
                            _RatingCard(
                              order: order,
                              stars: _stars,
                              comment: _comment,
                              busy: _ratingBusy,
                              onStar: (value) => setState(() => _stars = value),
                              onSubmit: _rate,
                            ),
                          ],
                          if (order.status == 'pending' || order.status == 'accepted') ...[
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: _cancel,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kRed,
                                side: const BorderSide(color: kRed),
                              ),
                              child: const Text('Cancelar pedido'),
                            ),
                          ],
                          if (order.isFinished) ...[
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                              child: const Text('Volver al inicio'),
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final Order order;
  final String message;
  const _StatusHeader({required this.order, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(order.status);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.16), Colors.white],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(statusEmoji(order.status), style: const TextStyle(fontSize: 30)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusLabel(order.status),
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: color)),
                const SizedBox(height: 3),
                Text(message, style: const TextStyle(fontSize: 12.5, color: kMuted, height: 1.35)),
                const SizedBox(height: 6),
                Text('${order.restaurantEmoji} ${order.restaurantName}  ·  ${relativeTime(order.createdAt)}',
                    style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityCode extends StatelessWidget {
  final Order order;
  const _SecurityCode({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kInk, Color(0xFF2C303A)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CÓDIGO DE ENTREGA',
                    style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.w800, letterSpacing: 1)),
                SizedBox(height: 2),
                Text('Compártelo al recibir tu pedido',
                    style: TextStyle(fontSize: 11.5, color: Colors.white70)),
              ],
            ),
          ),
          Text(
            order.securityCode,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: kAccent,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final String status;
  const _Timeline({required this.status});

  static const steps = [
    ('pending', 'Pedido enviado', ''),
    ('accepted', 'Restaurante confirmó', ''),
    ('preparing', 'Preparando tu comida', ''),
    ('ready', 'Listo para recoger', ''),
    ('assigned', 'Repartidor asignado', ''),
    ('picked_up', 'En camino', ''),
    ('delivered', 'Entregado', ''),
  ];

  @override
  Widget build(BuildContext context) {
    final current = steps.indexWhere((s) => s.$1 == status);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Seguimiento', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++)
            SizedBox(
              height: 46,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: i <= current ? kGreen : kBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: i <= current ? kGreen : kLine, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: i <= current
                            ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                            : Text('${i + 1}', style: const TextStyle(fontSize: 10, color: kMuted, fontWeight: FontWeight.w800)),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: i < current ? kGreen : kLine,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '${steps[i].$3}  ${steps[i].$2}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i <= current ? FontWeight.w800 : FontWeight.w500,
                        color: i <= current ? kInk : kMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final Order order;
  const _DriverCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final name = order.driverName ?? 'Repartidor';
    return SurfaceCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: kGreen.withValues(alpha: 0.12), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  order.driverPhone == null || order.driverPhone!.isEmpty
                      ? 'Tu repartidor'
                      : 'Tel. ${order.driverPhone}',
                  style: const TextStyle(fontSize: 12, color: kMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.verified_rounded, color: kGreen, size: 20),
        ],
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final Order order;
  const _DeliveryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Entrega', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          InfoRow(Icons.location_on_outlined, order.address),
          if (order.zoneName.isNotEmpty)
            InfoRow(
              Icons.map_outlined,
              order.distanceKm > 0
                  ? '${order.zoneName}  ·  ${order.distanceKm.toStringAsFixed(1)} km'
                  : order.zoneName,
            ),
          if (order.notes.isNotEmpty) InfoRow(Icons.sticky_note_2_outlined, 'Nota: ${order.notes}'),
          InfoRow(
            order.paymentMethod == 'cash' ? Icons.payments_outlined : Icons.credit_card_outlined,
            order.paymentMethod == 'cash' ? 'Pago en efectivo al recibir' : 'Pago con tarjeta (simulado)',
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final Order order;
  const _SummaryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${order.restaurantEmoji} ${order.restaurantName}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Text(item.emoji, style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 6),
                    Text('${item.qty}x', style: const TextStyle(fontSize: 12, color: kBrand, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, color: kInk)),
                    ),
                    Text(money(item.price * item.qty),
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              )),
          const Divider(height: 18),
          PriceRow('Subtotal', money(order.subtotal)),
          if (order.distanceKm > 0) PriceRow('Distancia', '${order.distanceKm.toStringAsFixed(1)} km'),
          PriceRow('Envío', money(order.deliveryFee)),
          if (order.tip > 0) PriceRow('Propina', money(order.tip)),
          const Divider(height: 18),
          PriceRow('Total', money(order.total), bold: true),
        ],
      ),
    );
  }
}

class _RatingCard extends StatelessWidget {
  final Order order;
  final int stars;
  final TextEditingController comment;
  final bool busy;
  final ValueChanged<int> onStar;
  final VoidCallback onSubmit;

  const _RatingCard({
    required this.order,
    required this.stars,
    required this.comment,
    required this.busy,
    required this.onStar,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    if (order.rating != null) {
      return SurfaceCard(
        child: Row(
          children: [
            const Text('⭐', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Calificaste este pedido con ${order.rating} de 5.',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿Cómo estuvo tu pedido?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final value = index + 1;
              return IconButton(
                onPressed: () => onStar(value),
                icon: Icon(
                  value <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: value <= stars ? kAccent : kLine,
                  size: 34,
                ),
              );
            }),
          ),
          TextField(
            controller: comment,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Cuéntanos qué tal estuvo (opcional)'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: (stars == 0 || busy) ? null : onSubmit,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Enviar calificación'),
          ),
        ],
      ),
    );
  }
}

class _TrackingMap extends StatelessWidget {
  final TrackingInfo tracking;
  final Order order;
  const _TrackingMap({required this.tracking, required this.order});

  @override
  Widget build(BuildContext context) {
    final points = <LatLng>[];
    LatLng? center;
    final markers = <Marker>[];

    if (tracking.restaurantLat != null && tracking.restaurantLng != null) {
      final p = LatLng(tracking.restaurantLat!, tracking.restaurantLng!);
      points.add(p);
      center ??= p;
      markers.add(Marker(
        point: p,
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(color: kBrand, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(order.restaurantEmoji, style: const TextStyle(fontSize: 18)),
        ),
      ));
    }

    if (tracking.customerLat != null && tracking.customerLng != null) {
      final p = LatLng(tracking.customerLat!, tracking.customerLng!);
      points.add(p);
      center ??= p;
      markers.add(Marker(
        point: p,
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(color: kGreen, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 20),
        ),
      ));
    }

    if (tracking.driverLat != null && tracking.driverLng != null) {
      final p = LatLng(tracking.driverLat!, tracking.driverLng!);
      points.add(p);
      center ??= p;
      markers.add(Marker(
        point: p,
        width: 44,
        height: 44,
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFF0D9488), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          alignment: Alignment.center,
          child: const Icon(Icons.delivery_dining_rounded, color: Colors.white, size: 22),
        ),
      ));
    }

    center ??= const LatLng(19.4326, -99.1332);

    return SurfaceCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Mapa en vivo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (tracking.driverName != null)
                Text(tracking.driverName!, style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 230,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 14,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.velozeat.velozeat',
                  ),
                  if (points.length >= 2)
                    PolylineLayer(
                      polylines: [
                        Polyline(points: points, color: kBrand.withValues(alpha: 0.7), strokeWidth: 3),
                      ],
                    ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legendDot(kBrand, 'Restaurante'),
              const SizedBox(width: 12),
              _legendDot(kGreen, 'Tu dirección'),
              const SizedBox(width: 12),
              _legendDot(const Color(0xFF0D9488), 'Repartidor'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

