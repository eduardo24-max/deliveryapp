// ============================================================
// Módulo WhatsApp Business API (Meta Cloud API) para VelozEat
// ============================================================
const store = require('./store');

let ctx = null;

function normalizePhone(raw) {
    if (!raw) return null;
    let digits = String(raw).replace(/\D/g, '');
    if (digits.length === 10) digits = (process.env.WHATSAPP_DEFAULT_COUNTRY_CODE || '52') + digits;
    if (digits.length < 11) return null;
    return digits;
}

async function sendWhatsAppMessage(to, text) {
    const token = process.env.WHATSAPP_TOKEN;
    const phoneId = process.env.WHATSAPP_PHONE_NUMBER_ID;
    const version = process.env.WHATSAPP_API_VERSION || 'v20.0';
    if (!token || !phoneId) {
        console.log('[WhatsApp deshabilitado] ->', to, '|', String(text).slice(0, 80));
        return false;
    }
    try {
        const res = await fetch(`https://graph.facebook.com/${version}/${phoneId}/messages`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({ messaging_product: 'whatsapp', to, type: 'text', text: { body: String(text) } })
        });
        if (!res.ok) console.error('[WhatsApp send error]', res.status, await res.text());
        return res.ok;
    } catch (e) {
        console.error('[WhatsApp send exception]', e.message);
        return false;
    }
}

function getSession(phone) {
    if (!ctx.db.whatsappSessions) ctx.db.whatsappSessions = [];
    let s = ctx.db.whatsappSessions.find((x) => x.phone === phone);
    if (!s) {
        s = { phone, userId: null, state: 'idle', data: {}, updatedAt: Date.now() };
        ctx.db.whatsappSessions.push(s);
    }
    return s;
}

function saveSession(s) {
    s.updatedAt = Date.now();
    ctx.save();
}

function parseItems(text) {
    const parts = String(text).split(/[,;\n]+/);
    const result = [];
    for (const part of parts) {
        const m = part.trim().match(/^(\d+)\s*(?:[xX:*-]\s*(\d+))?$/);
        if (!m) return null;
        result.push({ num: parseInt(m[1], 10), qty: m[2] ? Math.max(1, parseInt(m[2], 10)) : 1 });
    }
    if (!result.length) return null;
    return result;
}

async function showMainMenu(phone, session, contactName) {
    const name = contactName ? contactName + ', ' : '';
    const text = `👋 ${name}¡hola! Soy el asistente de VelozEat.\n¿Qué deseas hacer?\n1️⃣ Ver restaurantes y pedir\n2️⃣ Consultar mis pedidos\n3️⃣ Ayuda / Soporte\nResponde con el número de la opción.`;
    await sendWhatsAppMessage(phone, text);
    session.state = 'main_menu';
    saveSession(session);
}

async function handleMainMenuChoice(phone, session, lower) {
    if (lower === '1') {
        await listRestaurants(phone, session);
    } else if (lower === '2') {
        await showMyOrders(phone, session);
        session.state = 'idle';
        session.data = {};
        saveSession(session);
    } else if (lower === '3') {
        await showHelp(phone);
        session.state = 'idle';
        session.data = {};
        saveSession(session);
    } else {
        await sendWhatsAppMessage(phone, 'Responde 1, 2 o 3.');
    }
}

async function listRestaurants(phone, session) {
    const list = (ctx.db.restaurants || []).filter((r) => r.approved && r.isOpen);
    if (!list.length) {
        await sendWhatsAppMessage(phone, 'No hay restaurantes disponibles ahora. Intenta más tarde.');
        session.state = 'idle';
        saveSession(session);
        return;
    }
    if (list.length === 1) {
        session.data.restaurantId = list[0].id;
        session.data.cart = [];
        session.state = 'select_items';
        saveSession(session);
        await showMenu(phone, list[0]);
        return;
    }
    let msg = '🍽️ Restaurantes disponibles:\n';
    list.forEach((r, i) => { msg += `${i + 1}. ${r.emoji || ''} ${r.name} (⭐${r.rating})\n`; });
    msg += '\nResponde con el número del restaurante.';
    await sendWhatsAppMessage(phone, msg);
    session.data.restaurantList = list.map((r) => r.id);
    session.state = 'select_restaurant';
    saveSession(session);
}

