# Chatbot de WhatsApp para VelozEat

Se agregó un módulo de WhatsApp Business API (Meta Cloud API) al backend de VelozEat.

## Qué hace

- Recibe mensajes por WhatsApp y responde automáticamente.
- Muestra restaurantes y menús, toma pedidos y crea la orden en VelozEat.
- Notifica por WhatsApp al restaurante cuando entra un pedido.
- Auto-asigna un repartidor disponible cuando el restaurante marca el pedido "listo".
- Notifica al cliente y al repartidor por WhatsApp.
- Endpoint manual para enviar mensajes a cualquier número (admin).

## Configuración

1. Crea una app en https://developers.facebook.com y agrega el producto "WhatsApp".
2. En "WhatsApp > API Setup" obtén:
   - `WHATSAPP_TOKEN` (token permanente o temporal)
   - `WHATSAPP_PHONE_NUMBER_ID`
3. Copia `velozeat/backend/.env.example` a `velozeat/backend/.env` y completa los valores.
4. Define `WHATSAPP_VERIFY_TOKEN` (el que tú quieras) y úsalo en el panel de Meta al configurar el webhook.
5. Expón tu servidor con HTTPS (Render, Railway, o ngrok para pruebas locales).
6. En Meta, configura el webhook:
   - URL: `https://TU-DOMINIO/webhook/whatsapp`
   - Verify token: el mismo de `WHATSAPP_VERIFY_TOKEN`
   - Suscríbete al campo `messages`.

## Endpoints

- `GET /webhook/whatsapp` verificación del webhook.
- `POST /webhook/whatsapp` recepción de mensajes.
- `POST /api/whatsapp/send` (admin) envía un mensaje: `{ "to": "521...", "text": "..." }`.

## Flujo del cliente por WhatsApp

1. Escribe "hola" o "menu".
2. Elige "1" para ver restaurantes.
3. Selecciona restaurante por número.
4. Elige platillos: "1 x2, 3 x1".
5. "agregar", "confirmar" o "cancelar".
6. Envía la dirección (o ubicación).
7. Confirma con "sí".
8. Recibe código de pedido y código de seguridad.

## Auto-asignación de repartidores

Cuando un restaurante marca un pedido como "listo" (`POST /api/orders/:id/ready`), el sistema elige automáticamente el repartidor en línea más cercano (por ubicación) sin pedido activo, lo asigna y notifica por WhatsApp al repartidor y al cliente. Si no hay repartidores disponibles, se avisa al admin por WhatsApp.

## Notas

- Sin `WHATSAPP_TOKEN`/`WHATSAPP_PHONE_NUMBER_ID` el módulo funciona en modo simulado (solo log en consola).
- Los números se normalizan a formato internacional (por defecto código de país 52, México).
- Los clientes de WhatsApp se crean automáticamente como usuarios "customer" en VelozEat.