const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DATA_FILE = path.join(__dirname, 'data.json');

function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
    const hash = crypto.scryptSync(String(password), salt, 64).toString('hex');
    return `${salt}:${hash}`;
}

function verifyPassword(password, stored) {
    if (!stored || !stored.includes(':')) return false;
    const [salt, hash] = stored.split(':');
    const candidate = crypto.scryptSync(String(password), salt, 64);
    const expected = Buffer.from(hash, 'hex');
    return candidate.length === expected.length && crypto.timingSafeEqual(candidate, expected);
}

const now = Date.now();
const HOUR = 60 * 60 * 1000;

// Zonas de entrega de ejemplo (CDMX). La tarifa se calcula por distancia.
const DEFAULT_ZONES = [
    { id: 'z-centro', name: 'Centro / Reforma', lat: 19.4326, lng: -99.1332 },
    { id: 'z-roma', name: 'Roma / Condesa', lat: 19.4148, lng: -99.1650 },
    { id: 'z-juarez', name: 'JuÃÂ¡rez / Zona Rosa', lat: 19.4260, lng: -99.1600 },
    { id: 'z-guerrero', name: 'Guerrero', lat: 19.4450, lng: -99.1480 },
    { id: 'z-delvalle', name: 'Del Valle', lat: 19.3800, lng: -99.1650 },
    { id: 'z-narvarte', name: 'Narvarte', lat: 19.3900, lng: -99.1500 },
    { id: 'z-polanco', name: 'Polanco', lat: 19.4330, lng: -99.1990 },
    { id: 'z-coyoacan', name: 'CoyoacÃÂ¡n', lat: 19.3500, lng: -99.1620 }
];

const DEFAULT_DELIVERY = {
    baseFee: 12,
    perKm: 4,
    minFee: 15,
    maxFee: 70,
    driverSharePct: 0.8,
    maxRadiusKm: 25
};

const RESTAURANT_COORDS = {
    'r-tacos': { lat: 19.4326, lng: -99.1332 },
    'r-sushi': { lat: 19.4380, lng: -99.1500 },
    'r-burger': { lat: 19.4300, lng: -99.1400 },
    'r-pizza': { lat: 19.4160, lng: -99.1600 },
    'r-antojitos': { lat: 19.4450, lng: -99.1480 },
    'r-dulce': { lat: 19.4260, lng: -99.1600 }
};