async function handleSelectRestaurant(phone, session, text) {
    const ids = session.data.restaurantList || [];
    const n = parseInt(String(text).trim(), 10);
    if (isNaN(n) || n < 1 || n > ids.length) {
        await sendWhatsAppMessage(phone, 'Número inválido. Intenta de nuevo.');
        return;
    }
    const rid = ids[n - 1];
    const restaurant = ctx.restaurantById(rid);
    session.data.restaurantId = rid;
    session.data.cart = [];
    session.state = 'select_items';
    saveSession(session);
    await showMenu(phone, restaurant);
}

async function showMenu(phone, restaurant) {
    const available = (restaurant.menu || []).filter((m) => m.available !== false);
    if (!available.length) {
        await sendWhatsAppMessage(phone, 'Este restaurante no tiene platillos disponibles.');
        return;
    }
    let msg = `📋 Menú de ${restaurant.name}:\n`;
    available.forEach((m, i) => { msg += `${i + 1}. ${m.emoji || ''} ${m.name} - $${m.price}\n`; });
    msg += '\nResponde con los números y cantidades. Ej: "1 x2, 3 x1"\nPara cancelar escribe "cancelar".';
    await sendWhatsAppMessage(phone, msg);
    session.data.menuItems = available.map((m) => m.id);
}

async function handleSelectItems(phone, session, text) {
    const lower = String(text).trim().toLowerCase();
    if (lower === 'cancelar' || lower === 'cancel') {
        session.state = 'idle';
        session.data = {};
        saveSession(session);
        await sendWhatsAppMessage(phone, 'Pedido cancelado. Escribe "menu" para volver a empezar.');
        return;
    }
    const restaurant = ctx.restaurantById(session.data.restaurantId);
    const available = (restaurant.menu || []).filter((m) => m.available !== false);
    const ids = session.data.menuItems || available.map((m) => m.id);
    const cart = session.data.cart || [];
    const parsed = parseItems(text);
    if (!parsed) {
        await sendWhatsAppMessage(phone, 'No entendí. Ejemplo: "1 x2, 3 x1"');
        return;
    }
    let added = 0;
    for (const { num, qty } of parsed) {
        if (num < 1 || num > ids.length) continue;
        const itemId = ids[num - 1];
        const menuItem = available.find((m) => m.id === itemId);
        if (!menuItem) continue;
        const existing = cart.find((c) => c.itemId === itemId);
        if (existing) existing.qty += qty;
        else cart.push({ itemId, name: menuItem.name, emoji: menuItem.emoji, price: menuItem.price, qty });
        added++;
    }
    if (!added) {
        await sendWhatsAppMessage(phone, 'No se agregó ningún platillo válido. Intenta de nuevo.');
        return;
    }
    session.data.cart = cart;
    await showCart(phone, session);
    session.state = 'cart';
    saveSession(session);
}

async function showCart(phone, session) {
    const cart = session.data.cart || [];
    let subtotal = 0;
    let msg = '🛒 Tu carrito:\n';
    for (const c of cart) { msg += `- ${c.qty}x ${c.emoji || ''} ${c.name} = $${c.price * c.qty}\n`; subtotal += c.price * c.qty; }
    msg += `Subtotal comida: $${subtotal}\n`;
    msg += '(El envío se calcula al confirmar)\n\n';
    msg += 'Escribe "agregar" para añadir más, "confirmar" para continuar o "cancelar".';
    await sendWhatsAppMessage(phone, msg);
}

