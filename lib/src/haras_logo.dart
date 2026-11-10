import 'package:flutter/material.dart';

/// Usa a MESMA marca dos ícones de instalação, disponibilizada como asset Flutter.
class HarasLogo extends StatelessWidget {
  final double size;
  const HarasLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.19),
      child: Image.asset(
        'assets/icon/haras_f5e_app.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'Logo do Haras F5E',
      ),
    );
  }
}
