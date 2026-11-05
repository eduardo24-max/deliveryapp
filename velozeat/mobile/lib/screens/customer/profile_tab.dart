import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_client.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class CustomerProfileTab extends StatefulWidget {
  const CustomerProfileTab({super.key});

  @override
  State<CustomerProfileTab> createState() => _CustomerProfileTabState();
}

class _CustomerProfileTabState extends State<CustomerProfileTab> {
  bool _saving = false;
  double _walletBalance = 0;
  bool _walletBusy = false;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final res = await context.read<AppState>().api.wallet();
      if (mounted) setState(() => _walletBalance = asDouble(res['balance']));
    } catch (_) {}
  }

  Future<void> _topup() async {
    final controller = TextEditingController(text: '100');
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Agregar fondos'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Monto', prefixIcon: Icon(Icons.attach_money_rounded)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, double.tryParse(controller.text.trim())),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 42)),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || amount <= 0 || !mounted) return;
    setState(() => _walletBusy = true);
    try {
      final res = await context.read<AppState>().api.topupWallet(amount);
      if (mounted) {
        setState(() => _walletBalance = asDouble(res['balance']));
        showSnack(context, (res['message'] ?? 'Fondos agregados').toString());
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _walletBusy = false);
    }
  }

  Future<void> _editAddress() async {
    final app = context.read<AppState>();
    final controller = TextEditingController(text: app.user?.address ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('DirecciÃ³n de entrega'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Calle, nÃºmero, colonia y referencias'),
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
    if (value == null || value.length < 5 || !mounted) return;
    setState(() => _saving = true);
    try {
      await app.updateProfile({'address': value});
      if (mounted) showSnack(context, 'DirecciÃ³n actualizada.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Cerrar sesiÃ³n'),
        content: const Text('Â¿Quieres salir de tu cuenta VelozEat?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 42)),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AppState>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;
    if (user == null) return const SizedBox.shrink();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          Text('Mi perfil', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kBrand, kBrandDark],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    user.name.isEmpty ? '?' : user.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text('${user.roleLabel} VelozEat',
                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              children: [
                _row(Icons.phone_outlined, 'TelÃ©fono', user.phone.isEmpty ? 'Sin registrar' : user.phone),
                const Divider(height: 22),
                _row(Icons.mail_outline, 'Correo', user.email),
                const Divider(height: 22),
                _row(
                  Icons.location_on_outlined,
                  'DirecciÃ³n',
                  user.address.isEmpty ? 'Agrega tu direcciÃ³n de entrega' : user.address,
                  action: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: kBrand),
                        )
                      : TextButton(
                          onPressed: _editAddress,
                          style: TextButton.styleFrom(
                            foregroundColor: kBrand,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(60, 30),
                          ),
                          child: const Text('Editar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            color: kBrand.withValues(alpha: 0.05),
            child: Row(
              children: [
                const Text('â¡', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Modo demo', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        'Los pagos con tarjeta son simulados. Para probar el flujo completo usa otra sesiÃ³n como restaurante o repartidor.',
                        style: TextStyle(fontSize: 11.5, color: kMuted.withValues(alpha: 0.95), height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SurfaceCard(
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: kBrand.withValues(alpha: 0.12), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Icon(Icons.account_balance_wallet_rounded, color: kBrand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Billetera VelozEat', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      Text(money(_walletBalance), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kBrand)),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: _walletBusy ? null : _topup,
                  style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
                  child: _walletBusy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Agregar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _logout,
            style: OutlinedButton.styleFrom(foregroundColor: kRed, side: const BorderSide(color: kRed)),
            child: const Text('Cerrar sesiÃ³n'),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text('VelozEat v1.0 Â· ${app.api.baseUrl}',
                style: const TextStyle(fontSize: 10.5, color: kMuted)),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, {Widget? action}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: kBrand),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk)),
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}
