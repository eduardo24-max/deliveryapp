import 'package:flutter/material.dart';

import '../theme.dart';

Color colorFromHex(String hex) {
  var value = hex.replaceAll('#', '').trim();
  if (value.length == 6) value = 'FF$value';
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? kBrand : Color(parsed);
}

String statusLabel(String status) => switch (status) {
      'pending' => 'Nuevo',
      'accepted' => 'Aceptado',
      'preparing' => 'Preparando',
      'ready' => 'Listo',
      'assigned' => 'Repartidor asignado',
      'picked_up' => 'En camino',
      'delivered' => 'Entregado',
      'cancelled' => 'Cancelado',
      _ => status,
    };

Color statusColor(String status) => switch (status) {
      'pending' => kBrand,
      'accepted' => kBlue,
      'preparing' => const Color(0xFF7C3AED),
      'ready' => const Color(0xFF0D9488),
      'assigned' => const Color(0xFF4F46E5),
      'picked_up' => kGreen,
      'delivered' => kGreen,
      'cancelled' => kMuted,
      _ => kMuted,
    };

String statusEmoji(String status) => '';

String relativeTime(DateTime? date) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays == 1) return 'ayer';
  return 'hace ${diff.inDays} dÃ­as';
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: error ? kRed : kInk,
        content: Row(
          children: [
            Icon(error ? Icons.error_outline : Icons.check_circle_outline,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

class AppLogo extends StatelessWidget {
  final bool light;
  final double size;
  const AppLogo({super.key, this.light = false, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.62),
          child: Image.asset(
            'assets/logo.jpeg',
            width: size * 1.9,
            height: size * 1.9,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: size * 1.9,
              height: size * 1.9,
              color: kBrand,
              alignment: Alignment.center,
              child: Icon(Icons.bolt_rounded, color: Colors.white, size: size * 1.35),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'VelozEat',
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
            color: light ? Colors.white : kInk,
          ),
        ),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  final String status;
  final bool small;
  const StatusPill(this.status, {super.key, this.small = false});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 11, vertical: small ? 4 : 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(
          color: color,
          fontSize: small ? 10.5 : 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class EmojiBox extends StatelessWidget {
  final String emoji;
  final double size;
  final Color color;
  const EmojiBox({
    super.key,
    required this.emoji,
    this.size = 56,
    this.color = kBrand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      alignment: Alignment.center,
      child: emoji.trim().isEmpty || emoji.runes.any((r) => r > 0x00FF)
          ? Icon(Icons.restaurant_rounded, size: size * 0.42, color: color)
          : Text(emoji, style: TextStyle(fontSize: size * 0.48)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: kBrand,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            child: Text(action!),
          ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    this.subtitle = '',
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 54)),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: kMuted, height: 1.4)),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class LoadingBox extends StatelessWidget {
  final String label;
  const LoadingBox({super.key, this.label = 'Cargando...'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 3, color: kBrand),
            ),
            const SizedBox(height: 14),
            Text(label, style: const TextStyle(color: kMuted, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const InfoRow(this.icon, this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? kMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: color ?? kMuted, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kLine),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: card,
    );
  }
}

class PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;
  const PriceRow(this.label, this.value, {super.key, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                  fontSize: bold ? 16 : 13.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                  color: color ?? (bold ? kInk : kMuted),
                )),
          ),
          Text(value,
              style: TextStyle(
                fontSize: bold ? 18 : 13.5,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                color: color ?? kInk,
              )),
        ],
      ),
    );
  }
}

class BrandBadge extends StatelessWidget {
  final String text;
  final IconData icon;
  const BrandBadge(this.text, {super.key, this.icon = Icons.bolt_rounded});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kBrand.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: kBrand),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kBrand)),
        ],
      ),
    );
  }
}
