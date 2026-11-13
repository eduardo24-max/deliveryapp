-- VelozEat PostgreSQL Schema
-- Ejecutar en Supabase SQL Editor o psql

CREATE TABLE IF NOT EXISTS settings (
    id SERIAL PRIMARY KEY,
    brand VARCHAR(100) DEFAULT 'VelozEat',
    currency VARCHAR(10) DEFAULT 'MXN',
    commission_pct DECIMAL(5,4) DEFAULT 0.15,
    city VARCHAR(100) DEFAULT 'Ciudad de México',
    delivery JSONB DEFAULT '{"baseFee":12,"perKm":4,"minFee":15,"maxFee":70,"driverSharePct":0.8}',
    zones JSONB DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    email VARCHAR(200) UNIQUE NOT NULL,
    phone VARCHAR(50),
    role VARCHAR(20) NOT NULL CHECK (role IN ('customer','restaurant','driver','admin')),
    password_hash TEXT NOT NULL,
    address TEXT,
    zone_id VARCHAR(50),
    restaurant_id VARCHAR(50),
    email_verified BOOLEAN DEFAULT FALSE,
    verification_token TEXT,
    otp_code VARCHAR(10),
    otp_expires BIGINT,
    wallet_balance DECIMAL(10,2) DEFAULT 0,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    created_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS restaurants (
    id VARCHAR(50) PRIMARY KEY,
    owner_id VARCHAR(50) REFERENCES users(id),
    name VARCHAR(200) NOT NULL,
    category VARCHAR(100),
    emoji VARCHAR(20),
    color VARCHAR(20),
    description TEXT,
    address TEXT,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    rating DECIMAL(3,1) DEFAULT 5.0,
    rating_count INTEGER DEFAULT 0,
    delivery_fee DECIMAL(10,2) DEFAULT 15,
    min_order DECIMAL(10,2) DEFAULT 50,
    eta_minutes INTEGER DEFAULT 30,
    is_open BOOLEAN DEFAULT FALSE,
    approved BOOLEAN DEFAULT FALSE,
    created_at BIGINT NOT NULL,
    menu JSONB DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS orders (
    id VARCHAR(50) PRIMARY KEY,
    code VARCHAR(20) NOT NULL,
    security_code VARCHAR(10) NOT NULL,
    customer_id VARCHAR(50) REFERENCES users(id),
    restaurant_id VARCHAR(50) REFERENCES restaurants(id),
    driver_id VARCHAR(50) REFERENCES users(id),
    status VARCHAR(20) NOT NULL,
    items JSONB NOT NULL,
    subtotal DECIMAL(10,2) NOT NULL,
    delivery_fee DECIMAL(10,2) NOT NULL,
    tip DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) NOT NULL,
    driver_earnings DECIMAL(10,2) DEFAULT 0,
    platform_fee DECIMAL(10,2) DEFAULT 0,
    delivery_platform_fee DECIMAL(10,2) DEFAULT 0,
    distance_km DECIMAL(5,1) DEFAULT 0,
    zone_id VARCHAR(50),
    zone_name VARCHAR(100),
    customer_lat DOUBLE PRECISION,
    customer_lng DOUBLE PRECISION,
    address TEXT,
    notes TEXT,
    payment_method VARCHAR(20) DEFAULT 'cash',
    coupon_code VARCHAR(50),
    discount DECIMAL(10,2) DEFAULT 0,
    created_at BIGINT NOT NULL,
    accepted_at BIGINT,
    ready_at BIGINT,
    assigned_at BIGINT,
    picked_at BIGINT,
    delivered_at BIGINT,
    cancelled_at BIGINT,
    cancelled_by VARCHAR(20),
    cancel_reason TEXT,
    rating INTEGER,
    rating_comment TEXT
);

CREATE TABLE IF NOT EXISTS driver_profiles (
    user_id VARCHAR(50) PRIMARY KEY REFERENCES users(id),
    vehicle VARCHAR(20) DEFAULT 'moto',
    is_online BOOLEAN DEFAULT FALSE,
    rating DECIMAL(3,1) DEFAULT 5.0,
    deliveries INTEGER DEFAULT 0,
    earnings DECIMAL(10,2) DEFAULT 0,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION
);

CREATE TABLE IF NOT EXISTS coupons (
    id VARCHAR(50) PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    type VARCHAR(10) NOT NULL CHECK (type IN ('percent','fixed')),
    value DECIMAL(10,2) NOT NULL,
    min_order DECIMAL(10,2) DEFAULT 0,
    max_discount DECIMAL(10,2),
    active BOOLEAN DEFAULT TRUE,
    expires_at BIGINT,
    usage_limit INTEGER DEFAULT 100,
    used_count INTEGER DEFAULT 0,
    created_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
    id VARCHAR(50) PRIMARY KEY,
    order_id VARCHAR(50) REFERENCES orders(id),
    sender_id VARCHAR(50) REFERENCES users(id),
    sender_role VARCHAR(20),
    text TEXT NOT NULL,
    created_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS notifications (
    id VARCHAR(50) PRIMARY KEY,
    user_id VARCHAR(50) REFERENCES users(id),
    title VARCHAR(200),
    text TEXT,
    created_at BIGINT NOT NULL,
    read BOOLEAN DEFAULT FALSE
);

-- Tabla para almacenar todo el estado de la app como JSON (migración simple)
CREATE TABLE IF NOT EXISTS app_state (
    id INTEGER PRIMARY KEY DEFAULT 1,
    data JSONB NOT NULL,
    updated_at BIGINT NOT NULL
);

-- Índices para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant ON orders(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_driver ON orders(driver_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_messages_order ON messages(order_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);