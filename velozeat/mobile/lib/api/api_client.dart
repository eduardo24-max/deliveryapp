import 'dart:convert';

import 'package:http/http.dart' as http;

// shared_preferences was removed to avoid NDK/datastore dependencies in offline builds.

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class ApiClient {
  String? _token;
  String? _baseUrlOverride;

  String get baseUrl {
    if (_baseUrlOverride != null && _baseUrlOverride!.isNotEmpty) return _baseUrlOverride!;
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;
    return 'http://10.0.2.2:3100';
  }

  void setBaseUrl(String? url) {
    final trimmed = url?.trim();
    _baseUrlOverride = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  bool get hasToken => _token != null && _token!.isNotEmpty;
  String? get token => _token;

  Future<void> loadToken() async {
    // Token persistence disabled in this build; users log in per session.
  }

  Future<void> setToken(String? token) async {
    _token = token;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (hasToken) 'Authorization': 'Bearer $_token',
    };

    http.Response response;
    try {
      final encoded = body == null ? null : jsonEncode(body);
      response = switch (method) {
        'POST' => await http.post(uri, headers: headers, body: encoded).timeout(const Duration(seconds: 20)),
        'PUT' => await http.put(uri, headers: headers, body: encoded).timeout(const Duration(seconds: 20)),
        'DELETE' => await http.delete(uri, headers: headers).timeout(const Duration(seconds: 20)),
        _ => await http.get(uri, headers: headers).timeout(const Duration(seconds: 20)),
      };
    } on http.ClientException {
      throw ApiException('No se pudo conectar con VelozEat. Verifica que el servidor esté encendido.');
    } catch (_) {
      throw ApiException('Sin conexión con el servidor. Revisa tu red e intenta de nuevo.');
    }

    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {
        data = {};
      }
    }

    if (response.statusCode >= 400) {
      throw ApiException((data['error'] ?? 'Ocurrió un error (${response.statusCode}).').toString());
    }
    return data;
  }

  // Auth
  Future<Map<String, dynamic>> login(String email, String password) => _request('POST', '/api/auth/login', body: {'email': email, 'password': password});

  Future<Map<String, dynamic>> resendVerification(String email) => _request('POST', '/api/auth/resend-verification', body: {'email': email});

  Future<Map<String, dynamic>> verifyOtp(String email, String code) =>
      _request('POST', '/api/auth/verify-otp', body: {'email': email, 'code': code});

  Future<Map<String, dynamic>> resendOtp(String email) =>
      _request('POST', '/api/auth/resend-otp', body: {'email': email});

  Future<Map<String, dynamic>> wallet() => _request('GET', '/api/wallet');
  Future<Map<String, dynamic>> topupWallet(double amount) => _request('POST', '/api/wallet/topup', body: {'amount': amount});

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) => _request('POST', '/api/auth/register', body: data);

  Future<Map<String, dynamic>> me() => _request('GET', '/api/me');

  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> data) => _request('PUT', '/api/me', body: data);

  Future<Map<String, dynamic>> meta() => _request('GET', '/api/meta');

  // Restaurantes
  Future<Map<String, dynamic>> restaurants({
    String? q,
    String? category,
    double? lat,
    double? lng,
  }) => _request(
    'GET',
    '/api/restaurants',
    query: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (category != null && category.isNotEmpty) 'category': category,
      if (lat != null && lng != null) 'lat': '$lat',
      if (lat != null && lng != null) 'lng': '$lng',
    },
  );

  Future<Map<String, dynamic>> restaurant(String id) => _request('GET', '/api/restaurants/$id');

  Future<Map<String, dynamic>> quote(String restaurantId, String zoneId, {double? lat, double? lng}) => _request(
    'GET',
    '/api/restaurants/$restaurantId/quote',
    query: {
      if (zoneId.isNotEmpty) 'zoneId': zoneId,
      if (lat != null && lng != null) 'lat': '$lat',
      if (lat != null && lng != null) 'lng': '$lng',
    },
  );

  Future<Map<String, dynamic>> updateRestaurant(String id, Map<String, dynamic> data) => _request('PUT', '/api/restaurants/$id', body: data);

  Future<Map<String, dynamic>> addMenuItem(String restaurantId, Map<String, dynamic> data) => _request('POST', '/api/restaurants/$restaurantId/menu', body: data);

  Future<Map<String, dynamic>> updateMenuItem(
    String restaurantId,
    String itemId,
    Map<String, dynamic> data,
  ) => _request('PUT', '/api/restaurants/$restaurantId/menu/$itemId', body: data);

  Future<Map<String, dynamic>> deleteMenuItem(String restaurantId, String itemId) => _request('DELETE', '/api/restaurants/$restaurantId/menu/$itemId');

  // Pedidos
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> data) => _request('POST', '/api/orders', body: data);

  Future<Map<String, dynamic>> validateCoupon(String code, String restaurantId, double subtotal) => _request('POST', '/api/coupons/validate', body: {
    'code': code,
    'restaurantId': restaurantId,
    'subtotal': subtotal,
  });

  Future<Map<String, dynamic>> orders({String? status}) => _request(
    'GET',
    '/api/orders',
    query: {if (status != null && status.isNotEmpty) 'status': status},
  );

  Future<Map<String, dynamic>> order(String id) => _request('GET', '/api/orders/$id');
  Future<Map<String, dynamic>> tracking(String id) => _request('GET', '/api/orders/$id/tracking');

  Future<Map<String, dynamic>> messages(String orderId) => _request('GET', '/api/orders/$orderId/messages');
  Future<Map<String, dynamic>> sendMessage(String orderId, String text) => _request('POST', '/api/orders/$orderId/messages', body: {'text': text});

  Future<Map<String, dynamic>> notifications() => _request('GET', '/api/notifications');
  Future<Map<String, dynamic>> readNotification(String id) => _request('POST', '/api/notifications/$id/read');

  Future<Map<String, dynamic>> acceptOrder(String id) => _request('POST', '/api/orders/$id/accept');
  Future<Map<String, dynamic>> prepareOrder(String id) => _request('POST', '/api/orders/$id/prepare');
  Future<Map<String, dynamic>> readyOrder(String id) => _request('POST', '/api/orders/$id/ready');

  Future<Map<String, dynamic>> cancelOrder(String id, {String? reason}) => _request('POST', '/api/orders/$id/cancel', body: {'reason': reason ?? 'Cancelado'});

  Future<Map<String, dynamic>> rateOrder(String id, int rating, String comment) => _request('POST', '/api/orders/$id/rate', body: {'rating': rating, 'comment': comment});

  Future<Map<String, dynamic>> claimOrder(String id) => _request('POST', '/api/orders/$id/claim');
  Future<Map<String, dynamic>> pickupOrder(String id) => _request('POST', '/api/orders/$id/pickup');
  Future<Map<String, dynamic>> deliverOrder(String id, String code) => _request('POST', '/api/orders/$id/deliver', body: {'code': code});

  // Repartidor
  Future<Map<String, dynamic>> driverAvailable() => _request('GET', '/api/driver/available');
  Future<Map<String, dynamic>> driverSummary() => _request('GET', '/api/driver/summary');
  Future<Map<String, dynamic>> setDriverOnline(bool isOnline) => _request('POST', '/api/driver/status', body: {'isOnline': isOnline});
  Future<Map<String, dynamic>> updateDriverLocation(double lat, double lng) => _request('PUT', '/api/driver/location', body: {'lat': lat, 'lng': lng});

  Future<Map<String, dynamic>> setDriverLocation(double lat, double lng, {bool? isOnline}) => _request('POST', '/api/driver/status', body: {
    'isOnline': isOnline,
    'lat': lat,
    'lng': lng,
  });

  // Paneles
  Future<Map<String, dynamic>> restaurantDashboard() => _request('GET', '/api/dashboard/restaurant');
  Future<Map<String, dynamic>> adminStats() => _request('GET', '/api/admin/stats');
  Future<Map<String, dynamic>> adminRestaurants() => _request('GET', '/api/admin/restaurants');
  Future<Map<String, dynamic>> adminOrders() => _request('GET', '/api/admin/orders');
  Future<Map<String, dynamic>> approveRestaurant(String id, bool approved) => _request('POST', '/api/admin/restaurants/$id/approve', body: {'approved': approved});
}