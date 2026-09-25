require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const crypto = require('crypto');
const nodemailer = require('nodemailer');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json({ limit: '15mb' }));
app.use(express.static(path.join(__dirname)));

// Desactivar caché para que siempre cargue la versión más reciente
app.use((req, res, next) => {
    if (req.path.endsWith('.js') || req.path.endsWith('.css') || req.path.endsWith('.html')) {
        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
        res.setHeader('Pragma', 'no-cache');
        res.setHeader('Expires', '0');
    }
    next();
});

// Configurar Email
// Si hay credenciales de Brevo, úsalo (ideal para la nube). Si no, usa Gmail (desarrollo local).
const USE_BREVO = !!(process.env.BREVO_USER && process.env.BREVO_PASS);
// Timeouts generosos para evitar "Connection timeout" con Brevo
const SMTP_TIMEOUTS = {
    connectionTimeout: 30000,
    greetingTimeout: 30000,
    socketTimeout: 60000
};
const transporter = USE_BREVO
    ? nodemailer.createTransport({
          host: 'smtp-relay.brevo.com',
          port: 465,
          secure: true,
          auth: {
              user: process.env.BREVO_USER,
              pass: process.env.BREVO_PASS
          },
          ...SMTP_TIMEOUTS
      })
    : nodemailer.createTransport({
          service: 'gmail',
          auth: {
              user: process.env.ADMIN_EMAIL,
              pass: process.env.EMAIL_PASSWORD
          }
      });
if (USE_BREVO) {
    console.log('📧 Email configurado con BREVO');
} else {
    console.log('📧 Email configurado con GMAIL (solo recomienda para local)');
}

// Remitente de los emails. Con Brevo se usa la cuenta de login; con Gmail el ADMIN_EMAIL.
// Remitente de los emails.
// 1) API Brevo: usa el ADMIN_EMAIL (correo real del negocio, verificado como remitente)
// 2) Resend: usa la dirección de prueba (no requiere dominio verificado)
// 3) SMTP: Brevo usa login, Gmail usa ADMIN_EMAIL
const EMAIL_FROM = (process.env.BREVO_API_KEY)
    ? process.env.ADMIN_EMAIL
    : (process.env.RESEND_API_KEY
        ? 'DeliveryApp <onboarding@resend.dev>'
        : (USE_BREVO ? process.env.BREVO_USER : process.env.ADMIN_EMAIL));

// Almacenamiento persistente
// En producción usa Supabase (nube). En local usa database.json como fallback.
const fs = require('fs');
const DATA_FILE = path.join(__dirname, 'database.json');

const SUPABASE_URL = process.env.SUPABASE_URL || null;
const SUPABASE_KEY = process.env.SUPABASE_KEY || null;
const { createClient } = require('@supabase/supabase-js');

let supabase = null;
if (SUPABASE_URL && SUPABASE_KEY) {
    supabase = createClient(SUPABASE_URL, SUPABASE_KEY);
    console.log('✅ Supabase conectado');
}

// Cargar datos desde la nube (o del archivo local si no hay Supabase)
async function loadData() {
    try {
        if (supabase) {
            const { data, error } = await supabase
                .from('app_data')
                .select('payload')
                .eq('id', 'main')
                .single();
            if (error) {
                console.error('Error cargando de Supabase:', error.message);
            } else if (data && data.payload) {
                return data.payload;
            }
        }
        // Fallback: archivo local
        if (fs.existsSync(DATA_FILE)) {
            return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
        }
    } catch (e) {
        console.error('Error cargando datos:', e.message);
    }
    return { users: [], orders: [], semana: { students: [], payments: [], expenses: [] } };
}

// Cola de guardado para evitar escrituras concurrentes en Supabase
let saving = Promise.resolve();

// Guardar datos en la nube (o en el archivo local si no hay Supabase)
function saveData() {
    try {
        const payload = { users, orders, semana };
        if (supabase) {
            // Encolar el guardado para evitar pisarse entre escrituras
            saving = saving.then(async () => {
                const { error } = await supabase
                    .from('app_data')
                    .upsert({ id: 'main', payload: payload, updated_at: new Date().toISOString() });
                if (error) {
                    console.error('Error guardando en Supabase:', error);
                }
            }).catch(err => console.error('Error en cola de guardado:', err));
        } else {
            fs.writeFileSync(DATA_FILE, JSON.stringify(payload, null, 2));
        }
    } catch (e) {
        console.error('Error guardando datos:', e.message);
    }
}

