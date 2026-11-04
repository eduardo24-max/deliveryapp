/**
 * Notificaciones por correo de VelozEat.
 * Si no configuras VELOZEAT_SMTP_* en .env, los correos se registran en la consola
 * (modo simulado) para que puedas probar el flujo completo.
 *
 * Variables de entorno:
 *   VELOZEAT_SMTP_HOST   - ej. smtp.gmail.com
 *   VELOZEAT_SMTP_PORT   - ej. 587 (TLS) o 465 (SSL)
 *   VELOZEAT_SMTP_USER   - usuario de correo
 *   VELOZEAT_SMTP_PASS   - contraseña o App Password
 *   VELOZEAT_SMTP_FROM   - remitente visible
 */
const nodemailer = require('nodemailer');

const configured = Boolean(process.env.VELOZEAT_SMTP_HOST);

let transporter = null;
if (configured) {
    const port = Number(process.env.VELOZEAT_SMTP_PORT || 587);
    transporter = nodemailer.createTransport({
        host: process.env.VELOZEAT_SMTP_HOST,
        port,
        secure: port === 465,
        auth: process.env.VELOZEAT_SMTP_USER
            ? { user: process.env.VELOZEAT_SMTP_USER, pass: process.env.VELOZEAT_SMTP_PASS }
            : undefined
    });
}

function log(to, subject, text) {
    console.log(`[email · simulado] Para: ${to} | Asunto: ${subject}\n${text}`);
}

/**
 * Envía un correo. Si el SMTP no está configurado, lo registra en consola.
 */
async function sendEmail(to, subject, text) {
    if (!to) return;
    if (!transporter) {
        log(to, subject, text);
        return { simulated: true };
    }
    const from = process.env.VELOZEAT_SMTP_FROM || 'VelozEat <no-reply@velozeat.app>';
    return transporter.sendMail({ from, to, subject, text });
}

function orderLine(order) {
    return `Pedido #${order.code} · Total $${order.total}\nZona: ${order.zoneName || '-'} · Distancia: ${order.distanceKm || 0} km\nDirección: ${order.address}`;
}

module.exports = { sendEmail, configured, orderLine };