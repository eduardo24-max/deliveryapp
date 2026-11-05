import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models.dart';
import '../../location_service.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'restaurant_screen.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _loading = true;
  String? _error;
  List<Restaurant> _restaurants = [];
  List<Map<String, dynamic>> _notifications = [];
  List<String> _categories = ['Todos'];
  String _category = 'Todos';
  final _search = TextEditingController();
  double? _lat;
  double? _lng;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
    _loadNotifications();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        context.read<AppState>().api.restaurants(lat: _lat, lng: _lng),
        context.read<AppState>().api.meta(),
      ]);
      final restaurantRes = results[0];
      final meta = Meta.fromJson(results[1]);
      final raw = restaurantRes['restaurants'];
      setState(() {
        _restaurants = raw is List
            ? raw.whereType<Map<String, dynamic>>().map(Restaurant.fromJson).toList()
            : [];
        _categories = ['Todos', ...meta.categories];
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final res = await context.read<AppState>().api.notifications();
      final raw = res['notifications'];
      if (raw is List) {
        _notifications = raw.whereType<Map<String, dynamic>>().toList();
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _useGps() async {
    if (_locating) return;
    setState(() => _locating = true);
    final position = await LocationService.currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (position == null) {
      showSnack(context, 'No se pudo obtener tu ubicaciÃ³n. Activa el GPS y dale permiso a VelozEat.', error: true);
      return;
    }
    setState(() {
      _lat = position.latitude;
      _lng = position.longitude;
    });
    await _load();
  }

  Future<void> _clearGps() async {
    setState(() {
      _lat = null;
      _lng = null;
    });
    await _load();
  }

  List<Restaurant> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _restaurants.where((r) {
      final inCategory = _category == 'Todos' || r.category == _category;
      final inQuery = query.isEmpty ||
          r.name.toLowerCase().contains(query) ||
          r.category.toLowerCase().contains(query) ||
          r.description.toLowerCase().contains(query) ||
          r.menu.any((m) => m.name.toLowerCase().contains(query)) ||
          r.popularItems.any((m) => m.name.toLowerCase().contains(query));
      return inCategory && inQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;
    final firstName = (user?.name ?? 'Vecino').split(' ').first;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: kBrand,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            Row(
              children: [
                const AppLogo(size: 21),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Notificaciones'),
                        content: SizedBox(
                          width: double.maxFinite,
                          height: 300,
                          child: _notifications.isEmpty
                              ? const Center(child: Text('Sin notificaciones'))
                              : ListView(
                                  children: _notifications.map((n) => ListTile(
                                    title: Text('${n['title'] ?? ''}'),
                                    subtitle: Text('${n['text'] ?? ''}'),
                                    trailing: n['read'] == true ? null : const Icon(Icons.circle, size: 8, color: kBrand),
                                    onTap: () async {
                                      try { await context.read<AppState>().api.readNotification(n['id'].toString()); } catch (_) {}
                                      await _loadNotifications();
                                    },
                                  )).toList(),
                                ),
                        ),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
                      ),
                    );
                  },
                  icon: Badge(
                    isLabelVisible: _notifications.any((n) => n['read'] != true),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: kBrand.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    firstName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: kBrand, fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Hola, $firstName ð', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 16, color: kBrand),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    (user?.address.isNotEmpty ?? false) ? user!.address : 'Agrega tu direcciÃ³n en tu perfil',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: kMuted, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _locating ? null : (_lat == null ? _useGps : _clearGps),
              child: Row(
                children: [
                  if (_locating)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kBrand))
                  else
                    Icon(_lat == null ? Icons.my_location_rounded : Icons.gps_fixed_rounded,
                        size: 16, color: kBrand),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      _lat == null
                          ? 'Usar mi ubicaciÃ³n actual para calcular el envÃ­o'
                          : 'UbicaciÃ³n GPS activa Â· tocar para quitar',
                      style: const TextStyle(fontSize: 11.5, color: kBrand, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Busca tacos, sushi, pizza...',
                prefixIcon: const Icon(Icons.search_rounded, color: kMuted),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20, color: kMuted),
                        onPressed: () => _search.clear(),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kBrand, kBrandDark],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Antojo a domicilio',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tus restaurantes favoritos, entregados a toda velocidad. Usa BIENVENIDO y ahorra 15%.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5, height: 1.35),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt_rounded, color: Colors.white, size: 14),
                              SizedBox(width: 3),
                              Text('20-35 min',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('ðµ', style: TextStyle(fontSize: 56)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final active = category == _category;
                  return GestureDetector(
                    onTap: () => setState(() => _category = category),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? kInk : Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: active ? kInk : kLine),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: active ? Colors.white : kMuted,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            SectionTitle(
              _search.text.trim().isEmpty ? 'Cerca de ti' : 'Resultados',
              action: '${_filtered.length} lugares',
            ),
            const SizedBox(height: 4),
            if (_loading)
              const LoadingBox(label: 'Buscando restaurantes...')
            else if (_error != null)
              EmptyState(
                emoji: 'ð¡',
                title: 'No pudimos cargar los restaurantes',
                subtitle: _error!,
                action: FilledButton(
                  onPressed: _load,
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 46)),
                  child: const Text('Reintentar'),
                ),
              )
            else if (_filtered.isEmpty)
              EmptyState(
                emoji: 'ð',
                title: _restaurants.isEmpty ? 'Aun no hay restaurantes' : 'Sin resultados',
                subtitle: _restaurants.isEmpty ? 'Se el primero en registrar tu restaurante y empezar a vender.' : 'Prueba con otra busqueda o categoria.',
              )
            else
              ..._filtered.map(
                (restaurant) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RestaurantCard(
                    restaurant: restaurant,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => RestaurantScreen(restaurantId: restaurant.id)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onTap;
  const _RestaurantCard({required this.restaurant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(restaurant.color);
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EmojiBox(emoji: restaurant.emoji, size: 62, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            restaurant.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: kInk),
                          ),
                        ),
                        if (!restaurant.isOpen)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: kMuted.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Cerrado',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: kMuted)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: kAccent),
                        const SizedBox(width: 2),
                        Text(restaurant.rating.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kInk)),
                        Text(' (${restaurant.ratingCount})',
                            style: const TextStyle(fontSize: 11, color: kMuted)),
                        const SizedBox(width: 6),
                        Text('Â· ${restaurant.category}',
                            style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      restaurant.distanceKm == null
                          ? '${restaurant.etaMinutes} min Â· EnvÃ­o desde ${money(restaurant.deliveryFee)} Â· MÃ­n ${money(restaurant.minOrder)}'
                          : '${restaurant.distanceKm!.toStringAsFixed(1)} km Â· ${restaurant.etaMinutes} min Â· EnvÃ­o desde ${money(restaurant.deliveryFee)} Â· MÃ­n ${money(restaurant.minOrder)}',
                      style: const TextStyle(fontSize: 11.5, color: kMuted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (restaurant.popularItems.isNotEmpty) ...[
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  ...restaurant.popularItems.take(3).map((item) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text('${item.emoji} ${item.name.split(' ').take(2).join(' ')}',
                            style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w600)),
                      )),
                  const Spacer(),
                  Text(money(restaurant.popularItems.first.price),
                      style: const TextStyle(fontSize: 11, color: kBrand, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