let users = [];
let orders = [];
let semana = { students: [], payments: [], expenses: [] };
let adminEmail = process.env.ADMIN_EMAIL;
let emailCodes = {}; // Códigos de verificación temporales

// ============================================================
// Envío de emails central
// 1) BREVO_API_KEY -> API REST de Brevo (HTTPS 443, fiable desde Render)
// 2) RESEND_API_KEY -> API de Resend (HTTPS 443)
// 3) SMTP (Brevo/Gmail) -> con reintentos (funciona desde tu PC local)
// ============================================================
const BREVO_API_KEY = process.env.BREVO_API_KEY || null;
const RESEND_API_KEY = process.env.RESEND_API_KEY || null;

async function sendEmail({ to, subject, html }) {
    // Método 1: API REST de Brevo (HTTPS - evita timeout SMTP)
    if (BREVO_API_KEY) {
        try {
            const payload = {
                sender: { email: EMAIL_FROM, name: 'DeliveryApp' },
                to: [{ email: to }],
                subject,
                htmlContent: html
            };
            const res = await fetch('https://api.brevo.com/v3/smtp/email', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'api-key': BREVO_API_KEY, 'Accept': 'application/json' },
                body: JSON.stringify(payload)
            });
            if (res.ok) {
                console.log(`📧 Email enviado vía API Brevo a ${to}`);
                return true;
            }
            console.error('API Brevo error:', res.status, await res.text());
        } catch (e) {
            console.error('API Brevo error de red:', e.message);
        }
    }

    // Método 2: API Resend (HTTPS)
    if (RESEND_API_KEY) {
        try {
            const res = await fetch('https://api.resend.com/emails', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + RESEND_API_KEY },
                body: JSON.stringify({ from: EMAIL_FROM, to: [to], subject, html })
            });
            if (res.ok) {
                const d = await res.json();
                console.log(`📧 Email enviado vía Resend a ${to} (id ${d.id})`);
                return true;
            }
            console.error('Resend error:', res.status, await res.text());
        } catch (e) {
            console.error('Resend error de red:', e.message);
        }
    }

    // Método 3: SMTP (Brevo/Gmail) con reintentos
    let lastErr = null;
    for (let attempt = 1; attempt <= 3; attempt++) {
        try {
            await transporter.sendMail({ from: EMAIL_FROM, to, subject, html });
            console.log(`📧 Email enviado a ${to} (intento ${attempt})`);
            return true;
        } catch (error) {
            lastErr = error;
            console.error(`Intento ${attempt} de email falló:`, error.message);
            if (attempt < 3) await new Promise(r => setTimeout(r, 3000));
        }
    }
    console.error('Email no se pudo enviar tras intentos:', lastErr && lastErr.message);
    return false;
}

// Función para enviar email de verificación
async function sendVerificationEmail(user, code) {
    const html = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #2563eb;">Verifica tu correo</h2>
            <div style="background: #f8fafc; padding: 20px; border-radius: 10px; text-align: center;">
                <p style="font-size: 16px;">Hola ${user.name},</p>
                <p style="font-size: 16px;">Tu código de verificación es:</p>
                <div style="background: #2563eb; color: white; padding: 16px 24px; border-radius: 8px; font-size: 32px; font-weight: bold; letter-spacing: 8px; display: inline-block; margin: 10px 0;">
                    ${code}
                </div>
                <p style="color: #64748b; font-size: 14px;">Ingresa este código en la aplicación para activar tu cuenta.</p>
                <p style="color: #64748b; font-size: 12px;">El código expira en 10 minutos.</p>
            </div>
            <p style="margin-top: 20px; color: #64748b; font-size: 12px;">
                DeliveryApp - Sistema de Delivery
            </p>
        </div>
    `;
    const ok = await sendEmail({ to: user.email, subject: '🔐 Código de verificación - DeliveryApp', html });
    if (!ok) console.error('Fallo al enviar código de verificación');
    return ok;
}

// Función para enviar email de notificación al admin (solo para repartidores)
async function sendNewUserEmail(user) {
    const html = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: #2563eb;">Nuevo repartidor registrado</h2>
            <div style="background: #f8fafc; padding: 20px; border-radius: 10px;">
                <p><strong>Nombre:</strong> ${user.name}</p>
                <p><strong>Email:</strong> ${user.email}</p>
                <p><strong>Teléfono:</strong> ${user.phone}</p>
                <p><strong>Vehículo:</strong> ${user.vehicle || '-'}</p>
                <p><strong>Fecha:</strong> ${new Date().toLocaleString('es-MX')}</p>
            </div>
            <p style="margin-top: 20px; color: #64748b; font-size: 12px;">
                Revisa el panel de administración para aprobar a este repartidor.
            </p>
        </div>
    `;
    const ok = await sendEmail({ to: adminEmail, subject: `🚚 Nuevo repartidor registrado - ${user.name}`, html });
    if (!ok) console.error('Fallo al notificar al admin por email');
}

