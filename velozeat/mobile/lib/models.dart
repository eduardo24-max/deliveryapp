double asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? 0;
}

int asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

String asString(dynamic value) => value?.toString() ?? '';

DateTime? asDate(dynamic value) {
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

class User {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String address;
  final String zoneId;
  final String? restaurantId;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.address,
    this.zoneId = '',
    this.restaurantId,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: asString(json['id']),
        name: asString(json['name']),
        email: asString(json['email']),
        phone: asString(json['phone']),
        role: asString(json['role']),
        address: asString(json['address']),
        zoneId: asString(json['zoneId']),
        restaurantId: json['restaurantId'] == null ? null : asString(json['restaurantId']),
      );

  String get roleLabel => switch (role) {
        'restaurant' => 'Restaurante',
        'driver' => 'Repartidor',
        'admin' => 'Administrador',
        _ => 'Cliente',
      };
}

class MenuItem {
  final String id;
  final String name;
  final String description;
  final double price;
  final String category;
  final String emoji;
  final bool available;

  MenuItem({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.category,
    required this.emoji,
    required this.available,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: asString(json['id']),
        name: asString(json['name']),
        description: asString(json['description']),
        price: asDouble(json['price']),
        category: asString(json['category']),
        emoji: asString(json['emoji']).isEmpty ? 'ð½ï¸' : asString(json['emoji']),
        available: json['available'] != false,
      );
}

class Restaurant {
  final String id;
  final String name;
  final String category;
  final String emoji;
  final String color;
  final String description;
  final String address;
  final double lat;
  final double lng;
  final double rating;
  final int ratingCount;
  final double deliveryFee;
  final double minOrder;
  final int etaMinutes;
  final bool isOpen;
  final bool approved;
  final List<MenuItem> menu;
  final int menuCount;
  final List<MenuItem> popularItems;
  final double? distanceKm;

  Restaurant({
    required this.id,
    required this.name,
    required this.category,
    required this.emoji,
    required this.color,
    required this.description,
    required this.address,
    this.lat = 0,
    this.lng = 0,
    required this.rating,
    required this.ratingCount,
    required this.deliveryFee,
    required this.minOrder,
    required this.etaMinutes,
    required this.isOpen,
    required this.approved,
    required this.menu,
    required this.menuCount,
    required this.popularItems,
    this.distanceKm,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    final rawMenu = json['menu'];
    final menu = rawMenu is List
        ? rawMenu.whereType<Map<String, dynamic>>().map(MenuItem.fromJson).toList()
        : <MenuItem>[];
    final rawPopular = json['popularItems'];
    final popular = rawPopular is List
        ? rawPopular.whereType<Map<String, dynamic>>().map(MenuItem.fromJson).toList()
        : <MenuItem>[];
    return Restaurant(
      id: asString(json['id']),
      name: asString(json['name']),
      category: asString(json['category']),
      emoji: asString(json['emoji']).isEmpty ? 'ð½ï¸' : asString(json['emoji']),
      color: asString(json['color']).isEmpty ? '#7C3AED' : asString(json['color']),
      description: asString(json['description']),
      address: asString(json['address']),
      lat: asDouble(json['lat']),
      lng: asDouble(json['lng']),
      rating: asDouble(json['rating']),
      ratingCount: asInt(json['ratingCount']),
      deliveryFee: asDouble(json['deliveryFee']),
      minOrder: asDouble(json['minOrder']),
      etaMinutes: asInt(json['etaMinutes']),
      isOpen: json['isOpen'] == true,
      approved: json['approved'] == true,
      menu: menu,
      distanceKm: json['distanceKm'] == null ? null : asDouble(json['distanceKm']),
      menuCount: json['menuCount'] == null ? menu.length : asInt(json['menuCount']),
      popularItems: popular,
    );
  }
}

class OrderItem {
  final String itemId;
  final String name;
  final String emoji;
  final double price;
  final int qty;

  OrderItem({
    required this.itemId,
    required this.name,
    required this.emoji,
    required this.price,
    required this.qty,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
        itemId: asString(json['itemId']),
        name: asString(json['name']),
        emoji: asString(json['emoji']).isEmpty ? 'ð½ï¸' : asString(json['emoji']),
        price: asDouble(json['price']),
        qty: asInt(json['qty']),
      );
}

class Order {
  final String id;
  final String code;
  final String securityCode;
  final String customerId;
  final String restaurantId;
  final String? driverId;
  final String status;
  final List<OrderItem> items;
  final double subtotal;
  final double deliveryFee;
  final double tip;
  final double total;
  final double driverEarnings;
  final double platformFee;
  final String? couponCode;
  final double discount;
  final double deliveryPlatformFee;
  final double distanceKm;
  final String zoneId;
  final String zoneName;
  final String address;
  final String notes;
  final String paymentMethod;
  final DateTime? createdAt;
  final DateTime? deliveredAt;
  final int? rating;
  final String ratingComment;
  final String restaurantName;
  final String restaurantEmoji;
  final String restaurantColor;
  final String restaurantAddress;
  final String customerName;
  final String customerPhone;
  final String? driverName;
  final String? driverPhone;

