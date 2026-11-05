import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models.dart';

class CartLine {
  final MenuItem item;
  final int qty;
  CartLine(this.item, this.qty);
  double get total => item.price * qty;
}

class AppState extends ChangeNotifier {
  final ApiClient api = ApiClient();

  bool loading = true;
  User? user;
  Restaurant? myRestaurant;
  DriverProfile? driverProfile;

  final Map<String, int> _cart = {};
  Restaurant? cartRestaurant;

  bool get isLoggedIn => user != null;
  String get role => user?.role ?? '';

  Future<void> init() async {
    await api.loadToken();
    if (api.hasToken) {
      try {
        final res = await api.me();
        final raw = res['user'];
        if (raw is Map<String, dynamic> && raw['role'] == 'admin') {
          await api.setToken(null);
        } else {
          _applySession(res);
        }
      } catch (_) {
        await api.setToken(null);
      }
    }
    loading = false;
    notifyListeners();
  }

  void _applySession(Map<String, dynamic> res) {
    final rawUser = res['user'];
    if (rawUser is Map<String, dynamic>) user = User.fromJson(rawUser);
    final rawRestaurant = res['restaurant'];
    myRestaurant =
        rawRestaurant is Map<String, dynamic> ? Restaurant.fromJson(rawRestaurant) : null;
    final rawDriver = res['driverProfile'];
    driverProfile = rawDriver is Map<String, dynamic> ? DriverProfile.fromJson(rawDriver) : null;
  }

  Future<void> login(String email, String password) async {
    final res = await api.login(email, password);
    final raw = res['user'];
    if (raw is Map<String, dynamic> && raw['role'] == 'admin') {
      throw ApiException(
        'La administración es privada. Abre el panel en ${api.baseUrl}/admin desde tu navegador.',
      );
    }
    await api.setToken(res['token']?.toString());
    await refresh();
  }

  Future<void> register(Map<String, dynamic> data) async {
    final res = await api.register(data);
    await api.setToken(res['token']?.toString());
    await refresh();
  }

  Future<void> refresh() async {
    final res = await api.me();
    _applySession(res);
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    await api.updateMe(data);
    await refresh();
  }

  Future<void> logout() async {
    await api.setToken(null);
    user = null;
    myRestaurant = null;
    driverProfile = null;
    clearCart();
    notifyListeners();
  }

  // ------------------------------------------------------------- carrito
  int qtyOf(String itemId) => _cart[itemId] ?? 0;

  int get cartCount => _cart.values.fold(0, (sum, qty) => sum + qty);

  List<CartLine> get cartLines {
    final restaurant = cartRestaurant;
    if (restaurant == null) return [];
    return restaurant.menu
        .where((item) => (_cart[item.id] ?? 0) > 0)
        .map((item) => CartLine(item, _cart[item.id]!))
        .toList();
  }

  double get cartSubtotal =>
      cartLines.fold(0, (sum, line) => sum + line.total);

  void addToCart(Restaurant restaurant, MenuItem item) {
    if (cartRestaurant?.id != restaurant.id) {
      _cart.clear();
      cartRestaurant = restaurant;
    }
    _cart[item.id] = (_cart[item.id] ?? 0) + 1;
    notifyListeners();
  }

  void decreaseCart(MenuItem item) {
    final current = _cart[item.id] ?? 0;
    if (current <= 1) {
      _cart.remove(item.id);
    } else {
      _cart[item.id] = current - 1;
    }
    if (_cart.isEmpty) cartRestaurant = null;
    notifyListeners();
  }

  void removeFromCart(MenuItem item) {
    _cart.remove(item.id);
    if (_cart.isEmpty) cartRestaurant = null;
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    cartRestaurant = null;
    notifyListeners();
  }
}
