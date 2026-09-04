require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const nodemailer = require('nodemailer');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
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
const transporter = USE_BREVO
    ? nodemailer.createTransport({
          host: 'smtp-relay.brevo.com',
          port: 587,
          secure: false,
          auth: {
              user: process.env.BREVO_USER,
              pass: process.env.BREVO_PASS
          }
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
const EMAIL_FROM = USE_BREVO ? process.env.BREVO_USER : process.env.ADMIN_EMAIL;

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
    return { users: [], orders: [] };
}

// Cola de guardado para evitar escrituras concurrentes en Supabase
let saving = Promise.resolve();

// Guardar datos en la nube (o en el archivo local si no hay Supabase)
function saveData() {
    try {
        const payload = { users, orders };
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
let adminEmail = process.env.ADMIN_EMAIL;
let emailCodes = {}; // Códigos de verificación temporales

// Función para enviar email de verificación
async function sendVerificationEmail(user, code) {
    const mailOptions = {
        from: EMAIL_FROM,
        to: user.email,
        subject: '🔐 Código de verificación - DeliveryApp',
        html: `
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
        `
    };

    try {
        await transporter.sendMail(mailOptions);
        return true;
    } catch (error) {
        console.error('Error enviando email de verificación:', error);
        return false;
    }
}

// Función para enviar email de notificación al admin (solo para repartidores)
async function sendNewUserEmail(user) {
    const mailOptions = {
        from: EMAIL_FROM,
        to: adminEmail,
        subject: `🚚 Nuevo repartidor registrado - ${user.name}`,
        html: `
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
        `
    };

    try {
        await transporter.sendMail(mailOptions);
        console.log('Email de notificación al admin enviado');
    } catch (error) {
        console.error('Error enviando email al admin:', error);
    }
}

// Función para enviar email de aprobación
async function sendApprovalEmail(user, approved) {
    const status = approved ? 'Aprobada' : 'Rechazada';
    const color = approved ? '#22c55e' : '#ef4444';
    
    const mailOptions = {
        from: EMAIL_FROM,
        to: user.email,
        subject: `${status} tu cuenta en DeliveryApp`,
        html: `
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
        `
    };

    try {
        await transporter.sendMail(mailOptions);
        console.log(`Email de ${status.toLowerCase()} enviado a ${user.email}`);
    } catch (error) {
        console.error('Error enviando email:', error);
    }
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

// Iniciar servidor
async function startServer() {
    const data = await loadData();
    users = data.users || [];
    orders = data.orders || [];
    console.log(`📦 Datos cargados: ${users.length} usuarios, ${orders.length} pedidos`);
    
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
