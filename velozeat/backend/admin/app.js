const API = '';
let token = localStorage.getItem('velozeat_admin_token') || '';

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));

function money(n) {
  const v = Number(n) || 0;
  return v % 1 !== 0 ? `$${v.toFixed(2)}` : `$${Math.round(v)}`;
}

async function api(path, opts = {}) {
  const headers = { 'Content-Type': 'application/json', ...(opts.headers || {}) };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const res = await fetch(API + path, { ...opts, headers });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `Error ${res.status}`);
  return data;
}

function showView(name) {
  $$('.view').forEach((v) => v.classList.remove('active'));
  $(`#${name}View`).classList.add('active');
  $$('.nav-btn').forEach((b) => b.classList.toggle('active', b.dataset.view === name));
}

function setAuthed(authed) {
  $('#sidebar').hidden = !authed;
  if (authed) {
    $('#loginView').classList.remove('active');
    showView('dashboard');
    loadDashboard();
  } else {
    $$('.view').forEach((v) => v.classList.remove('active'));
    $('#loginView').classList.add('active');
  }
}

// Login
$('#loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#loginError').textContent = '';
  try {
    const data = await api('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        email: $('#loginEmail').value.trim(),
        password: $('#loginPassword').value,
      }),
    });
    if (data.user?.role !== 'admin') throw new Error('Esta cuenta no es de administrador.');
    token = data.token;
    localStorage.setItem('velozeat_admin_token', token);
    setAuthed(true);
  } catch (err) {
    $('#loginError').textContent = err.message;
  }
});

$('#logoutBtn').addEventListener('click', () => {
  token = '';
  localStorage.removeItem('velozeat_admin_token');
  setAuthed(false);
});

$$('.nav-btn').forEach((btn) => {
  btn.addEventListener('click', () => {
    showView(btn.dataset.view);
    if (btn.dataset.view === 'dashboard') loadDashboard();
    if (btn.dataset.view === 'approvals') loadApprovals();
    if (btn.dataset.view === 'restaurants') loadRestaurants();
    if (btn.dataset.view === 'orders') loadOrders();
    if (btn.dataset.view === 'settings') loadSettings();
  });
});

