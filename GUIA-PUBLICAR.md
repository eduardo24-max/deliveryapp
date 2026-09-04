# 🚀 Publicar DeliveryApp — GUÍA ULTRA RÁPIDA

Todo el código ya está listo y funcionando. Solo falta ponerlo en la nube.
Son **2 registros gratuitos** (sin tarjeta) y luego pegar 2 cadenas. **~20 minutos en total.**

---

## 📦 Paso 1 — Base de datos en Supabase (gratis, sin tarjeta)

1. Entra a **https://supabase.com** → **"Start your project"**
2. Regístrate con tu correo (ej: `medinahernandezeduardo73@gmail.com`) y confirma el email
3. Botón **"New project"**:
   - Name: `deliveryapp`
   - Database Password: escribe una y **guárdala** (la vas a necesitar)
   - Region: la más cercana (ej: `South America (São Paulo)`)
   - **Create new project** → espera 1-2 min
4. Menú izquierdo → **"SQL Editor"** → **"New query"**
5. Borra todo, **pega el contenido del archivo `setup.sql`** → **Run** ✅
6. Menú izquierdo → **"Project Settings"** → **"Data API"**
7. Copia:
   - **Project URL** (ej: `https://xxxx.supabase.co`)
   - **anon public key** (`eyJ...`)
8. Guárdalos para el Paso 3 👇

---

## 🚀 Paso 2 — Hosting en Render (gratis, sin tarjeta)

1. Necesitas cuenta de **GitHub** (gratis: **https://github.com/join**) y subir tu proyecto a un repositorio
   - Sube el contenido del ZIP **`DeliveryApp-PUBLICAR.zip`** a un repo llamado `deliveryapp`
2. Entra a **https://render.com** → **"Get Started"** → **"Continue with GitHub"** → conéctalo
3. **"New"** → **"Web Service"** → selecciona tu repo `deliveryapp`
4. **IMPORTANTE:** el archivo `render.yaml` ya trae la config, Render la usará sola.
   En "Environment" agrega estas 5 variables:
   | Variable | Valor |
   |----------|-------|
   | `ADMIN_EMAIL` | `medinahernandezeduardo73@gmail.com` |
   | `EMAIL_PASSWORD` | tu contraseña de app de Gmail |
   | `ADMIN_PASSWORD` | `admin123` |
   | `SUPABASE_URL` | del Paso 1 |
   | `SUPABASE_KEY` | del Paso 1 |
5. **"Create Web Service"** → espera 1-3 min
6. Render te da tu enlace **permanente**: `https://delivery-app.onrender.com` 🎉

---

## ✅ Listo: tu app queda con enlace permanente

- **App (clientes/repartidores):** `https://delivery-app.onrender.com`
- **Admin:** `https://delivery-app.onrender.com/admin` (contraseña `admin123`)

---

## 🔔 Notificación al repartidor (importante)

La notificación de pedido nuevo funciona **cuando el repartidor tiene la app abierta**
(en la pestaña del navegador). Suena alerta + aviso "🛎️ Nuevo pedido disponible".
El repartidor debe mantener la pestaña abierta (en el celular se puede dejar en primer plano).

> Para notificaciones "de verdad" (aunque esté en otra pestaña) hace falta Web Push,
> que es un nivel más avanzado. Si algún día lo quieres, te lo agrego.

---

## ⚠️ Problemas comunes

- **No llega el email de código:** revisa spam y que `EMAIL_PASSWORD` sea la contraseña de aplicación de Gmail.
- **No carga la app:** en Render, que `Health Check Path` sea `/` (el render.yaml ya lo pone).
- **Se borran datos:** revisa que `SUPABASE_URL` y `SUPABASE_KEY` estén correctas.