function haversineKm(a, b) {
    const rad = (v) => (Number(v) * Math.PI) / 180;
    const dLat = rad(b.lat - a.lat);
    const dLng = rad(b.lng - a.lng);
    const h = Math.sin(dLat / 2) ** 2 +
        Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
    return 6371 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

function migrate(data) {
    let changed = false;
    data.driverLocations = data.driverLocations || {};
    data.settings = data.settings || {};
    if (!data.settings.delivery) {
        data.settings.delivery = { ...DEFAULT_DELIVERY };
        changed = true;
    } else {
        const merged = { ...DEFAULT_DELIVERY, ...data.settings.delivery };
        if (JSON.stringify(merged) !== JSON.stringify(data.settings.delivery)) {
            data.settings.delivery = merged;
            changed = true;
        }
    }
    if (!Array.isArray(data.messages)) {
        data.messages = [];
        changed = true;
    }
    if (!Array.isArray(data.notifications)) {
        data.notifications = [];
        changed = true;
    }
    if (!Array.isArray(data.coupons)) {
        data.coupons = [];
        changed = true;
    }
    if (!Array.isArray(data.settings.zones) || data.settings.zones.length === 0) {
        data.settings.zones = DEFAULT_ZONES.map((z) => ({ ...z }));
        changed = true;
    }

    for (const restaurant of data.restaurants || []) {
        if (!Number.isFinite(restaurant.lat) || !Number.isFinite(restaurant.lng)) {
            const coords = RESTAURANT_COORDS[restaurant.id] || DEFAULT_ZONES[0];
            restaurant.lat = coords.lat;
            restaurant.lng = coords.lng;
            changed = true;
        }
    }

    for (const user of data.users || []) {
        if (user.walletBalance === undefined) {
            user.walletBalance = 0;
            changed = true;
        }
        if (user.emailVerified === undefined) {
            user.emailVerified = true;
            changed = true;
        }
        if (user.role === 'customer' && !user.zoneId) {
            user.zoneId = user.address && /roma|condesa/i.test(user.address) ? 'z-roma' : 'z-centro';
            changed = true;
        }
    }

    for (const order of data.orders || []) {
        if (order.distanceKm === undefined) {
            const restaurant = (data.restaurants || []).find((r) => r.id === order.restaurantId);
            const customer = (data.users || []).find((u) => u.id === order.customerId);
            const zone = (data.settings.zones || []).find((z) => z.id === (customer && customer.zoneId)) ||
                (data.settings.zones || [])[0];
            order.zoneId = order.zoneId || (zone && zone.id) || 'z-centro';
            order.zoneName = order.zoneName || (zone && zone.name) || 'Centro / Reforma';
            order.distanceKm = restaurant && zone
                ? Math.round(haversineKm(restaurant, zone) * 1.25 * 10) / 10
                : 0;
            changed = true;
        }
        if (order.deliveryPlatformFee === undefined) {
            // Pedidos anteriores al cobro por distancia: no tenÃÂ­an comisiÃÂ³n de envÃÂ­o.
            order.deliveryPlatformFee = 0;
            changed = true;
        }
    }
    return changed;
}

function item(id, name, description, price, category, emoji) {
    return { id, name, description, price, category, emoji, available: true };
}

function seed() {
    const users = [
        {
            id: 'u-admin', name: 'Equipo VelozEat', email: 'admin@velozeat.com', phone: '5550000001',
            role: 'admin', passwordHash: hashPassword('admin123'), createdAt: now
        },
        {
            id: 'u-cust-1', name: 'Ana Torres', email: 'cliente@velozeat.com', phone: '5551112233',
            role: 'customer', passwordHash: hashPassword('cliente123'), address: 'Av. Reforma 123, Col. Centro',
            zoneId: 'z-centro', createdAt: now
        },
        {
            id: 'u-cust-2', name: 'Luis RamÃÂ­rez', email: 'luis@velozeat.com', phone: '5554445566',
            role: 'customer', passwordHash: hashPassword('cliente123'), address: 'Calle Hidalgo 45, Col. Roma',
            zoneId: 'z-roma', createdAt: now
        },
        {
            id: 'u-rest-1', name: 'MarÃÂ­a Fuentes', email: 'taqueria@velozeat.com', phone: '5557778899',
            role: 'restaurant', restaurantId: 'r-tacos', passwordHash: hashPassword('restaurante123'), createdAt: now
        },
        {
            id: 'u-rest-2', name: 'Kenji Sato', email: 'sushi@velozeat.com', phone: '5552223344',
            role: 'restaurant', restaurantId: 'r-sushi', passwordHash: hashPassword('restaurante123'), createdAt: now
        },
        {
            id: 'u-rest-3', name: 'Carla MÃÂ©ndez', email: 'burger@velozeat.com', phone: '5553334455',
            role: 'restaurant', restaurantId: 'r-burger', passwordHash: hashPassword('restaurante123'), createdAt: now
        },
        {
            id: 'u-driver-1', name: 'Diego LÃÂ³pez', email: 'repartidor@velozeat.com', phone: '5559990011',
            role: 'driver', passwordHash: hashPassword('repartidor123'), createdAt: now
        },
        {
            id: 'u-driver-2', name: 'SofÃÂ­a Cruz', email: 'sofia@velozeat.com', phone: '5558880022',
            role: 'driver', passwordHash: hashPassword('repartidor123'), createdAt: now
        }
    ];

    const restaurants = [
        {
            id: 'r-tacos', ownerId: 'u-rest-1', name: 'TaquerÃÂ­a El Fuego', category: 'Tacos', emoji: 'Ã°ÂÂÂ®',
            color: '#F97316', description: 'Tacos al pastor, gringas y salsas de la casa. Fuego lento, sabor rÃÂ¡pido.',
            address: 'Av. JuÃÂ¡rez 220, Centro', lat: 19.4326, lng: -99.1332,
            rating: 4.8, ratingCount: 312, deliveryFee: 15, minOrder: 80,
            etaMinutes: 25, isOpen: true, approved: true, createdAt: now,
            menu: [
                item('m-taco-1', 'Tacos al pastor (3)', 'Cerdo marinado, piÃÂ±a, cebolla y cilantro', 45, 'Tacos', 'Ã°ÂÂÂ®'),
                item('m-taco-2', 'Tacos de bistec (3)', 'Res a la plancha con cebolla asada', 49, 'Tacos', 'Ã°ÂÂ¥Â©'),
                item('m-taco-3', 'Gringa de pastor', 'Tortilla de harina, queso y pastor', 75, 'Tacos', 'Ã°ÂÂ«Â'),
                item('m-taco-4', 'Quesadilla mixta', 'Queso Oaxaca, pollo y champinones', 55, 'Antojitos', 'Ã°ÂÂ§Â'),
                item('m-taco-5', 'Nachos El Fuego', 'Totopos, frijol, queso, jalapeno y crema', 60, 'Antojitos', 'Ã°ÂÂ§Â'),
                item('m-taco-6', 'Horchata 1L', 'Agua de horchata artesanal', 30, 'Bebidas', 'Ã°ÂÂ¥Â¤'),
                item('m-taco-7', 'Agua de jamaica 1L', 'Jamaica natural, poco azucar', 25, 'Bebidas', 'Ã°ÂÂÂ¹'),
                item('m-taco-8', 'Flan napolitano', 'Casero con caramelo', 35, 'Postres', 'Ã°ÂÂÂ®')
            ]
        },
        {
            id: 'r-sushi', ownerId: 'u-rest-2', name: 'Sushi Zen', category: 'Sushi', emoji: 'Ã°ÂÂÂ£',
            color: '#0EA5E9', description: 'Rolls frescos, ramen caliente y tÃÂ© verde. Cocina japonesa al momento.',
            address: 'Blvd. Marina 88, Local 4', lat: 19.4380, lng: -99.1500,
            rating: 4.7, ratingCount: 198, deliveryFee: 25, minOrder: 150,
            etaMinutes: 35, isOpen: true, approved: true, createdAt: now,
            menu: [
                item('m-sushi-1', 'Sushi roll zen (8pz)', 'Salmon, aguacate, queso crema y ajonjoli', 120, 'Sushi', 'Ã°ÂÂÂ£'),
                item('m-sushi-2', 'California roll (8pz)', 'Surimi, pepino y aguacate', 110, 'Sushi', 'Ã°ÂÂÂ±'),
                item('m-sushi-3', 'Nigiri mix (5pz)', 'Salmon, atun y camarÃÂ³n', 95, 'Sushi', 'Ã°ÂÂÂ¤'),
                item('m-sushi-4', 'Ramen tonkotsu', 'Caldo de cerdo, huevo, naruto y cebollin', 130, 'Calientes', 'Ã°ÂÂÂ'),
                item('m-sushi-5', 'Edamame', 'Vainas de soya con sal de mar', 55, 'Entradas', 'Ã°ÂÂ«Â'),
                item('m-sushi-6', 'TÃÂ© verde caliente', 'Sencha japonÃÂ©s', 30, 'Bebidas', 'Ã°ÂÂÂµ'),
                item('m-sushi-7', 'Mochi de matcha', 'Dos piezas de mochi relleno', 45, 'Postres', 'Ã°ÂÂÂ¡')
            ]
        },
        {
            id: 'r-burger', ownerId: 'u-rest-3', name: 'Burger Lab', category: 'Hamburguesas', emoji: 'Ã°ÂÂÂ',
            color: '#DC2626', description: 'Carne 100% res, pan brioche y salsas de autor. Ciencia del sabor.',
            address: 'Calle FÃÂ­sica 12, Col. Centro', lat: 19.4300, lng: -99.1400,
            rating: 4.6, ratingCount: 421, deliveryFee: 20, minOrder: 100,
            etaMinutes: 30, isOpen: true, approved: true, createdAt: now,
            menu: [
                item('m-burger-1', 'ClÃÂ¡sica Lab', 'Res 150g, queso americano, lechuga y tomate', 95, 'Hamburguesas', 'Ã°ÂÂÂ'),
                item('m-burger-2', 'Doble queso', 'Dos carnes, doble queso y tocino', 135, 'Hamburguesas', 'Ã°ÂÂÂ'),
                item('m-burger-3', 'Papas rÃÂºsticas', 'Papas con paprika y alioli', 45, 'Extras', 'Ã°ÂÂÂ'),
                item('m-burger-4', 'Alitas BBQ (8pz)', 'Alitas glaseadas con BBQ de la casa', 120, 'Extras', 'Ã°ÂÂÂ'),
                item('m-burger-5', 'Malteada de chocolate', 'Helado, leche y chocolate belga', 55, 'Bebidas', 'Ã°ÂÂ¥Â¤'),
                item('m-burger-6', 'Brownie con helado', 'Brownie tibio y helado de vainilla', 50, 'Postres', 'Ã°ÂÂÂ«')
            ]
        },
        {
            id: 'r-pizza', ownerId: 'u-rest-3', name: 'PizzerÃÂ­a Roma', category: 'Pizza', emoji: 'Ã°ÂÂÂ',
            color: '#16A34A', description: 'Masa madre, horno de piedra y ingredientes italianos.',
            address: 'Av. ÃÂlvaro ObregÃÂ³n 301, Roma Norte', lat: 19.4160, lng: -99.1600,
            rating: 4.9, ratingCount: 156, deliveryFee: 25,
            minOrder: 120, etaMinutes: 35, isOpen: true, approved: true, createdAt: now,
            menu: [
                item('m-pizza-1', 'Pizza margarita', 'Salsa de tomate, mozzarella y albahaca', 150, 'Pizza', 'Ã°ÂÂÂ'),
                item('m-pizza-2', 'Pizza pepperoni', 'Pepperoni, mozzarella y orÃÂ©gano', 180, 'Pizza', 'Ã°ÂÂÂ'),
                item('m-pizza-3', 'Pizza hawaiana', 'Jamon, piÃÂ±a y mozzarella', 170, 'Pizza', 'Ã°ÂÂÂ'),
                item('m-pizza-4', 'Pan de ajo', 'Con mantequilla de ajo y perejil', 45, 'Entradas', 'Ã°ÂÂ¥Â'),
                item('m-pizza-5', 'Refresco 600ml', 'Bien frÃÂ­o', 30, 'Bebidas', 'Ã°ÂÂ¥Â¤')
            ]
        },
        {
            id: 'r-antojitos', ownerId: 'u-rest-1', name: 'Antojitos DoÃÂ±a Luz', category: 'Antojitos', emoji: 'Ã°ÂÂ«Â',
            color: '#DB2777', description: 'Tamales, pozole y sopes como los de casa. TradiciÃÂ³n de barrio.',
            address: 'Calle Morelos 55, Col. Guerrero', lat: 19.4450, lng: -99.1480,
            rating: 4.5, ratingCount: 89, deliveryFee: 10,
            minOrder: 60, etaMinutes: 20, isOpen: true, approved: true, createdAt: now,
            menu: [
                item('m-ant-1', 'Tamales (3)', 'Verde, rojo y dulce', 35, 'Tamales', 'Ã°ÂÂ«Â'),
                item('m-ant-2', 'Pozole rojo', 'Con tostadas, orÃÂ©gano y limÃÂ³n', 90, 'Calientes', 'Ã°ÂÂÂ²'),
                item('m-ant-3', 'Enchiladas verdes', 'Pollo, crema y queso fresco', 75, 'Calientes', 'Ã°ÂÂÂ¯'),
                item('m-ant-4', 'Sopes (4)', 'Frijol, salsa, queso y crema', 50, 'Antojitos', 'Ã°ÂÂ«Â'),
                item('m-ant-5', 'Agua fresca 1L', 'Del dÃÂ­a', 25, 'Bebidas', 'Ã°ÂÂ¥Â¤')
            ]
        },
        {
            id: 'r-dulce', ownerId: 'u-rest-3', name: 'Dulce Veloz', category: 'Postres', emoji: 'Ã°ÂÂÂ°',
            color: '#A855F7', description: 'Pasteles, churros y cafÃÂ© para cerrar con algo dulce.',
            address: 'Calle Dulce 8, Col. JuÃÂ¡rez', lat: 19.4260, lng: -99.1600,
            rating: 4.8, ratingCount: 64, deliveryFee: 15,
            minOrder: 50, etaMinutes: 20, isOpen: true, approved: true, createdAt: now,
            menu: [
                item('m-dulce-1', 'Rebanada de pastel', 'Chocolate, tres leches o red velvet', 55, 'Postres', 'Ã°ÂÂÂ°'),
                item('m-dulce-2', 'Churros (5)', 'Con azÃÂºcar y cajeta', 40, 'Postres', 'Ã°ÂÂÂ©'),
                item('m-dulce-3', 'Gelatina de mosaico', 'Casera', 25, 'Postres', 'Ã°ÂÂÂ®'),
                item('m-dulce-4', 'CafÃÂ© americano', 'Grano de la casa', 30, 'Bebidas', 'Ã¢ÂÂ')
            ]
        }
    ];

    const orders = [
        {
            id: 'o-seed-1', code: '1042', securityCode: '4821', customerId: 'u-cust-1', restaurantId: 'r-tacos',
            driverId: 'u-driver-1', status: 'delivered', paymentMethod: 'cash',
            items: [
                { itemId: 'm-taco-1', name: 'Tacos al pastor (3)', emoji: 'Ã°ÂÂÂ®', price: 45, qty: 2 },
                { itemId: 'm-taco-6', name: 'Horchata 1L', emoji: 'Ã°ÂÂ¥Â¤', price: 30, qty: 1 }
            ],
            subtotal: 120, deliveryFee: 15, tip: 20, total: 155, driverEarnings: 35, platformFee: 18,
            address: 'Av. Reforma 123, Col. Centro', notes: 'Sin cebolla por favor',
            createdAt: now - 26 * HOUR, acceptedAt: now - 26 * HOUR, readyAt: now - 25.6 * HOUR,
            pickedAt: now - 25.5 * HOUR, deliveredAt: now - 25.2 * HOUR, rating: 5, ratingComment: 'Todo bien'
        },
        {
            id: 'o-seed-2', code: '1043', securityCode: '7734', customerId: 'u-cust-2', restaurantId: 'r-sushi',
            driverId: 'u-driver-2', status: 'delivered', paymentMethod: 'card',
            items: [
                { itemId: 'm-sushi-1', name: 'Sushi roll zen (8pz)', emoji: 'Ã°ÂÂÂ£', price: 120, qty: 1 },
                { itemId: 'm-sushi-6', name: 'TÃÂ© verde caliente', emoji: 'Ã°ÂÂÂµ', price: 30, qty: 2 }
            ],
            subtotal: 180, deliveryFee: 25, tip: 15, total: 220, driverEarnings: 40, platformFee: 27,
            address: 'Calle Hidalgo 45, Col. Roma', notes: '',
            createdAt: now - 6 * HOUR, acceptedAt: now - 6 * HOUR, readyAt: now - 5.6 * HOUR,
            pickedAt: now - 5.5 * HOUR, deliveredAt: now - 5.1 * HOUR, rating: 4, ratingComment: ''
        }
    ];

    return {
        settings: {
            brand: 'VelozEat',
            currency: 'MXN',
            commissionPct: 0.15,
            city: 'Ciudad de MÃÂ©xico',
            delivery: { ...DEFAULT_DELIVERY },
            zones: DEFAULT_ZONES.map((z) => ({ ...z }))
        },
        users,
        restaurants,
        orders,
        messages: [],
        notifications: [],
        coupons: [
            { id: 'c-bienvenido', code: 'BIENVENIDO', type: 'percent', value: 15, minOrder: 100, maxDiscount: 50, active: true, expiresAt: now + 30*24*60*60*1000, usageLimit: 1000, usedCount: 0 },
            { id: 'c-envio', code: 'ENVIOGRATIS', type: 'fixed', value: 30, minOrder: 150, maxDiscount: 30, active: true, expiresAt: now + 30*24*60*60*1000, usageLimit: 500, usedCount: 0 }
        ],
        driverProfiles: [
            { userId: 'u-driver-1', vehicle: 'moto', isOnline: true, rating: 4.9, deliveries: 128, earnings: 0, lat: 19.4326, lng: -99.1332 },
            { userId: 'u-driver-2', vehicle: 'bici', isOnline: true, rating: 4.8, deliveries: 74, earnings: 0, lat: 19.4270, lng: -99.1430 }
        ]
    };
}

let db = null;

function load() {
    if (db) return db;
    try {
        if (fs.existsSync(DATA_FILE)) {
            // Tolerate UTF-8 BOM if some tool added one, otherwise JSON.parse throws and data is lost.
            const raw = fs.readFileSync(DATA_FILE, 'utf8').replace(/^\uFEFF/, '');
            db = JSON.parse(raw);
            if (migrate(db)) save();
            return db;
        }
    } catch (err) {
        console.error('No se pudo leer data.json, se regenera:', err.message);
    }
    db = seed();
    migrate(db);
    save();
    return db;
}

function save() {
    if (!db) return;
    const tmp = `${DATA_FILE}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(db, null, 2), 'utf8');
    fs.renameSync(tmp, DATA_FILE);
}

function reset() {
    db = seed();
    save();
    return db;
}

module.exports = { load, save, reset, hashPassword, verifyPassword, DATA_FILE };