// Función para enviar email de aprobación
async function sendApprovalEmail(user, approved) {
    const status = approved ? 'Aprobada' : 'Rechazada';
    const color = approved ? '#22c55e' : '#ef4444';
    const html = `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
            <h2 style="color: ${color};">Tu cuenta ha sido ${status}</h2>
            <div style="background: #f8fafc; padding: 20px; border-radius: 10px;">
                <p>Hola ${user.name},</p>
                <p>Tu cuenta como <strong>${user.role === 'driver' ? 'Repartidor' : 'Cliente'}</strong> ha sido ${status.toLowerCase()}.</p>
                ${approved ? 
                    '<p style="color: #22c55e; font-weight: bold;">Ya puedes iniciar sesión y usar la plataforma.</p>' :
                    '<p style="color: #ef4444;">Si tienes alguna consulta, contacta al administrador.</p>'
                }
            </div>
            <p style="margin-top: 20px; color: #64748b; font-size: 12px;">
                DeliveryApp - Sistema de Delivery
            </p>
        </div>
    `;
    const ok = await sendEmail({ to: user.email, subject: `${status} tu cuenta en DeliveryApp`, html });
    if (!ok) console.error('Fallo al enviar email de aprobación');
}

// Ruta principal - servir el frontend
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

// Ruta del admin
app.get('/admin', (req, res) => {
    res.sendFile(path.join(__dirname, 'admin.html'));
});

// Ruta del monitor (panel de monitoreo del negocio) - protegida con contraseña admin
app.get('/monitor', (req, res) => {
    // Autorización básica: solo quien sepa la contraseña del admin entra
    const auth = req.headers.authorization;
    if (!auth || auth.indexOf('Basic ') !== 0) {
        res.setHeader('WWW-Authenticate', 'Basic realm="Monitor"');
        return res.status(401).json({ success: false, message: 'Acceso restringido' });
    }
    const buf = Buffer.from(auth.slice(6), 'base64').toString('utf8');
    const parts = buf.split(':');
    const user = parts[0];
    const pass = parts.slice(1).join(':');
    if (user === (process.env.ADMIN_EMAIL || 'admin') && pass === process.env.ADMIN_PASSWORD) {
        return res.sendFile(path.join(__dirname, 'monitor.html'));
    }
    res.setHeader('WWW-Authenticate', 'Basic realm="Monitor"');
    return res.status(401).json({ success: false, message: 'Acceso restringido' });
});

