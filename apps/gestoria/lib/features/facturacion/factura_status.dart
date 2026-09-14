import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Tečka stavu knihy. Features nesmí házet nahodilé Color().
Color facturaEstadoColor(String estado) {
  return switch (estado) {
    'emitida' => AppTheme.statusOk,
    'pendiente' => AppTheme.statusWatch,
    'error' => AppTheme.statusAlert,
    'borrador' || 'guardada' => AppTheme.statusWarn,
    _ => AppTheme.pencil,
  };
}

class FacturaEstadoDot extends StatelessWidget {
  const FacturaEstadoDot({super.key, required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: facturaEstadoColor(estado),
        shape: BoxShape.circle,
      ),
    );
  }
}