async function loadDashboard() {
  const data = await api('/api/admin/stats');
  const s = data.stats;
  $('#statsGrid').innerHTML = `
    <div class="stat"><div class="label">GMV hoy</div><div class="value brand">${money(s.gmvToday)}</div></div>
    <div class="stat"><div class="label">Comisión comida</div><div class="value">${money(s.foodCommissionToday)}</div></div>
    <div class="stat"><div class="label">Comisión envío</div><div class="value">${money(s.deliveryCommissionToday)}</div></div>
    <div class="stat"><div class="label">Comisión total</div><div class="value brand">${money(s.commissionToday)}</div></div>
    <div class="stat"><div class="label">Pedidos hoy</div><div class="value">${s.ordersToday}</div></div>
    <div class="stat"><div class="label">Activos</div><div class="value">${s.activeOrders}</div></div>
    <div class="stat"><div class="label">Entregados hoy</div><div class="value">${s.deliveredToday}</div></div>
    <div class="stat"><div class="label">Envío promedio</div><div class="value">${money(s.avgDeliveryFee)}</div></div>
    <div class="stat"><div class="label">Clientes</div><div class="value">${s.customers}</div></div>
    <div class="stat"><div class="label">Repartidores</div><div class="value">${s.drivers}</div></div>
    <div class="stat"><div class="label">Restaurantes</div><div class="value">${s.restaurants}</div></div>
    <div class="stat"><div class="label">Pendientes</div><div class="value">${s.pendingRestaurants}</div></div>
  `;
  const orders = data.recentOrders || [];
  $('#recentOrders').innerHTML = orders.length
    ? `<table class="table"><thead><tr><th>#</th><th>Restaurante</th><th>Cliente</th><th>Total</th><th>Comisión</th><th>Estado</th></tr></thead><tbody>
       ${orders.map((o) => `<tr><td>#${o.code}</td><td>${o.restaurantName}</td><td>${o.customerName}</td><td>${money(o.total)}</td><td>${money(o.platformFee)}</td><td>${o.status}</td></tr>`).join('')}
       </tbody></table>`
    : '<p class="sub">Sin pedidos aún.</p>';
}

async function loadApprovals() {
  const data = await api('/api/admin/stats');
  const pending = data.pendingRestaurants || [];
  $('#pendingList').innerHTML = pending.length
    ? pending.map((r) => `
        <div class="item">
          <span style="font-size:24px">${r.emoji}</span>
          <div>
            <div class="title">${r.name}</div>
            <div class="sub">${r.category} · ${r.address} · Envío base ${money(r.deliveryFee)}</div>
          </div>
          <div class="actions">
            <button class="approve" data-id="${r.id}" data-approved="true">Aprobar</button>
            <button class="reject" data-id="${r.id}" data-approved="false">Rechazar</button>
          </div>
        </div>`).join('')
    : '<p class="sub">No hay restaurantes pendientes.</p>';

  $('#pendingList').querySelectorAll('button[data-id]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      await api(`/api/admin/restaurants/${btn.dataset.id}/approve`, {
        method: 'POST',
        body: JSON.stringify({ approved: btn.dataset.approved === 'true' }),
      });
      loadApprovals();
      loadRestaurants();
    });
  });
}

async function loadRestaurants() {
  const data = await api('/api/admin/restaurants');
  const list = data.restaurants || [];
  $('#restaurantsList').innerHTML = list.length
    ? list.map((r) => `
        <div class="item">
          <span style="font-size:24px">${r.emoji}</span>
          <div>
            <div class="title">${r.name} ${r.approved ? '✅' : '⏳'}</div>
            <div class="sub">${r.category} · ${r.address} · ⭐ ${r.rating} · Envío base ${money(r.deliveryFee)} · ${r.lat.toFixed(4)}, ${r.lng.toFixed(4)}</div>
          </div>
        </div>`).join('')
    : '<p class="sub">Sin restaurantes.</p>';
}

async function loadOrders() {
  const data = await api('/api/admin/orders');
  const list = data.orders || [];
  $('#ordersList').innerHTML = list.length
    ? `<table class="table"><thead><tr><th>#</th><th>Restaurante</th><th>Cliente</th><th>Zona</th><th>km</th><th>Envío</th><th>Total</th><th>Comisión</th><th>Estado</th></tr></thead><tbody>
       ${list.map((o) => `<tr>
         <td>#${o.code}</td><td>${o.restaurantName}</td><td>${o.customerName}</td>
         <td>${o.zoneName || '-'}</td><td>${Number(o.distanceKm || 0).toFixed(1)}</td>
         <td>${money(o.deliveryFee)}</td><td>${money(o.total)}</td><td>${money(o.platformFee)}</td><td>${o.status}</td>
       </tr>`).join('')}
       </tbody></table>`
    : '<p class="sub">Sin pedidos.</p>';
}

async function loadSettings() {
  const data = await api('/api/admin/stats');
  const s = data.settings || {};
  const d = s.delivery || {};
  $('#commissionPct').value = ((s.commissionPct || 0) * 100).toFixed(2);
  $('#baseFee').value = d.baseFee ?? 12;
  $('#perKm').value = d.perKm ?? 4;
  $('#minFee').value = d.minFee ?? 15;
  $('#maxFee').value = d.maxFee ?? 70;
  $('#maxRadiusKm').value = d.maxRadiusKm ?? 25;
  $('#driverSharePct').value = ((d.driverSharePct || 0.8) * 100).toFixed(2);
}

$('#settingsForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#settingsOk').textContent = '';
  try {
    await api('/api/admin/settings', {
      method: 'PUT',
      body: JSON.stringify({
        commissionPct: Number($('#commissionPct').value) / 100,
        delivery: {
          baseFee: Number($('#baseFee').value),
          perKm: Number($('#perKm').value),
          minFee: Number($('#minFee').value),
          maxFee: Number($('#maxFee').value),
          maxRadiusKm: Number($('#maxRadiusKm').value),
          driverSharePct: Number($('#driverSharePct').value) / 100,
        },
      }),
    });
    $('#settingsOk').textContent = 'Configuración guardada.';
  } catch (err) {
    $('#settingsOk').textContent = err.message;
  }
});

$('#passwordForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('#passwordOk').textContent = '';
  $('#passwordError').textContent = '';
  try {
    await api('/api/admin/password', {
      method: 'PUT',
      body: JSON.stringify({
        currentPassword: $('#currentPassword').value,
        newPassword: $('#newPassword').value,
      }),
    });
    $('#passwordOk').textContent = 'Contraseña actualizada.';
    $('#passwordForm').reset();
  } catch (err) {
    $('#passwordError').textContent = err.message;
  }
});

// Boot
if (token) {
  api('/api/admin/stats').then(() => setAuthed(true)).catch(() => {
    token = '';
    localStorage.removeItem('velozeat_admin_token');
    setAuthed(false);
  });
} else {
  setAuthed(false);
}