// API: Registro de usuario (paso 1 - envía código de verificación)
app.post('/api/register', (req, res) => {
    try {
        const { name, email, phone, password, role, vehicle } = req.body;
        
        if (!email || !email.includes('@') || !email.includes('.')) {
            return res.status(400).json({ success: false, message: 'Ingresa un email válido' });
        }
        
        // No permitir dos registros con el mismo email
        if (users.find(u => u.email && u.email.toLowerCase() === email.toLowerCase())) {
            return res.status(400).json({ success: false, message: 'Este email ya está registrado' });
        }
        
        if (!name || !phone || !password) {
            return res.status(400).json({ success: false, message: 'Completa todos los campos' });
        }
        
        const code = Math.floor(100000 + Math.random() * 900000).toString();
        
        const newUser = {
            id: Date.now(),
            name,
            email,
            phone,
            password,
            role,
            vehicle: role === 'driver' ? (vehicle || 'moto') : null,
            status: 'pending-verification', // Esperando verificación de email
            emailVerified: false,
            approved: role === 'customer', // Clientes se verifican solos; repartidores requieren aprobación del admin
            deliveries: 0,
            earnings: 0,
            createdAt: new Date().toISOString()
        };
        
        users.push(newUser);
        
        // Guardar código temporal (expira en 10 min)
        emailCodes[email.toLowerCase()] = { code, userId: newUser.id, time: Date.now() };
        saveData();
        
        // Enviar código de verificación por email
        sendVerificationEmail(newUser, code);
        
        res.json({ 
            success: true, 
            message: 'Te enviamos un código de verificación a tu correo',
            requireVerification: true
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Verificar código de email (paso 2)
app.post('/api/verify-code', async (req, res) => {
    try {
        const { email, code } = req.body;
        
        if (!email || !code) {
            return res.status(400).json({ success: false, message: 'Faltan datos' });
        }
        
        const emailLower = email.toLowerCase();
        const stored = emailCodes[emailLower];
        
        if (!stored) {
            return res.status(400).json({ success: false, message: 'No hay código pendiente para este email' });
        }
        
        // Verificar expiración (10 min)
        if (Date.now() - stored.time > 10 * 60 * 1000) {
            delete emailCodes[emailLower];
            return res.status(400).json({ success: false, message: 'El código expiró. Regístrate de nuevo.' });
        }
        
        if (stored.code !== code) {
            return res.status(400).json({ success: false, message: 'Código incorrecto' });
        }
        
        // Código correcto - activar cuenta
        const user = users.find(u => u.id === stored.userId);
        if (!user) {
            return res.status(400).json({ success: false, message: 'Usuario no encontrado' });
        }
        
        user.emailVerified = true;
        if (user.role === 'customer') {
            user.status = 'available';
            user.approved = true;
        } else {
            user.status = 'pending'; // Repartidor espera aprobación del admin
            user.approved = false;
        }
        
        delete emailCodes[emailLower];
        saveData();
        
        // Notificar al admin si es repartidor
        if (user.role === 'driver') {
            sendNewUserEmail(user);
        }
        
        res.json({ 
            success: true, 
            message: user.role === 'customer' 
                ? '¡Cuenta verificada! Ya puedes iniciar sesión.' 
                : '¡Email verificado! Tu cuenta de repartidor está pendiente de aprobación del administrador.',
            role: user.role
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Reenviar código
app.post('/api/resend-code', (req, res) => {
    try {
        const { email } = req.body;
        if (!email) return res.status(400).json({ success: false, message: 'Falta email' });
        
        const emailLower = email.toLowerCase();
        const user = users.find(u => u.email && u.email.toLowerCase() === emailLower);
        
        if (!user) {
            return res.status(400).json({ success: false, message: 'Email no encontrado' });
        }
        
        const code = Math.floor(100000 + Math.random() * 900000).toString();
        emailCodes[emailLower] = { code, userId: user.id, time: Date.now() };
        
        sendVerificationEmail(user, code);
        res.json({ success: true, message: 'Nuevo código enviado' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Login
app.post('/api/login', (req, res) => {
    try {
        const { email, password } = req.body;
        
        const user = users.find(u => u.email && u.email.toLowerCase() === email.toLowerCase() && u.password === password);
        
        if (!user) {
            return res.status(401).json({ success: false, message: 'Email o contraseña incorrectos' });
        }
        
        if (!user.emailVerified) {
            return res.status(403).json({ 
                success: false, 
                message: 'No has verificado tu correo. Revisa tu email para el código.' 
            });
        }
        
        if (user.role === 'driver' && !user.approved) {
            return res.status(403).json({ 
                success: false, 
                message: 'Tu cuenta de repartidor está pendiente de aprobación del administrador.' 
            });
        }
        
        res.json({ success: true, user });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Obtener usuarios pendientes
app.get('/api/users/pending', (req, res) => {
    const pendingUsers = users.filter(u => !u.approved);
    res.json({ success: true, users: pendingUsers });
});

// API: Obtener todos los usuarios
app.get('/api/users', (req, res) => {
    const safeUsers = users.map(u => ({
        ...u,
        password: undefined
    }));
    res.json({ success: true, users: safeUsers });
});

// API: Aprobar/Rechazar usuario
app.post('/api/users/:userId/approve', async (req, res) => {
    try {
        const { userId } = req.params;
        const { approved } = req.body;
        
        const user = users.find(u => u.id == userId);
        if (!user) {
            return res.status(404).json({ success: false, message: 'Usuario no encontrado' });
        }
        
        user.approved = approved;
        user.status = approved ? 'available' : 'rejected';
        saveData();
        
        // Enviar email de notificación al usuario
        await sendApprovalEmail(user, approved);
        
        res.json({ 
            success: true, 
            message: approved ? 'Usuario aprobado' : 'Usuario rechazado' 
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Crear pedido
app.post('/api/orders', (req, res) => {
    try {
        const { customerId, customerName, customerPhone, customerEmail, address, reference, description, tip, customerLocation } = req.body;
        
        const securityCode = Math.floor(100000 + Math.random() * 900000).toString();
        
        const order = {
            id: `ORD-${Date.now()}`,
            customerId,
            customerName,
            customerPhone,
            customerEmail,
            address,
            reference,
            description,
            tip: tip ? parseFloat(tip) : 0,
            addTip: tip ? true : false,
            amount: null,
            confirmedAmount: null,
            paymentMethod: null,
            customerLocation: customerLocation || null,
            out: false,
            outAt: null,
            securityCode,
            status: 'pending',
            driverId: null,
            driverName: null,
            paymentId: null,
            createdAt: new Date().toISOString()
        };
        
        orders.push(order);
        saveData();
        
        res.json({
            success: true,
            order,
            message: `Pedido creado. Código de seguridad: ${securityCode}`
        });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Login de administrador
app.post('/api/admin/login', (req, res) => {
    try {
        const { email, password } = req.body;
        
        if (email === process.env.ADMIN_EMAIL && password === process.env.ADMIN_PASSWORD) {
            res.json({ success: true, token: 'admin-token' });
        } else {
            res.status(401).json({ success: false, message: 'Credenciales de administrador incorrectas' });
        }
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Asignar pedido a repartidor
app.post('/api/orders/:orderId/assign', (req, res) => {
    try {
        const { orderId } = req.params;
        const { driverId, driverName } = req.body;
        
        const order = orders.find(o => o.id === orderId);
        if (!order) {
            return res.status(404).json({ success: false, message: 'Pedido no encontrado' });
        }
        
        order.driverId = driverId;
        order.driverName = driverName;
        order.status = 'assigned';
        saveData();
        
        res.json({ success: true, order });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Repartidor salió con el pedido (activa la visibilidad de ubicación para el cliente)
app.post('/api/orders/:orderId/out', (req, res) => {
    try {
        const { orderId } = req.params;
        const { driverId } = req.body;
        
        const order = orders.find(o => o.id === orderId);
        if (!order) {
            return res.status(404).json({ success: false, message: 'Pedido no encontrado' });
        }
        
        if (order.driverId != driverId) {
            return res.status(403).json({ success: false, message: 'No tienes autorización para este pedido' });
        }
        
        order.out = true;
        order.outAt = new Date().toISOString();
        // Al salir, el repartidor empieza a mandar su ubicación
        if (!order.driverLocation) {
            order.driverLocation = null;
        }
        saveData();
        
        res.json({ success: true, order, message: 'Pedido saliendo del restaurante' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Confirmar entrega (efectivo)
app.post('/api/orders/:orderId/deliver-cash', (req, res) => {
    try {
        const { orderId } = req.params;
        const { securityCode, amount } = req.body;
        
        const order = orders.find(o => o.id === orderId);
        if (!order) {
            return res.status(404).json({ success: false, message: 'Pedido no encontrado' });
        }
        
        if (order.securityCode !== securityCode) {
            return res.status(400).json({ success: false, message: 'Código de seguridad incorrecto' });
        }
        
        if (!amount || isNaN(parseFloat(amount))) {
            return res.status(400).json({ success: false, message: 'El repartidor debe indicar el monto a cobrar' });
        }
        
        order.status = 'delivered';
        order.paymentMethod = 'cash';
        order.amount = parseFloat(amount);
        order.confirmedAmount = parseFloat(amount);
        order.deliveredAt = new Date().toISOString();
        saveData();
        
        res.json({ success: true, order, message: 'Entrega confirmada' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Actualizar ubicación del repartidor
app.post('/api/orders/:orderId/location', (req, res) => {
    try {
        const { orderId } = req.params;
        const { lat, lng } = req.body;
        
        const order = orders.find(o => o.id === orderId);
        if (!order) {
            return res.status(404).json({ success: false, message: 'Pedido no encontrado' });
        }
        
        order.driverLocation = { lat, lng, updatedAt: new Date().toISOString() };
        saveData();
        
        res.json({ success: true, message: 'Ubicación actualizada' });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// API: Obtener pedidos
app.get('/api/orders', (req, res) => {
    const { customerId, driverId, status } = req.query;
    
    let filteredOrders = orders;
    
    if (customerId) {
        filteredOrders = filteredOrders.filter(o => o.customerId == customerId);
    }
    
    if (driverId) {
        filteredOrders = filteredOrders.filter(o => o.driverId == driverId);
    }
    
    if (status) {
        filteredOrders = filteredOrders.filter(o => o.status === status);
    }
    
    res.json({ success: true, orders: filteredOrders });
});

// API: Obtener un pedido individual
app.get('/api/orders/:orderId', (req, res) => {
    const order = orders.find(o => o.id === req.params.orderId);
    if (!order) {
        return res.status(404).json({ success: false, message: 'Pedido no encontrado' });
    }
    res.json({ success: true, order });
});

// API: Obtener estadísticas
app.get('/api/stats', (req, res) => {
    const totalUsers = users.length;
    const pendingUsers = users.filter(u => !u.approved).length;
    const totalOrders = orders.length;
    const deliveredOrders = orders.filter(o => o.status === 'delivered').length;
    
    res.json({
        success: true,
        stats: {
            totalUsers,
            pendingUsers,
            totalOrders,
            deliveredOrders
        }
    });
});

// ============================================================
// SEMANA ACADÉMICA - Registro de alumnos, abonos y gastos
// ============================================================

const SEMANA_PASSWORD = process.env.SEMANA_PASSWORD || process.env.ADMIN_PASSWORD || 'semana123';
const semanaTokenValue = crypto.createHash('sha256').update('semana::' + SEMANA_PASSWORD).digest('hex');

// Ruta protegida por token (Bearer simple, el token deriva de la contraseña)
function semanaAuth(req, res, next) {
    const token = req.headers['x-semana-token'];
    if (token && token === semanaTokenValue) return next();
    return res.status(401).json({ success: false, message: 'No autorizado' });
}

function round2(n) {
    return Math.round(n * 100) / 100;
}

function semanaTotals() {
    const recaudado = semana.payments.reduce((s, p) => s + (parseFloat(p.amount) || 0), 0);
    const gastos = semana.expenses.reduce((s, e) => s + (parseFloat(e.amount) || 0), 0);
    return {
        recaudado: round2(recaudado),
        gastos: round2(gastos),
        saldo: round2(recaudado - gastos)
    };
}

// Página principal de la Semana Académica (el login se hace en el frontend)
app.get('/semana', (req, res) => {
    res.sendFile(path.join(__dirname, 'semana.html'));
});

// Login (devuelve el token que derivamos de la contraseña)
app.post('/api/semana/auth', (req, res) => {
    const { password } = req.body || {};
    if (password === SEMANA_PASSWORD) {
        res.json({ success: true, token: semanaTokenValue });
    } else {
        res.status(401).json({ success: false, message: 'Contraseña incorrecta' });
    }
});

// Obtener todos los datos (alumnos, abonos, gastos y totales)
app.get('/api/semana/data', semanaAuth, (req, res) => {
    res.json({ success: true, data: semana, totals: semanaTotals() });
});

// Agregar alumno
app.post('/api/semana/students', semanaAuth, (req, res) => {
    try {
        const { name, group } = req.body || {};
        if (!name || !name.trim()) {
            return res.status(400).json({ success: false, message: 'El nombre es obligatorio' });
        }
        const student = {
            id: Date.now(),
            name: name.trim(),
            group: (group || '').trim(),
            createdAt: new Date().toISOString()
        };
        semana.students.push(student);
        saveData();
        res.json({ success: true, student, totals: semanaTotals() });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// Eliminar alumno (también elimina sus abonos)
app.delete('/api/semana/students/:id', semanaAuth, (req, res) => {
    try {
        const id = Number(req.params.id);
        const idx = semana.students.findIndex(s => s.id === id);
        if (idx === -1) {
            return res.status(404).json({ success: false, message: 'Alumno no encontrado' });
        }
        semana.students.splice(idx, 1);
        semana.payments = semana.payments.filter(p => p.studentId !== id);
        saveData();
        res.json({ success: true, totals: semanaTotals() });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// Registrar abono de un alumno
app.post('/api/semana/payments', semanaAuth, (req, res) => {
    try {
        const { studentId, amount, note } = req.body || {};
        const student = semana.students.find(s => s.id === Number(studentId));
        if (!student) {
            return res.status(404).json({ success: false, message: 'Alumno no encontrado' });
        }
        const amt = parseFloat(amount);
        if (isNaN(amt) || amt <= 0) {
            return res.status(400).json({ success: false, message: 'Ingresa un monto válido mayor a 0' });
        }
        const payment = {
            id: Date.now(),
            studentId: student.id,
            amount: round2(amt),
            note: (note || '').trim(),
            date: new Date().toISOString()
        };
        semana.payments.push(payment);
        saveData();
        res.json({ success: true, payment, totals: semanaTotals() });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// Eliminar un abono (por si se registró por error)
app.delete('/api/semana/payments/:id', semanaAuth, (req, res) => {
    try {
        const id = Number(req.params.id);
        const before = semana.payments.length;
        semana.payments = semana.payments.filter(p => p.id !== id);
        if (semana.payments.length === before) {
            return res.status(404).json({ success: false, message: 'Abono no encontrado' });
        }
        saveData();
        res.json({ success: true, totals: semanaTotals() });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// Registrar gasto (con foto opcional del ticket en base64)
app.post('/api/semana/expenses', semanaAuth, (req, res) => {
    try {
        const { description, amount, category, photo } = req.body || {};
        if (!description || !description.trim()) {
            return res.status(400).json({ success: false, message: 'La descripción es obligatoria' });
        }
        const amt = parseFloat(amount);
        if (isNaN(amt) || amt <= 0) {
            return res.status(400).json({ success: false, message: 'Ingresa un monto válido mayor a 0' });
        }
        const expense = {
            id: Date.now(),
            description: description.trim(),
            amount: round2(amt),
            category: (category || '').trim() || 'General',
            photo: photo || null,
            date: new Date().toISOString()
        };
        semana.expenses.push(expense);
        saveData();
        res.json({ success: true, expense, totals: semanaTotals() });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// Eliminar gasto
app.delete('/api/semana/expenses/:id', semanaAuth, (req, res) => {
    try {
        const id = Number(req.params.id);
        const before = semana.expenses.length;
        semana.expenses = semana.expenses.filter(e => e.id !== id);
        if (semana.expenses.length === before) {
            return res.status(404).json({ success: false, message: 'Gasto no encontrado' });
        }
        saveData();
        res.json({ success: true, totals: semanaTotals() });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
});

// Iniciar servidor
async function startServer() {
    const data = await loadData();
    users = data.users || [];
    orders = data.orders || [];
    semana = data.semana || { students: [], payments: [], expenses: [] };
    console.log(`📦 Datos cargados: ${users.length} usuarios, ${orders.length} pedidos`);
    console.log(`🎓 Semana Académica: ${semana.students.length} alumnos, ${semana.expenses.length} gastos`);
    
    app.listen(PORT, () => {
        console.log(`🚀 Servidor corriendo en http://localhost:${PORT}`);
        console.log(`📦 Frontend: http://localhost:${PORT}`);
        console.log(`👨‍💼 Admin: http://localhost:${PORT}/admin`);
        console.log(`🔗 API: http://localhost:${PORT}/api`);
    });
}

startServer().catch(err => {
    console.error('Error iniciando servidor:', err);
    process.exit(1);
});
