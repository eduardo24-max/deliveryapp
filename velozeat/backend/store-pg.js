const store = require('./store');
const { Pool } = require('pg');

const pool = process.env.DATABASE_URL
    ? new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } })
    : null;

function usePg() { return !!pool; }

async function load() {
    if (usePg()) {
        const client = await pool.connect();
        try {
            const res = await client.query('SELECT data FROM app_state WHERE id = 1');
            if (res.rows.length > 0) {
                console.log('Cargado desde PostgreSQL');
                return res.rows[0].data;
            }
            // No data yet: seed and save
            const seed = store.seed ? store.seed() : store.load();
            await client.query(
                'INSERT INTO app_state (id, data, updated_at) VALUES (1, $1, $2) ON CONFLICT (id) DO NOTHING',
                [JSON.stringify(seed), Date.now()]
            );
            console.log('Datos iniciales guardados en PostgreSQL');
            return seed;
        } finally {
            client.release();
        }
    }
    return store.load();
}

function save() {
    if (usePg() && global.__db) {
        // Fire-and-forget async save
        pool.query(
            'INSERT INTO app_state (id, data, updated_at) VALUES (1, $1, $2) ON CONFLICT (id) DO UPDATE SET data = $1, updated_at = $2',
            [JSON.stringify(global.__db), Date.now()]
        ).catch(err => console.error('Error guardando en PG:', err.message));
        return;
    }
    store.save();
}

function reset() {
    if (usePg()) {
        const seed = store.seed ? store.seed() : store.load();
        global.__db = seed;
        pool.query(
            'INSERT INTO app_state (id, data, updated_at) VALUES (1, $1, $2) ON CONFLICT (id) DO UPDATE SET data = $1, updated_at = $2',
            [JSON.stringify(seed), Date.now()]
        ).catch(err => console.error('Error reseteando PG:', err.message));
        return seed;
    }
    return store.reset();
}

// Re-export
const { hashPassword, verifyPassword } = store;

module.exports = { load, save, reset, hashPassword, verifyPassword };
