// Migra data.json a PostgreSQL
// Uso: DATABASE_URL=postgres://... node migrate-to-pg.js
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const DATA_FILE = path.join(__dirname, 'data.json');
const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });

async function run() {
    const db = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        // settings
        const s = db.settings;
        await client.query(
            `INSERT INTO settings (brand, currency, commission_pct, city, delivery, zones)
             VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING`,
            [s.brand, s.currency, s.commissionPct, s.city, JSON.stringify(s.delivery), JSON.stringify(s.zones)]
        );

        // users
        for (const u of db.users || []) {
            await client.query(
                `INSERT INTO users (id,name,email,phone,role,password_hash,address,zone_id,restaurant_id,email_verified,verification_token,otp_code,otp_expires,wallet_balance,lat,lng,created_at)
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17) ON CONFLICT (id) DO NOTHING`,
                [u.id, u.name, u.email, u.phone, u.role, u.passwordHash, u.address, u.zoneId, u.restaurantId,
                 u.emailVerified !== false, u.verificationToken || null, u.otpCode || null, u.otpExpires || null,
                 u.walletBalance || 0, u.lat || null, u.lng || null, u.createdAt]
            );
        }

        // restaurants
        for (const r of db.restaurants || []) {
            await client.query(
                `INSERT INTO restaurants (id,owner_id,name,category,emoji,color,description,address,lat,lng,rating,rating_count,delivery_fee,min_order,eta_minutes,is_open,approved,created_at,menu)
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19) ON CONFLICT (id) DO NOTHING`,
                [r.id, r.ownerId, r.name, r.category, r.emoji, r.color, r.description, r.address, r.lat, r.lng,
                 r.rating, r.ratingCount, r.deliveryFee, r.minOrder, r.etaMinutes, r.isOpen, r.approved, r.createdAt,
                 JSON.stringify(r.menu || [])]
            );
        }

        // driver profiles
        for (const dp of db.driverProfiles || []) {
            await client.query(
                `INSERT INTO driver_profiles (user_id,vehicle,is_online,rating,deliveries,earnings,lat,lng)
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT (user_id) DO NOTHING`,
                [dp.userId, dp.vehicle, dp.isOnline, dp.rating, dp.deliveries, dp.earnings, dp.lat, dp.lng]
            );
        }

        // orders
        for (const o of db.orders || []) {
            await client.query(
                `INSERT INTO orders (id,code,security_code,customer_id,restaurant_id,driver_id,status,items,subtotal,delivery_fee,tip,total,driver_earnings,platform_fee,delivery_platform_fee,distance_km,zone_id,zone_name,customer_lat,customer_lng,address,notes,payment_method,coupon_code,discount,created_at,accepted_at,ready_at,assigned_at,picked_at,delivered_at,cancelled_at,cancelled_by,cancel_reason,rating,rating_comment)
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34,$35,$36) ON CONFLICT (id) DO NOTHING`,
                [o.id, o.code, o.securityCode, o.customerId, o.restaurantId, o.driverId, o.status, JSON.stringify(o.items),
                 o.subtotal, o.deliveryFee, o.tip, o.total, o.driverEarnings, o.platformFee, o.deliveryPlatformFee || 0,
                 o.distanceKm || 0, o.zoneId, o.zoneName, o.customerLat, o.customerLng, o.address, o.notes, o.paymentMethod,
                 o.couponCode, o.discount || 0, o.createdAt, o.acceptedAt, o.readyAt, o.assignedAt, o.pickedAt, o.deliveredAt,
                 o.cancelledAt, o.cancelledBy, o.cancelReason, o.rating, o.ratingComment]
            );
        }

        // coupons
        for (const c of db.coupons || []) {
            await client.query(
                `INSERT INTO coupons (id,code,type,value,min_order,max_discount,active,expires_at,usage_limit,used_count,created_at)
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) ON CONFLICT (id) DO NOTHING`,
                [c.id, c.code, c.type, c.value, c.minOrder, c.maxDiscount, c.active, c.expiresAt, c.usageLimit, c.usedCount, c.createdAt]
            );
        }

        // messages
        for (const m of db.messages || []) {
            await client.query(
                `INSERT INTO messages (id,order_id,sender_id,sender_role,text,created_at)
                 VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING`,
                [m.id, m.orderId, m.senderId, m.senderRole, m.text, m.createdAt]
            );
        }

        // notifications
        for (const n of db.notifications || []) {
            await client.query(
                `INSERT INTO notifications (id,user_id,title,text,created_at,read)
                 VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING`,
                [n.id, n.userId, n.title, n.text, n.createdAt, n.read]
            );
        }

        await client.query('COMMIT');
        console.log('Migración completada.');
    } catch (err) {
        await client.query('ROLLBACK');
        console.error('Error en migración:', err);
    } finally {
        client.release();
        await pool.end();
    }
}

run();