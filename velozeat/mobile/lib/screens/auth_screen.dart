import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _busy = false;
  bool _resendBusy = false;
  bool _obscure = true;
  String _role = 'customer';

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _restaurantName = TextEditingController();
  final _address = TextEditingController();
  String _category = 'Tacos';
  String _vehicle = 'moto';

  static const _categories = [
    'Tacos',
    'Hamburguesas',
    'Sushi',
    'Pizza',
    'Antojitos',
    'Postres',
    'Otros',
  ];

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _restaurantName.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _resendVerification() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      showSnack(context, 'Escribe tu correo para reenviar la verificacion.', error: true);
      return;
    }
    setState(() => _resendBusy = true);
    try {
      await context.read<AppState>().api.resendVerification(email);
      if (mounted) showSnack(context, 'Te enviamos un nuevo correo de verificacion.');
    } on ApiException catch (e) {
      if (e.message.toLowerCase().contains('conectar') || e.message.toLowerCase().contains('servidor')) {
        await _configureServer();
        return;
      }
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _resendBusy = false);
    }
  }

  Future<void> _configureServer() async {
    final controller = TextEditingController(text: context.read<AppState>().api.baseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Servidor backend'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'http://192.168.1.50:3100'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 42)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    context.read<AppState>().api.setBaseUrl(value);
    showSnack(context, 'Servidor configurado: $value');
  }

  Future<String?> _showOtpDialog(String email) async {
    final controller = TextEditingController();
    bool resending = false;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Código de verificación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Te enviamos un código de 6 dígitos a $email.', style: const TextStyle(fontSize: 12.5, color: kMuted)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 8),
                decoration: const InputDecoration(hintText: '000000', counterText: ''),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: resending
                    ? null
                    : () async {
                        setDialogState(() => resending = true);
                        try {
                          await context.read<AppState>().api.resendOtp(email);
                          if (context.mounted) showSnack(context, 'Código reenviado.');
                        } on ApiException catch (e) {
                          if (context.mounted) showSnack(context, e.message, error: true);
                        } finally {
                          setDialogState(() => resending = false);
                        }
                      },
                child: resending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Reenviar código'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              style: FilledButton.styleFrom(minimumSize: const Size(100, 42)),
              child: const Text('Verificar'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      if (_isLogin) {
        final email = _email.text.trim();
        final res = await app.api.login(email, _password.text);
        if (res['requiresVerification'] == true) {
          final code = await _showOtpDialog(email);
          if (code == null) return;
          final vres = await app.api.verifyOtp(email, code);
          await app.api.setToken(vres['token']?.toString());
          await app.refresh();
          if (mounted) showSnack(context, '¡Bienvenido de vuelta!');
          return;
        }
        await app.api.setToken(res['token']?.toString());
        await app.refresh();
        if (mounted) showSnack(context, '¡Bienvenido de vuelta!');
        if (mounted) showSnack(context, '¡Bienvenido de vuelta!');
      } else {
        await app.register({
          'name': _name.text.trim(),
          'email': _email.text.trim(),
          'phone': _phone.text.trim(),
          'password': _password.text,
          'role': _role,
          'address': _address.text.trim(),
          if (_role == 'restaurant') 'restaurantName': _restaurantName.text.trim(),
          if (_role == 'restaurant') 'category': _category,
          if (_role == 'driver') 'vehicle': _vehicle,
        });
        if (mounted) showSnack(context, 'Cuenta creada. Revisa tu correo para verificar tu cuenta.');
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'No se pudo completar el registro.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demoLogin(String email, String password) async {
    if (_busy) return;
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _isLogin = true;
      _email.text = email;
      _password.text = password;
    });
    try {
      await app.login(email, password);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kBrand, Color(0xFF9F67FF)],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Row(
                children: [
                  const AppLogo(light: true, size: 24),
                  const Spacer(),
                  IconButton(
                    onPressed: _configureServer,
                    icon: const Icon(Icons.settings_rounded, color: Colors.white70),
                  ),
                  BrandBadge('Entrega rápida', icon: Icons.bolt_rounded),
                ],
              ),
              const SizedBox(height: 30),
              const Text(
                'Tu comida,\na toda velocidad.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1.08,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Restaurantes, repartidores y clientes en una sola app.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14.5, height: 1.4),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, 14)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ModeSwitch(
                      isLogin: _isLogin,
                      onChanged: (value) => setState(() => _isLogin = value),
                    ),
                    const SizedBox(height: 20),
                    if (!_isLogin) ...[
                      _label('¿Cómo vas a usar VelozEat?'),
                      const SizedBox(height: 8),
                      _RolePicker(
                        role: _role,
                        onChanged: (value) => setState(() => _role = value),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (!_isLogin) ...[
                      TextField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nombre completo',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_isLogin && _role == 'restaurant') ...[
                      TextField(
                        controller: _restaurantName,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del restaurante',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: const InputDecoration(
                          labelText: 'Categoría',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: _categories
                            .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: (value) => setState(() => _category = value ?? 'Tacos'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _address,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Dirección del restaurante',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_isLogin && _role == 'customer') ...[
                      TextField(
                        controller: _address,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Tu dirección de entrega',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_isLogin && _role == 'driver') ...[
                      DropdownButtonFormField<String>(
                        initialValue: _vehicle,
                        decoration: const InputDecoration(
                          labelText: 'Tu vehículo',
                          prefixIcon: Icon(Icons.two_wheeler_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'moto', child: Text(' Moto')),
                          DropdownMenuItem(value: 'bici', child: Text(' Bicicleta')),
                          DropdownMenuItem(value: 'auto', child: Text(' Auto')),
                        ],
                        onChanged: (value) => setState(() => _vehicle = value ?? 'moto'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                    ),
                    if (_isLogin) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _resendBusy ? null : _resendVerification,
                          child: _resendBusy
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('No recibiste el correo? Reenviar', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                            )
                          : Text(_isLogin ? 'Iniciar sesión' : 'Crear mi cuenta'),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text('Cuentas demo',
                              style: TextStyle(fontSize: 11.5, color: kMuted.withValues(alpha: 0.9), fontWeight: FontWeight.w700)),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _DemoChip(' Cliente', () => _demoLogin('cliente@velozeat.com', 'cliente123')),
                        _DemoChip(' Restaurante', () => _demoLogin('taqueria@velozeat.com', 'restaurante123')),
                        _DemoChip(' Repartidor', () => _demoLogin('repartidor@velozeat.com', 'repartidor123')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Administración privada: ${context.read<AppState>().api.baseUrl}/admin',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10.5, color: kMuted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Servidor: ${context.read<AppState>().api.baseUrl}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 10.5, color: kMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kMuted),
      );
}

class _ModeSwitch extends StatelessWidget {
  final bool isLogin;
  final ValueChanged<bool> onChanged;
  const _ModeSwitch({required this.isLogin, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          _tab('Iniciar sesión', isLogin, () => onChanged(true)),
          _tab('Registrarme', !isLogin, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: active
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: active ? kInk : kMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _RolePicker extends StatelessWidget {
  final String role;
  final ValueChanged<String> onChanged;
  const _RolePicker({required this.role, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const roles = [
      ('customer', '', 'Cliente'),
      ('restaurant', '', 'Restaurante'),
      ('driver', '', 'Repartidor'),
    ];
    return Row(
      children: roles.map((r) {
        final active = role == r.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(r.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                color: active ? kBrand.withValues(alpha: 0.10) : kBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: active ? kBrand : kLine, width: active ? 1.5 : 1),
              ),
              child: Column(
                children: [
                  Text(r.$2, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(
                    r.$3,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: active ? kBrand : kMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DemoChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DemoChip(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: kLine),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kInk)),
      ),
    );
  }
}
