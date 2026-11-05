import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'screens/customer/customer_shell.dart';
import 'screens/driver/driver_shell.dart';
import 'screens/restaurant/restaurant_shell.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const VelozEatApp()));
  state.init();
}

class VelozEatApp extends StatelessWidget {
  const VelozEatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VelozEat',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Gate(),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.loading) return const _Splash();
    final user = app.user;
    if (user == null) return const AuthScreen();

    return KeyedSubtree(
      key: ValueKey('${user.id}-${user.role}'),
      child: switch (user.role) {
        'restaurant' => const RestaurantShell(),
        'driver' => const DriverShell(),
        _ => const CustomerShell(),
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kBrand, kBrandDark],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 30, offset: const Offset(0, 12)),
                  ],
                ),
                alignment: Alignment.center,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset('assets/logo.jpeg', width: 92, height: 92, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'VelozEat',
                style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2),
              ),
              const SizedBox(height: 4),
              Text(
                'Tu comida, a toda velocidad.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5),
              ),
              const SizedBox(height: 30),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
