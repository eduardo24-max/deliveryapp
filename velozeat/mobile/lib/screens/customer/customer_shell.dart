import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import 'cart_screen.dart';
import 'home_tab.dart';
import 'orders_tab.dart';
import 'profile_tab.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeTab(),
          CustomerOrdersTab(),
          CustomerProfileTab(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (app.cartCount > 0 && app.cartRestaurant != null)
            _CartBar(
              count: app.cartCount,
              total: app.cartSubtotal,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CartScreen(restaurant: app.cartRestaurant!)),
              ),
            ),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront_rounded),
                label: 'Inicio',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Pedidos',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Perfil',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  final int count;
  final double total;
  final VoidCallback onTap;
  const _CartBar({required this.count, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Material(
        color: kInk,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: kBrand,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Ver carrito',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  money(total),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_rounded, color: kAccent, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
