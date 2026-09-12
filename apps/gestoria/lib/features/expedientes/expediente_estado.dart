import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

const expedienteEstadoKeys = <String>[
  'abierto',
  'en_curso',
  'espera_cliente',
  'espera_admin',
  'hecho',
  'archivado',
];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Inbox stale: jen `en_curso`, N dní z nastavení, 0 = vypnuto.
bool isExpedienteStale({
  required String estado,
  required DateTime updatedAt,
  required int staleDays,
  required DateTime today,
}) {
  if (estado != 'en_curso' || staleDays <= 0) return false;
  final limit = _day(today).subtract(Duration(days: staleDays));
  return !_day(updatedAt).isAfter(limit);
}

class ExpedienteEstadoPicker extends StatelessWidget {
  const ExpedienteEstadoPicker({
    super.key,
    required this.estado,
    required this.onChanged,
  });

  final String estado;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final current =
        expedienteEstadoKeys.contains(estado) ? estado : 'abierto';
    return DropdownButtonFormField<String>(
      value: current,
      decoration: InputDecoration(labelText: 'expedientes.estadoLabel'.tr()),
      items: [
        for (final k in expedienteEstadoKeys)
          DropdownMenuItem(
            value: k,
            child: Text('expedientes.estado.$k'.tr()),
          ),
      ],
      onChanged: (v) {
        if (v == null || v == current) return;
        onChanged(v);
      },
    );
  }
}