  Order({
    required this.id,
    required this.code,
    required this.securityCode,
    required this.customerId,
    required this.restaurantId,
    required this.driverId,
    required this.status,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.tip,
    required this.total,
    required this.driverEarnings,
    required this.platformFee,
    this.couponCode,
    this.discount = 0,
    this.deliveryPlatformFee = 0,
    this.distanceKm = 0,
    this.zoneId = '',
    this.zoneName = '',
    required this.address,
    required this.notes,
    required this.paymentMethod,
    required this.createdAt,
    required this.deliveredAt,
    required this.rating,
    required this.ratingComment,
    required this.restaurantName,
    required this.restaurantEmoji,
    required this.restaurantColor,
    required this.restaurantAddress,
    required this.customerName,
    required this.customerPhone,
    required this.driverName,
    required this.driverPhone,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return Order(
      id: asString(json['id']),
      code: asString(json['code']),
      securityCode: asString(json['securityCode']),
      customerId: asString(json['customerId']),
      restaurantId: asString(json['restaurantId']),
      driverId: json['driverId'] == null ? null : asString(json['driverId']),
      status: asString(json['status']),
      items: rawItems is List
          ? rawItems.whereType<Map<String, dynamic>>().map(OrderItem.fromJson).toList()
          : <OrderItem>[],
      subtotal: asDouble(json['subtotal']),
      deliveryFee: asDouble(json['deliveryFee']),
      tip: asDouble(json['tip']),
      total: asDouble(json['total']),
      driverEarnings: asDouble(json['driverEarnings']),
      platformFee: asDouble(json['platformFee']),
      couponCode: json['couponCode'] == null ? null : asString(json['couponCode']),
      discount: asDouble(json['discount']),
      deliveryPlatformFee: asDouble(json['deliveryPlatformFee']),
      distanceKm: asDouble(json['distanceKm']),
      zoneId: asString(json['zoneId']),
      zoneName: asString(json['zoneName']),
      address: asString(json['address']),
      notes: asString(json['notes']),
      paymentMethod: asString(json['paymentMethod']),
      createdAt: asDate(json['createdAt']),
      deliveredAt: asDate(json['deliveredAt']),
      rating: json['rating'] == null ? null : asInt(json['rating']),
      ratingComment: asString(json['ratingComment']),
      restaurantName: asString(json['restaurantName']),
      restaurantEmoji: asString(json['restaurantEmoji']).isEmpty ? 'ð½ï¸' : asString(json['restaurantEmoji']),
      restaurantColor: asString(json['restaurantColor']).isEmpty ? '#7C3AED' : asString(json['restaurantColor']),
      restaurantAddress: asString(json['restaurantAddress']),
      customerName: asString(json['customerName']),
      customerPhone: asString(json['customerPhone']),
      driverName: json['driverName'] == null ? null : asString(json['driverName']),
      driverPhone: json['driverPhone'] == null ? null : asString(json['driverPhone']),
    );
  }

  bool get isActive => const [
        'pending',
        'accepted',
        'preparing',
        'ready',
        'assigned',
        'picked_up'
      ].contains(status);

  bool get isFinished => status == 'delivered' || status == 'cancelled';
}

class DriverProfile {
  final String vehicle;
  final bool isOnline;
  final double rating;
  final int deliveries;
  final double earnings;

  DriverProfile({
    required this.vehicle,
    required this.isOnline,
    required this.rating,
    required this.deliveries,
    required this.earnings,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
        vehicle: asString(json['vehicle']),
        isOnline: json['isOnline'] == true,
        rating: asDouble(json['rating']),
        deliveries: asInt(json['deliveries']),
        earnings: asDouble(json['earnings']),
      );

  String get vehicleLabel => switch (vehicle) {
        'bici' => 'Bicicleta',
        'auto' => 'Auto',
        _ => 'Moto',
      };

  String get vehicleEmoji => switch (vehicle) {
        'bici' => 'ð²',
        'auto' => 'ð',
        _ => 'ðµ',
      };
}

class PaymentMethod {
  final String id;
  final String label;
  final String emoji;
  final String detail;

  PaymentMethod({required this.id, required this.label, required this.emoji, required this.detail});

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
        id: asString(json['id']),
        label: asString(json['label']),
        emoji: asString(json['emoji']),
        detail: asString(json['detail']),
      );
}

class Zone {
  final String id;
  final String name;
  final double lat;
  final double lng;

  Zone({required this.id, required this.name, this.lat = 0, this.lng = 0});

  factory Zone.fromJson(Map<String, dynamic> json) => Zone(
        id: asString(json['id']),
        name: asString(json['name']),
        lat: asDouble(json['lat']),
        lng: asDouble(json['lng']),
      );
}

class DeliverySettings {
  final double baseFee;
  final double perKm;
  final double minFee;
  final double maxFee;
  final double driverSharePct;

