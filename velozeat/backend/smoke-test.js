/**
 * Prueba de humo de la API VelozEat.
 * Uso: node smoke-test.js   (con el servidor corriendo en el puerto 3100)
 */
const BASE = process.env.VELOZEAT_API || 'http://localhost:3100';

async function req(method, path, { body, token } = {}) {
    const res = await fetch(`${BASE}${path}`, {
        method,
        headers: {
            'Content-Type': 'application/json',
            ...(token ? { Authorization: `Bearer ${token}` } : {})
        },
        body: body ? JSON.stringify(body) : undefined
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${data.error || 'error'}`);
    return data;
}

function check(condition, message) {
    if (!condition) throw new Error(`FALLO: ${message}`);
    console.log(`  ✓ ${message}`);
}

async function login(email, password) {
    const res = await req('POST', '/api/auth/login', { body: { email, password } });
    return res.token;
}

async function main() {
    console.log('\n⚡ VelozEat · prueba de flujo completo\n');

    const health = await req('GET', '/api/health');
    check(health.ok === true, 'API en línea');

    const customer = await login('cliente@velozeat.com', 'cliente123');
    const restaurant = await login('taqueria@velozeat.com', 'restaurante123');
    const driver = await login('repartidor@velozeat.com', 'repartidor123');
    const admin = await login('admin@velozeat.com', 'admin123');
    check(!!customer && !!restaurant && !!driver && !!admin, 'Login de los 4 roles');

    const list = await req('GET', '/api/restaurants', { token: customer });
    const taqueria = list.restaurants.find((r) => r.id === 'r-tacos');
    check(taqueria && taqueria.isOpen, 'Restaurante abierto visible para clientes');

    const detail = await req('GET', '/api/restaurants/r-tacos', { token: customer });
    const first = detail.restaurant.menu.find((m) => m.available);
    const second = detail.restaurant.menu.filter((m) => m.available)[1];

    const created = await req('POST', '/api/orders', {
        token: customer,
        body: {
            restaurantId: 'r-tacos',
            items: [
                { itemId: first.id, qty: 2 },
                { itemId: second.id, qty: 1 }
            ],
            address: 'Av. Reforma 123, Col. Centro',
            notes: 'Prueba automática',
            paymentMethod: 'cash',
            tip: 20
        }
    });
    const order = created.order;
    check(order.status === 'pending', 'Cliente crea pedido (pendiente)');
    check(order.total > 0 && order.securityCode.length === 4, 'Total calculado y código de entrega generado');

    await req('POST', `/api/orders/${order.id}/accept`, { token: restaurant });
    await req('POST', `/api/orders/${order.id}/prepare`, { token: restaurant });
    await req('POST', `/api/orders/${order.id}/ready`, { token: restaurant });
    const ready = await req('GET', `/api/orders/${order.id}`, { token: restaurant });
    check(ready.order.status === 'ready', 'Restaurante acepta, prepara y marca listo');

    await req('POST', '/api/driver/status', { token: driver, body: { isOnline: true } });
    const available = await req('GET', '/api/driver/available', { token: driver });
    check(available.orders.some((o) => o.id === order.id), 'El pedido aparece al repartidor');

    const claimed = await req('POST', `/api/orders/${order.id}/claim`, { token: driver });
    check(claimed.order.driverId !== null, 'Repartidor toma el pedido');

    await req('POST', `/api/orders/${order.id}/pickup`, { token: driver });
    const badCode = await fetch(`${BASE}/api/orders/${order.id}/deliver`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${driver}` },
        body: JSON.stringify({ code: '0000' })
    });
    check(badCode.status === 400, 'Código incorrecto rechazado');

    const delivered = await req('POST', `/api/orders/${order.id}/deliver`, {
        token: driver,
        body: { code: order.securityCode }
    });
    check(delivered.order.status === 'delivered', 'Repartidor confirma entrega con código');

    const rated = await req('POST', `/api/orders/${order.id}/rate`, {
        token: customer,
        body: { rating: 5, comment: 'Excelente servicio' }
    });
    check(rated.order.rating === 5, 'Cliente califica el pedido');

    const driverSummary = await req('GET', '/api/driver/summary', { token: driver });
    check(driverSummary.todayDeliveries >= 1 && driverSummary.todayEarnings > 0, 'Ganancias del repartidor actualizadas');

    const stats = await req('GET', '/api/admin/stats', { token: admin });
    check(stats.stats.gmvToday > 0, 'Panel admin muestra GMV del día');

    const email = `demo${Date.now()}@velozeat.com`;
    const registered = await req('POST', '/api/auth/register', {
        body: {
            name: 'Prueba Restaurante',
            email,
            password: 'prueba123',
            role: 'restaurant',
            restaurantName: 'Cocina de Prueba',
            category: 'Otros',
            address: 'Calle Prueba 1'
        }
    });
    check(registered.restaurant.approved === false, 'Restaurante nuevo queda pendiente de aprobación');

    const approved = await req('POST', `/api/admin/restaurants/${registered.restaurant.id}/approve`, {
        token: admin,
        body: { approved: true }
    });
    check(approved.restaurant.approved === true, 'Admin aprueba el restaurante');

    const addItem = await req('POST', `/api/restaurants/${registered.restaurant.id}/menu`, {
        token: registered.token,
        body: { name: 'Platillo de prueba', price: 99, category: 'Menú', emoji: '🍽️' }
    });
    check(addItem.item.price === 99, 'Restaurante agrega platillo a su menú');

    console.log('\n✅ Flujo completo OK\n');
    console.log(`Pedido probado: #${order.code} · total $${order.total} · repartidor ganó $${order.driverEarnings}\n`);
}

main().catch((err) => {
    console.error(`\n❌ ${err.message}\n`);
    process.exit(1);
});
