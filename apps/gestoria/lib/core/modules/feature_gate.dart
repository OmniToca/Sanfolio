import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gestoria_auth/gestoria_auth.dart';

import 'module_catalog.dart';

/// Licence kanceláře z `organization_modules`. Core je vždy.
class TenantConfig {
  const TenantConfig({
    required this.enabledModules,
    this.staffLocale = 'cs',
    this.defaultClientLocale = 'cs',
  });

  final Set<GestoriaModule> enabledModules;
  final String staffLocale;
  final String defaultClientLocale;

  bool isOn(GestoriaModule m) =>
      m == GestoriaModule.core || enabledModules.contains(m);
}

final tenantConfigProvider = FutureProvider<TenantConfig>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  final tenantId = auth.currentTenantId;
  final client = trySupabaseClient();
  if (tenantId == null || client == null) {
    return const TenantConfig(enabledModules: {});
  }
  final rows = await client
      .from('organization_modules')
      .select('module_key, status')
      .eq('tenant_id', tenantId)
      .isFilter('deleted_at', null);
  final enabled = <GestoriaModule>{};
  for (final raw in rows as List) {
    if (raw is! Map) continue;
    final status = '${raw['status']}';
    if (status != 'active' && status != 'trial') continue;
    final module = GestoriaModuleKey.fromKey('${raw['module_key']}');
    if (module != null) enabled.add(module);
  }
  return TenantConfig(enabledModules: enabled);
});

class FeatureGate extends ConsumerWidget {
  const FeatureGate({
    super.key,
    required this.module,
    required this.child,
    this.fallback = const SizedBox.shrink(),
  });

  final GestoriaModule module;
  final Widget child;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(tenantConfigProvider);
    return cfg.maybeWhen(
      data: (c) => c.isOn(module) ? child : fallback,
      orElse: () => module == GestoriaModule.core ? child : fallback,
    );
  }
}