async function handleCart(phone, session, lower) {
    if (lower === 'cancelar' || lower === 'cancel') {
        session.state = 'idle';
        session.data = {};
        saveSession(session);
        await sendWhatsAppMessage(phone, 'Pedido cancelado. Escribe "menu" para volver a empezar.');
        return;
    }
    if (lower === 'agregar' || lower === 'add') {
        const restaurant = ctx.restaurantById(session.data.restaurantId);
        session.state = 'select_items';
        saveSession(session);
        await showMenu(phone, restaurant);
        return;
    }
    if (lower === 'confirmar' || lower === 'confirm') {
        await sendWhatsAppMessage(phone, '📍 ¿A qué dirección enviamos el pedido?\n(Escribe la dirección o envía tu ubicación)');
        session.state = 'address';
        saveSession(session);
        return;
    }
    await sendWhatsAppMessage(phone, 'Responde "agregar", "confirmar" o "cancelar".');
}

async function handleAddress(phone, session, text) {
    session.data.address = String(text).trim();
    session.data.lat = null;
    session.data.lng = null;
    await finalizeQuote(phone, session);
}

async function handleLocationMessage(phone, loc) {
    const session = getSession(phone);
    if (session.state !== 'address') {
        await sendWhatsAppMessage(phone, 'Para usar ubicación, primero inicia un pedido (menu).');
        return;
    }
    session.data.address = `Ubicación GPS (${Number(loc.latitude).toFixed(5)}, ${Number(loc.longitude).toFixed(5)})`;
    session.data.lat = loc.latitude;
    session.data.lng = loc.longitude;
    await finalizeQuote(phone, session);
}

async function finalizeQuote(phone, session) {
    const restaurant = ctx.restaurantById(session.data.restaurantId);
    const cart = session.data.cart || [];
    const subtotal = cart.reduce((s, c) => s + c.price * c.qty, 0);
    const bodyLat = session.data.lat;
    const bodyLng = session.data.lng;
    const quote = ctx.deliveryQuote(restaurant, { lat: bodyLat, lng: bodyLng, zoneId: 'z-centro' });
    if (quote.outOfRange) {
        await sendWhatsAppMessage(phone, `Tu ubicación está a ${quote.distanceKm} km del restaurante. El área de entrega es ${quote.maxRadiusKm} km. Intenta otra dirección o restaurante.`);
        session.state = 'address';
        saveSession(session);
        return;
    }
    if (subtotal < restaurant.minOrder) {
        await sendWhatsAppMessage(phone, `El pedido mínimo es $${restaurant.minOrder}. Tu subtotal es $${subtotal}. Agrega más platillos.`);
        session.state = 'cart';
        saveSession(session);
        return;
    }
    const deliveryFee = quote.deliveryFee;
    const total = ctx.money(subtotal + deliveryFee);
    session.data.quote = quote;
    session.data.subtotal = ctx.money(subtotal);
    session.data.deliveryFee = ctx.money(deliveryFee);
    session.data.total = total;
    const msg = `🧾 Resumen de tu pedido:\nRestaurante: ${restaurant.name}\n` +
        cart.map((c) => `- ${c.qty}x ${c.name} = $${c.price * c.qty}`).join('\n') + '\n' +
        `Subtotal: $${subtotal}\nEnvío: $${deliveryFee} (${quote.distanceKm} km)\nTotal: $${total}\nDirección: ${session.data.address}\n\n¿Confirmas? Responde "sí" o "no".`;
    await sendWhatsAppMessage(phone, msg);
    session.state = 'confirm';
    saveSession(session);
}

async function handleConfirm(phone, session, lower) {
    if (lower === 'no' || lower === 'cancelar' || lower === 'cancel') {
        session.state = 'idle';
        session.data = {};
        saveSession(session);
        await sendWhatsAppMessage(phone, 'Pedido cancelado. Escribe "menu" para volver a empezar.');
        return;
    }
    if (lower !== 'sí' && lower !== 'si' && lower !== 's' && lower !== 'yes' && lower !== 'si') {
        await sendWhatsAppMessage(phone, 'Responde "sí" o "no".');
        return;
    }
    await createOrderFromSession(phone, session);
}

