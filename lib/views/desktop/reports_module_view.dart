import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/report_controller.dart';
import '../../controllers/user_controller.dart';
import '../../core/theme/app_theme.dart';
import '../shared/widgets/pro_ui.dart';
import '../shared/widgets/ui_kit.dart';
import 'reports/activity_tab.dart';
import 'reports/report_catalog_tab.dart';

enum _ReportsTab { reports, activity }

/// Módulo "Reportes y auditoría": catálogo de reportes descargables (PDF,
/// Excel o CSV) y la actividad de cada usuario en lenguaje claro.
class ReportsModuleView extends StatefulWidget {
  const ReportsModuleView({super.key});

  @override
  State<ReportsModuleView> createState() => _ReportsModuleViewState();
}

class _ReportsModuleViewState extends State<ReportsModuleView> {
  _ReportsTab _tab = _ReportsTab.reports;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ReportController>().ensureLoaded();
      try {
        context.read<UserController>().ensureLoaded();
      } on ProviderNotFoundException {
        // Sin controlador de usuarios: los nombres se toman de la bitácora.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ReportController ctrl = context.watch<ReportController>();
    final bool narrow = MediaQuery.sizeOf(context).width < 900;

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PageHeader(
              title: 'Reportes y auditoría',
              subtitle: 'Descarga reportes en PDF, Excel o CSV y revisa lo que hace cada usuario.',
              actions: <Widget>[
                AppSegmentedControl<_ReportsTab>(
                  selected: _tab,
                  onChanged: (_ReportsTab t) => setState(() => _tab = t),
                  segments: const <AppSegment<_ReportsTab>>[
                    AppSegment<_ReportsTab>(
                      value: _ReportsTab.reports,
                      label: 'Reportes',
                      icon: Icons.insert_chart_outlined_rounded,
                    ),
                    AppSegment<_ReportsTab>(
                      value: _ReportsTab.activity,
                      label: 'Actividad de usuarios',
                      icon: Icons.manage_search_rounded,
                    ),
                  ],
                ),
                if (_tab == _ReportsTab.reports)
                  OutlinedButton.icon(
                    onPressed: ctrl.isLoading ? null : () => ctrl.ensureLoaded(force: true),
                    icon: ctrl.isLoading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Actualizar datos'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (ctrl.errorMessage != null && _tab == _ReportsTab.reports) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.dangerBg,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline_rounded, size: 18, color: AppTheme.dangerText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No se pudieron cargar todos los datos. Revisa tu conexión y pulsa "Actualizar datos".',
                        style: AppTheme.bodyStyle(color: AppTheme.dangerText),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_tab == _ReportsTab.reports) const ReportCatalogTab() else const ActivityTab(),
          ],
        ),
      ),
    );
  }
}
