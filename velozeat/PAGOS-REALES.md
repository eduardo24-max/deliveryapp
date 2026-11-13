# Pagos reales con VelozEat

## Estado actual
El flujo de pago con tarjeta es **simulado**. Los endpoints `/api/payments/create-intent` y `/api/payments/confirm` devuelven respuestas simuladas si no hay claves de pasarela configuradas.

## Para activar pagos reales (Stripe)

### 1) Crear cuenta en Stripe
1. Ve a https://stripe.com → crea cuenta.
2. Obtén tus claves en: Dashboard → Developers → API keys.
   - **Publishable key** (pk_test_...) → va en la app Flutter.
   - **Secret key** (sk_test_...) → va en el backend (NUNCA en la app).

### 2) Configurar el backend
Agrega a `velozeat/backend/.env`:
```
STRIPE_SECRET_KEY=sk_test_tu_clave_secreta
STRIPE_PUBLISHABLE_KEY=pk_test_tu_clave_publica
```

### 3) Instalar SDK de Stripe en el backend
```powershell
cd velozeat/backend
npm install stripe
```

### 4) Modificar el endpoint create-intent
Reemplaza la lógica simulada por:
```js
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
const paymentIntent = await stripe.paymentIntents.create({
  amount: Math.round(amount * 100), // centavos
  currency: currency,
  automatic_payment_methods: { enabled: true },
});
res.json({ clientSecret: paymentIntent.client_secret, amount, currency, simulated: false });
```

### 5) Instalar SDK de Stripe en Flutter
```powershell
cd velozeat/mobile
flutter pub add flutter_stripe
```

### 6) Configurar la app
En `main.dart`:
```dart
import 'package:flutter_stripe/flutter_stripe.dart';
Stripe.publishableKey = 'pk_test_tu_clave_publica';
```

### 7) Usar el SDK en el flujo de pago
En `cart_screen.dart`, reemplaza la validación simulada por:
```dart
final paymentIntent = await api.createPaymentIntent(total, 'mxn');
await Stripe.instance.initPaymentSheet(
  paymentSheetParameters: SetupPaymentSheetParameters(
    paymentIntentClientSecret: paymentIntent['clientSecret'],
    merchantDisplayName: 'VelozEat',
  ),
);
await Stripe.instance.presentPaymentSheet();
```

### Seguridad
- **Nunca** pongas la secret key en la app Flutter.
- **Nunca** guardes números de tarjeta en tu base de datos.
- Usa HTTPS en producción.
- Valida el pago en el backend antes de marcar el pedido como pagado.

### Otras pasarelas
- **Mercado Pago:** https://www.mercadopago.com.mx/developers
- **PayPal:** https://developer.paypal.com
- **Conekta (México):** https://developers.conekta.com

El flujo es similar: crear orden en la pasarela → obtener clientSecret → confirmar en la app → verificar en el backend.