async function createOrderFromSession(phone, session) {
    const restaurant = ctx.restaurantById(session.data.restaurantId);
    const cart = session.data.cart || [];
    const subtotal = session.data.subtotal;
    const deliveryFee = session.data.deliveryFee;
    const quote = session.data.quote;
    const address = session.data.address;
    const lat = session.data.lat;
    const lng = session.data.lng;

    let user = (ctx.db.users || []).find((u) => u.role === 'customer' && normalizePhone(u.phone) === phone);
    if (!user) {
        user = {
            id: ctx.uid(),
            name: `Cliente ${String(phone).slice(-4)}`,
            email: `${phone}@whatsapp.velozeat`,
            phone: phone,
            role: 'customer',
            passwordHash: store.hashPassword(Math.random().toString(36)),
            emailVerified: true,
            walletBalance: 0,
            address: address,
            zoneId: 'z-centro',
            createdAt: Date.now()
        };
        if (Number.isFinite(lat) && Number.isFinite(lng)) { user.lat = lat; user.lng = lng; }
        ctx.db.users.push(user);
    } else {
        user.address = address;
        if (Number.isFinite(lat) && Number.isFinite(lng)) { user.lat = lat; user.lng = lng; }
    }

    const items = cart.map((c) => ({ itemId: c.itemId, name: c.name, emoji: c.emoji, price: c.price, qty: c.qty }));
    const tip = 0;
    const paymentMethod = 'cash';
    const discount = 0;
    const total = ctx.money(Math.max(0, subtotal + deliveryFee + tip - discount));

    const order = {
        id: ctx.uid(),
        code: ctx.nextOrderCode ? ctx.nextOrderCode() : String(Date.now()).slice(-6),
        securityCode: ctx.newSecurityCode ? ctx.newSecurityCode() : String(Math.floor(1000 + Math.random() * 9000)),
        customerId: user.id,
        restaurantId: restaurant.id,
        driverId: null,
        status: 'pending',
        items,
        subtotal: ctx.money(subtotal),
        deliveryFee: ctx.money(deliveryFee),
        tip: ctx.money(tip),
        couponCode: null,
        discount: ctx.money(discount),
        total,
        driverEarnings: ctx.money(quote.driverEarnings + tip),
        platformFee: ctx.money(subtotal * (ctx.db.settings.commissionPct || 0.15) + (quote.deliveryPlatformFee || 0)),
        deliveryPlatformFee: quote.deliveryPlatformFee,
        distanceKm: quote.distanceKm,
        zoneId: quote.zoneId,
        zoneName: quote.zoneName,
        customerLat: Number.isFinite(lat) ? lat : null,
        customerLng: Number.isFinite(lng) ? lng : null,
        address,
        notes: 'Pedido por WhatsApp',
        paymentMethod,
        createdAt: Date.now(),
        acceptedAt: null, readyAt: null, assignedAt: null, pickedAt: null, deliveredAt: null,
        rating: null, ratingComment: ''
    };
    ctx.db.orders.push(order);
    ctx.save();

    const restUser = (ctx.db.users || []).find((u) => u.restaurantId === restaurant.id && u.role === 'restaurant');
    if (restUser) {
        const rPhone = normalizePhone(restUser.phone);
        if (rPhone) {
            await sendWhatsAppMessage(rPhone, `📦 Nuevo pedido #${order.code} (WhatsApp)\nCliente: ${user.name}\nTel: ${phone}\n${ctx.mailer && ctx.mailer.orderLine ? ctx.mailer.orderLine(order) : ''}\nDirección: ${address}`);
        }
        if (restUser.email) ctx.notify(restUser.email, `Nuevo pedido #${order.code}`, `Pedido por WhatsApp de ${user.name}.\n${ctx.mailer && ctx.mailer.orderLine ? ctx.mailer.orderLine(order) : ''}`);
    }
    const adminPhone = process.env.WHATSAPP_ADMIN_PHONE;
    if (adminPhone) await sendWhatsAppMessage(normalizePhone(adminPhone), `🆕 Pedido #${order.code} por WhatsApp en ${restaurant.name}. Total $${order.total}`);
    await sendWhatsAppMessage(phone, `✅ ¡Pedido creado! #${order.code}\nCódigo de seguridad: ${order.securityCode} (muéstraselo al repartidor)\nTe avisaremos cuando el restaurante lo acepte.`);

    session.state = 'idle';
    session.data = {};
    saveSession(session);
}

