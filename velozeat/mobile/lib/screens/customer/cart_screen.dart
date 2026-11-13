import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models.dart';
import '../../location_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'order_tracking_screen.dart';

class CartScreen extends StatefulWidget {
  final Restaurant restaurant;
  const CartScreen({super.key, required this.restaurant});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late final TextEditingController _address;
  final _notes = TextEditingController();
  final _coupon = TextEditingController();
  final _cardNumber = TextEditingController();
  final _cardName = TextEditingController();
  final _cardExpiry = TextEditingController();
  final _cardCvv = TextEditingController();
  double _tip = 0;
  String? _appliedCoupon;
  double _discount = 0;
  bool _applyingCoupon = false;
  String _payment = 'cash';
  bool _placing = false;

  List<Zone> _zones = const [];
  String _zoneId = '';
  DeliveryQuote? _quote;
  bool _loadingQuote = false;
  int _quoteSeq = 0;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().user;
    _address = TextEditingController(text: user?.address ?? '');
    _zoneId = user?.zoneId ?? '';
    _loadZones();
  }

  Future<void> _loadZones() async {
    try {
      final meta = Meta.fromJson(await context.read<AppState>().api.meta());
      if (!mounted) return;
      setState(() {
        _zones = meta.zones;
        if (_zoneId.isEmpty && _zones.isNotEmpty) _zoneId = _zones.first.id;
      });
      await _refreshQuote();
    } catch (_) {
      // Si falla la carga de zonas se usa la tarifa base del restaurante.
    }
  }

  Future<void> _refreshQuote() async {
    if (_lat == null && _zoneId.isEmpty) return;
    final seq = ++_quoteSeq;
    setState(() => _loadingQuote = true);
    try {
      final raw = await context.read<AppState>().api.quote(
            widget.restaurant.id,
            _zoneId.isEmpty ? 'z-centro' : _zoneId,
            lat: _lat,
            lng: _lng,
          );
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = DeliveryQuote.fromJson(raw);
        _loadingQuote = false;
      });
    } catch (_) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() => _loadingQuote = false);
    }
  }

  Future<void> _useGps() async {
    if (_loadingQuote) return;
    setState(() => _loadingQuote = true);
    final position = await LocationService.currentPosition();
    if (!mounted) return;
    if (position == null) {
      setState(() => _loadingQuote = false);
      showSnack(context, 'No se pudo obtener tu ubicaciÃÂÃÂ³n. Activa el GPS y dale permiso a VelozEat.', error: true);
      return;
    }
    setState(() {
      _lat = position.latitude;
      _lng = position.longitude;
      _zoneId = '';
    });
    await _refreshQuote();
  }

  Future<void> _pickOnMap() async {
    final initial = _lat != null && _lng != null
        ? LatLng(_lat!, _lng!)
        : const LatLng(19.4326, -99.1332);
    LatLng? selected = initial;
    final result = await showDialog<LatLng>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Selecciona la ubicaciÃÂÃÂ³n de entrega'),
              content: SizedBox(
                width: double.maxFinite,
                height: 320,
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: initial,
                            initialZoom: 14,
                            onTap: (_, point) => setDialogState(() => selected = point),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.velozeat.velozeat',
                            ),
                            if (selected != null)
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: selected!,
                                    width: 40,
                                    height: 40,
                                    child: Container(
                                      decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 22),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selected == null
                          ? 'Toca el mapa para marcar tu ubicaciÃÂÃÂ³n'
                          : 'Lat ${selected!.latitude.toStringAsFixed(5)}, Lng ${selected!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(fontSize: 12, color: kMuted),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                FilledButton(
                  onPressed: selected == null ? null : () => Navigator.pop(context, selected),
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null && mounted) {
      setState(() {
        _lat = result.latitude;
        _lng = result.longitude;
        _zoneId = '';
      });
      await _refreshQuote();
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    _coupon.dispose();
    _cardNumber.dispose();
    _cardName.dispose();
    _cardExpiry.dispose();
    _cardCvv.dispose();
    super.dispose();
  }

  Future<void> _applyCoupon() async {
    final code = _coupon.text.trim();
    if (code.isEmpty) return;
    setState(() => _applyingCoupon = true);
    try {
      final app = context.read<AppState>();
      final res = await app.api.validateCoupon(code, widget.restaurant.id, app.cartSubtotal);
      setState(() {
        _appliedCoupon = (res['code'] ?? code).toString();
        _discount = asDouble(res['discount']);
      });
      if (mounted) showSnack(context, (res['message'] ?? 'Cupon aplicado').toString());
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  bool _validateCard() {
    if (_payment != 'card') return true;
    final number = _cardNumber.text.replaceAll(' ', '');
    if (number.length < 13 || number.length > 19 || !_luhn(number)) {
      showSnack(context, 'NÃÂÃÂºmero de tarjeta invÃÂÃÂ¡lido.', error: true);
      return false;
    }
    if (_cardName.text.trim().length < 3) {
      showSnack(context, 'Ingresa el nombre del titular.', error: true);
      return false;
    }
    final expiry = _cardExpiry.text.trim();
    if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(expiry)) {
      showSnack(context, 'Fecha de expiraciÃÂÃÂ³n invÃÂÃÂ¡lida (MM/AA).', error: true);
      return false;
    }
    final parts = expiry.split('/');
    final month = int.tryParse(parts[0]) ?? 0;
    final year = int.tryParse(parts[1]) ?? 0;
    if (month < 1 || month > 12) {
      showSnack(context, 'Mes de expiraciÃÂÃÂ³n invÃÂÃÂ¡lido.', error: true);
      return false;
    }
    final now = DateTime.now();
    final fullYear = 2000 + year;
    if (fullYear < now.year || (fullYear == now.year && month < now.month)) {
      showSnack(context, 'La tarjeta estÃÂÃÂ¡ expirada.', error: true);
      return false;
    }
    final cvv = _cardCvv.text.trim();
    if (cvv.length < 3 || cvv.length > 4) {
      showSnack(context, 'CVV invÃÂÃÂ¡lido.', error: true);
      return false;
    }
    return true;
  }

  bool _luhn(String input) {
    var sum = 0;
    var alternate = false;
    for (var i = input.length - 1; i >= 0; i--) {
      var n = int.tryParse(input[i]) ?? 0;
      if (alternate) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alternate = !alternate;
    }
    return sum % 10 == 0;
  }

  Future<void> _placeOrder() async {
    final app = context.read<AppState>();
    if (_placing) return;
    if (app.cartLines.isEmpty) return;
    if (_quote?.outOfRange == true) {
      showSnack(context, 'Tu ubicaciÃÂÃÂ³n estÃÂÃÂ¡ fuera del ÃÂÃÂ¡rea de entrega.', error: true);
      return;
    }
    if (_lat == null && _zoneId.isEmpty) {
      showSnack(context, 'Elige una zona de entrega o tu ubicaciÃÂÃÂ³n.', error: true);
      return;
    }
    if (!_validateCard()) return;
    if (app.cartSubtotal < widget.restaurant.minOrder) {
      showSnack(context,
          'El pedido mÃÂÃÂ­nimo es ${money(widget.restaurant.minOrder)}. Agrega algo mÃÂÃÂ¡s.', error: true);
      return;
    }

    setState(() => _placing = true);
    try {
      final res = await app.api.createOrder({
        'restaurantId': widget.restaurant.id,
        'items': app.cartLines.map((line) => {'itemId': line.item.id, 'qty': line.qty}).toList(),
        'address': _address.text.trim().isNotEmpty
            ? _address.text.trim()
            : (_lat != null && _lng != null
                ? 'UbicaciÃÂÃÂ³n GPS (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)})'
                : (_zones.firstWhere((z) => z.id == _zoneId, orElse: () => Zone(id: '', name: 'Zona de entrega')).name)),
        'zoneId': _zoneId,
        if (_lat != null && _lng != null) 'lat': _lat,
        if (_lat != null && _lng != null) 'lng': _lng,
        'notes': _notes.text.trim(),
        if (_appliedCoupon != null) 'couponCode': _appliedCoupon,
        'paymentMethod': _payment,
        'tip': _tip,
      });
      final raw = res['order'];
      if (raw is! Map<String, dynamic>) throw ApiException('No se pudo crear el pedido.');
      final order = Order.fromJson(raw);
      app.clearCart();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: order.id, initialOrder: order)),
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lines = app.cartLines;
    final subtotal = app.cartSubtotal;
    final quote = _quote;
    final delivery = quote?.deliveryFee ?? widget.restaurant.deliveryFee;
    final total = subtotal + delivery + _tip - _discount;
    final belowMin = subtotal < widget.restaurant.minOrder;

    return Scaffold(
      appBar: AppBar(title: const Text('Tu carrito')),
      body: lines.isEmpty
          ? EmptyState(
              emoji: '',
              title: 'Tu carrito estÃÂÃÂ¡ vacÃÂÃÂ­o',
              subtitle: 'Agrega platillos de ${widget.restaurant.name} para empezar.',
              action: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(minimumSize: const Size(180, 48)),
                child: const Text('Ver el menÃÂÃÂº'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 26),
              children: [
                Row(
                  children: [
                    EmojiBox(emoji: widget.restaurant.emoji, size: 46, color: colorFromHex(widget.restaurant.color)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.restaurant.name,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          Text(
                              quote == null
                                  ? '${widget.restaurant.etaMinutes} min ÃÂÃÂ· EnvÃÂÃÂ­o desde ${money(delivery)}'
                                  : '${widget.restaurant.etaMinutes} min ÃÂÃÂ· ${quote.distanceKm.toStringAsFixed(1)} km ÃÂÃÂ· EnvÃÂÃÂ­o ${money(delivery)}',
                              style: const TextStyle(fontSize: 11.5, color: kMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ...lines.map((line) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            EmojiBox(emoji: line.item.emoji, size: 44, color: kBrand),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(line.item.name,
                                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(money(line.item.price),
                                      style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            _Stepper(
                              qty: line.qty,
                              onMinus: () => app.decreaseCart(line.item),
                              onPlus: () => app.addToCart(widget.restaurant, line.item),
                            ),
                            const SizedBox(width: 10),
                            Text(money(line.total),
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    )),
                const SizedBox(height: 10),
                _block(
                  title: 'DirecciÃÂÃÂ³n de entrega',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _loadingQuote ? null : _useGps,
                              icon: const Icon(Icons.my_location_rounded, size: 18),
                              label: const Text('Mi ubicaciÃÂÃÂ³n'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _loadingQuote ? null : _pickOnMap,
                              icon: const Icon(Icons.map_rounded, size: 18),
                              label: const Text('Elegir en mapa'),
                            ),
                          ),
                        ],
                      ),
                      if (_lat != null && _lng != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: kBrand.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.gps_fixed_rounded, size: 18, color: kBrand),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'UbicaciÃÂÃÂ³n GPS aplicada ÃÂÃÂ· ${quote?.distanceKm.toStringAsFixed(1) ?? '...'} km del restaurante',
                                  style: const TextStyle(fontSize: 12, color: kBrand, fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _lat = null;
                                    _lng = null;
                                    if (_zones.isNotEmpty) _zoneId = _zones.first.id;
                                  });
                                  _refreshQuote();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_lat == null && _zones.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _zoneId.isEmpty ? null : _zoneId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Zona de entrega',
                            prefixIcon: Icon(Icons.map_outlined),
                          ),
                          items: _zones
                              .map((zone) => DropdownMenuItem(value: zone.id, child: Text(zone.name)))
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _zoneId = value;
                              _lat = null;
                              _lng = null;
                            });
                            _refreshQuote();
                          },
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: _address,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: _lat != null || _zoneId.isNotEmpty
                              ? 'Referencias para el repartidor (opcional)'
                              : 'Calle, nÃÂÃÂºmero, colonia y referencias',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kBrand.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.route_rounded, size: 18, color: kBrand),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _loadingQuote
                                    ? 'Calculando el envÃÂÃÂ­o por distancia...'
                                    : quote == null
                                        ? 'EnvÃÂÃÂ­o desde ${money(delivery)}'
                                        : '${quote.distanceKm.toStringAsFixed(1)} km desde el restaurante ÃÂÃÂ· '
                                            'EnvÃÂÃÂ­o ${money(quote.deliveryFee)}',
                                style: const TextStyle(
                                    fontSize: 12, color: kBrand, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notes,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Notas para el restaurante o el repartidor (opcional)',
                          prefixIcon: Icon(Icons.sticky_note_2_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _block(
                  title: 'Cupon de descuento',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _coupon,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                hintText: 'Codigo de cupon',
                                prefixIcon: Icon(Icons.local_offer_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: _applyingCoupon ? null : _applyCoupon,
                            style: FilledButton.styleFrom(minimumSize: const Size(100, 54)),
                            child: _applyingCoupon
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Aplicar'),
                          ),
                        ],
                      ),
                      if (_appliedCoupon != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: kGreen, size: 18),
                            const SizedBox(width: 6),
                            Expanded(child: Text('Cupon $_appliedCoupon aplicado', style: const TextStyle(fontSize: 12.5, color: kGreen, fontWeight: FontWeight.w700))),
                            TextButton(onPressed: () { setState(() { _appliedCoupon = null; _discount = 0; _coupon.clear(); }); }, child: const Text('Quitar')),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _block(
                  title: 'MÃÂÃÂ©todo de pago',
                  child: Row(
                    children: [
                      _PaymentTile(
                        emoji: '',
                        label: 'Efectivo',
                        detail: 'Pagas al recibir',
                        selected: _payment == 'cash',
                        onTap: () => setState(() => _payment = 'cash'),
                      ),
                      const SizedBox(width: 10),
                      _PaymentTile(
                        emoji: 'Wallet',
                        label: 'Billetera',
                        detail: 'Saldo disponible',
                        selected: _payment == 'wallet',
                        onTap: () => setState(() => _payment = 'wallet'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _block(
                  title: 'Propina para tu repartidor',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [0, 10, 20, 30, 50].map((amount) {
                      final selected = _tip == amount.toDouble();
                      return GestureDetector(
                        onTap: () => setState(() => _tip = amount.toDouble()),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                          decoration: BoxDecoration(
                            color: selected ? kBrand.withValues(alpha: 0.10) : kBg,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: selected ? kBrand : kLine),
                          ),
                          child: Text(
                            amount == 0 ? 'Sin propina' : money(amount),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: selected ? kBrand : kMuted,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                _block(
                  title: 'Resumen',
                  child: Column(
                    children: [
                      PriceRow('Subtotal', money(subtotal)),
                      if (quote != null)
                        PriceRow('Distancia', '${quote.distanceKm.toStringAsFixed(1)} km'),
                      PriceRow('EnvÃÂÃÂ­o', money(delivery)),
                      if (_discount > 0) PriceRow('Cupon', '-${money(_discount)}', color: kGreen),
                      PriceRow('Propina', money(_tip)),
                      const Divider(height: 20),
                      PriceRow('Total', money(total), bold: true),
                      if (belowMin) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kBrand.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Te faltan ${money(widget.restaurant.minOrder - subtotal)} para el pedido mÃÂÃÂ­nimo.',
                            style: const TextStyle(fontSize: 12, color: kBrand, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: lines.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: kLine)),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 11.5, color: kMuted)),
                        Text(money(total),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: kInk)),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: (_placing || belowMin) ? null : _placeOrder,
                        child: _placing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Text('Hacer pedido'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _block({required String title, required Widget child}) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _Stepper({required this.qty, required this.onMinus, required this.onPlus});

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
          _icon(Icons.remove_rounded, onMinus),
          Text('$qty', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
          _icon(Icons.add_rounded, onPlus),
        ],
      ),
    );
  }

  Widget _icon(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: SizedBox(width: 30, height: 32, child: Icon(icon, size: 17, color: kBrand)),
      );
}

class _PaymentTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  const _PaymentTile({
    required this.emoji,
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? kBrand.withValues(alpha: 0.08) : kBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? kBrand : kLine, width: selected ? 1.4 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 20)),
                  const Spacer(),
                  Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    size: 18,
                    color: selected ? kBrand : kMuted,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kInk)),
              Text(detail, style: const TextStyle(fontSize: 10.5, color: kMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