  const DeliverySettings({
    this.baseFee = 12,
    this.perKm = 4,
    this.minFee = 15,
    this.maxFee = 70,
    this.driverSharePct = 0.8,
  });

  factory DeliverySettings.fromJson(Map<String, dynamic> json) => DeliverySettings(
        baseFee: asDouble(json['baseFee']),
        perKm: asDouble(json['perKm']),
        minFee: asDouble(json['minFee']),
        maxFee: asDouble(json['maxFee']),
        driverSharePct: asDouble(json['driverSharePct']),
      );
}

class DeliveryQuote {
  final String zoneId;
  final String zoneName;
  final double distanceKm;
  final double deliveryFee;
  final double driverEarnings;
  final double deliveryPlatformFee;
  final bool outOfRange;
  final double maxRadiusKm;

  DeliveryQuote({
    required this.zoneId,
    required this.zoneName,
    required this.distanceKm,
    required this.deliveryFee,
    required this.driverEarnings,
    required this.deliveryPlatformFee,
    this.outOfRange = false,
    this.maxRadiusKm = 25,
  });

  factory DeliveryQuote.fromJson(Map<String, dynamic> json) => DeliveryQuote(
        zoneId: asString(json['zoneId']),
        zoneName: asString(json['zoneName']),
        distanceKm: asDouble(json['distanceKm']),
        deliveryFee: asDouble(json['deliveryFee']),
        driverEarnings: asDouble(json['driverEarnings']),
        deliveryPlatformFee: asDouble(json['deliveryPlatformFee']),
        outOfRange: json['outOfRange'] == true,
        maxRadiusKm: asDouble(json['maxRadiusKm']),
      );
}

class TrackingInfo {
  final String status;
  final double? restaurantLat;
  final double? restaurantLng;
  final String? restaurantName;
  final String? restaurantAddress;
  final double? customerLat;
  final double? customerLng;
  final String? customerAddress;
  final String? driverName;
  final String? driverPhone;
  final double? driverLat;
  final double? driverLng;
  final String? driverVehicle;
  final bool driverOnline;
  final double distanceKm;

  TrackingInfo({
    required this.status,
    this.restaurantLat,
    this.restaurantLng,
    this.restaurantName,
    this.restaurantAddress,
    this.customerLat,
    this.customerLng,
    this.customerAddress,
    this.driverName,
    this.driverPhone,
    this.driverLat,
    this.driverLng,
    this.driverVehicle,
    this.driverOnline = false,
    this.distanceKm = 0,
  });

  factory TrackingInfo.fromJson(Map<String, dynamic> json) {
    final r = json['restaurant'];
    final c = json['customer'];
    final d = json['driver'];
    double? dn(dynamic v) => v == null ? null : asDouble(v);
    return TrackingInfo(
      status: asString(json['status']),
      restaurantLat: r is Map ? dn(r['lat']) : null,
      restaurantLng: r is Map ? dn(r['lng']) : null,
      restaurantName: r is Map ? asString(r['name']) : null,
      restaurantAddress: r is Map ? asString(r['address']) : null,
      customerLat: c is Map ? dn(c['lat']) : null,
      customerLng: c is Map ? dn(c['lng']) : null,
      customerAddress: c is Map ? asString(c['address']) : null,
      driverName: d is Map ? asString(d['name']) : null,
      driverPhone: d is Map ? asString(d['phone']) : null,
      driverLat: d is Map ? dn(d['lat']) : null,
      driverLng: d is Map ? dn(d['lng']) : null,
      driverVehicle: d is Map ? asString(d['vehicle']) : null,
      driverOnline: d is Map && d['isOnline'] == true,
      distanceKm: asDouble(json['distanceKm']),
    );
  }
}

class Meta {
  final List<String> categories;
  final List<PaymentMethod> paymentMethods;
  final List<Zone> zones;
  final DeliverySettings delivery;

  Meta({
    required this.categories,
    required this.paymentMethods,
    this.zones = const [],
    this.delivery = const DeliverySettings(),
  });

  factory Meta.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    final rawPayments = json['paymentMethods'];
    final rawZones = json['zones'];
    final rawDelivery = json['delivery'];
    return Meta(
      categories: rawCategories is List
          ? rawCategories.map((e) => e.toString()).toList()
          : <String>[],
      paymentMethods: rawPayments is List
          ? rawPayments
              .whereType<Map<String, dynamic>>()
              .map(PaymentMethod.fromJson)
              .toList()
          : <PaymentMethod>[],
      zones: rawZones is List
          ? rawZones.whereType<Map<String, dynamic>>().map(Zone.fromJson).toList()
          : <Zone>[],
      delivery: rawDelivery is Map<String, dynamic>
          ? DeliverySettings.fromJson(rawDelivery)
          : const DeliverySettings(),
    );
  }
}