async function showMyOrders(phone, session) {
    const user = (ctx.db.users || []).find((u) => u.role === 'customer' && normalizePhone(u.phone) === phone);
    if (!user) {
        await sendWhatsAppMessage(phone, 'No encontré pedidos asociados a tu número.');
        return;
    }
    const orders = (ctx.db.orders || []).filter((o) => o.customerId === user.id).sort((a, b) => b.createdAt - a.createdAt).slice(0, 5);
    if (!orders.length) {
        await sendWhatsAppMessage(phone, 'No tienes pedidos aún.');
        return;
    }
    let msg = '📦 Tus últimos pedidos:\n';
    for (const o of orders) {
        const r = ctx.restaurantById(o.restaurantId);
        msg += `#${o.code} - ${r ? r.name : 'Restaurante'} - ${o.status} - $${o.total}\n`;
    }
    await sendWhatsAppMessage(phone, msg);
}

async function showHelp(phone) {
    await sendWhatsAppMessage(phone, '🆘 Ayuda VelozEat:\n- Escribe "menu" para hacer un pedido.\n- Puedes consultar tus pedidos.\n- Para soporte, contacta al negocio.');
}

async function showTracking(phone, session) {
    await sendWhatsAppMessage(phone, 'Escribe "menu" para volver al inicio.');
    session.state = 'idle';
    session.data = {};
    saveSession(session);
}

async function handleTextMessage(phone, text, contactName) {
    if (process.env.WHATSAPP_FORWARD_ALL === 'true') {
        const adminPhone = process.env.WHATSAPP_ADMIN_PHONE;
        if (adminPhone) {
            const a = normalizePhone(adminPhone);
            if (a && a !== phone) {
                await sendWhatsAppMessage(a, `📩 Mensaje de ${phone}${contactName ? ' (' + contactName + ')' : ''}:\n${text}`);
            }
        }
    }
    const session = getSession(phone);
    const lower = String(text).trim().toLowerCase();
    if (['hola', 'menu', 'inicio', 'start', '0', 'menú'].includes(lower)) {
        session.state = 'idle';
        session.data = {};
        saveSession(session);
    }
    const state = session.state;
    if (state === 'idle') return showMainMenu(phone, session, contactName);
    if (state === 'main_menu') return handleMainMenuChoice(phone, session, lower);
    if (state === 'select_restaurant') return handleSelectRestaurant(phone, session, text);
    if (state === 'select_items') return handleSelectItems(phone, session, text);
    if (state === 'cart') return handleCart(phone, session, lower);
    if (state === 'address') return handleAddress(phone, session, text);
    if (state === 'confirm') return handleConfirm(phone, session, lower);
    if (state === 'tracking') return showTracking(phone, session);
    await sendWhatsAppMessage(phone, 'No entendí. Escribe "menu" para volver al inicio.');
}

async function processWebhook(body) {
    if (!body || body.object !== 'whatsapp_business_account') return;
    for (const entry of body.entry || []) {
        for (const change of entry.changes || []) {
            const value = change.value || {};
            const messages = value.messages || [];
            const contacts = value.contacts || [];
            for (const msg of messages) {
                try {
                    const from = msg.from;
                    if (msg.type === 'text') {
                        await handleTextMessage(from, msg.text.body, (contacts.find((c) => c.wa_id === from) || {}).profile && (contacts.find((c) => c.wa_id === from) || {}).profile.name);
                    } else if (msg.type === 'location') {
                        await handleLocationMessage(from, msg.location);
                    } else {
                        await sendWhatsAppMessage(from, 'Solo puedo procesar texto y ubicación por ahora. Escribe "menu" para empezar.');
                    }
                } catch (e) {
                    console.error('[WhatsApp process msg error]', e.message);
                }
            }
        }
    }
}

async function autoAssignDriver(order) {
    if (!order || order.driverId) return;
    const restaurant = ctx.restaurantById(order.restaurantId);
    const candidates = (ctx.db.users || []).filter((u) => u.role === 'driver').map((u) => {
        const profile = ctx.driverProfile(u.id);
        if (!profile || !profile.isOnline) return null;
        const active = (ctx.db.orders || []).find((o) => o.driverId === u.id && ['assigned', 'picked_up'].includes(o.status));
        if (active) return null;
        let dist = Infinity;
        if (Number.isFinite(profile.lat) && Number.isFinite(profile.lng) && restaurant && Number.isFinite(restaurant.lat)) {
            dist = ctx.haversineKm({ lat: profile.lat, lng: profile.lng }, restaurant);
        }
        return { user: u, profile, dist };
    }).filter(Boolean);
    if (!candidates.length) {
        const adminPhone = process.env.WHATSAPP_ADMIN_PHONE;
        if (adminPhone) await sendWhatsAppMessage(normalizePhone(adminPhone), `⚠️ Pedido #${order.code} listo pero no hay repartidores disponibles.`);
        return;
    }
    candidates.sort((a, b) => a.dist - b.dist);
    const chosen = candidates[0];
    order.driverId = chosen.user.id;
    order.status = 'assigned';
    order.assignedAt = Date.now();
    ctx.save();
    const rPhone = normalizePhone(chosen.user.phone);
    if (rPhone) {
        await sendWhatsAppMessage(rPhone, `📦 Nuevo pedido asignado #${order.code}\nRestaurante: ${restaurant ? restaurant.name : ''}\nDirección: ${order.address}\nGanancia: $${order.driverEarnings}\nAcepta en la app o responde "aceptar".`);
    }
    const customer = (ctx.db.users || []).find((u) => u.id === order.customerId);
    if (customer) {
        const cPhone = normalizePhone(customer.phone);
        if (cPhone) await sendWhatsAppMessage(cPhone, `🚗 Repartidor asignado a tu pedido #${order.code}. Pronto estará en camino.`);
    }
}

function register(app, context) {
    ctx = context;
    if (!ctx.db.whatsappSessions) ctx.db.whatsappSessions = [];

    app.get('/webhook/whatsapp', (req, res) => {
        const mode = req.query['hub.mode'];
        const token = req.query['hub.verify_token'];
        const challenge = req.query['hub.challenge'];
        const verifyToken = process.env.WHATSAPP_VERIFY_TOKEN || 'velozeat-verify';
        if (mode === 'subscribe' && token === verifyToken) {
            return res.status(200).send(challenge);
        }
        return res.sendStatus(403);
    });

    app.post('/webhook/whatsapp', (req, res) => {
        const secret = process.env.WHATSAPP_APP_SECRET;
        if (secret) {
            const sig = req.headers['x-hub-signature-256'];
            const crypto = require('crypto');
            const expected = 'sha256=' + crypto.createHmac('sha256', secret).update(JSON.stringify(req.body)).digest('hex');
            if (sig !== expected) {
                console.warn('[WhatsApp] firma no coincide (verifica WHATSAPP_APP_SECRET / raw body). Continuando.');
            }
        }
        res.sendStatus(200);
        processWebhook(req.body).catch((e) => console.error('[WhatsApp webhook error]', e.message));
    });

    app.post('/api/whatsapp/send', ctx.auth(['admin']), async (req, res) => {
        const to = normalizePhone(req.body && req.body.to);
        const text = String((req.body && req.body.text) || '').trim();
        if (!to || !text) return res.status(400).json({ error: 'Faltan datos' });
        const ok = await sendWhatsAppMessage(to, text);
        res.json({ ok });
    });

    console.log('[WhatsApp] módulo registrado. Webhook: GET/POST /webhook/whatsapp');
}

module.exports = { register, autoAssignDriver };