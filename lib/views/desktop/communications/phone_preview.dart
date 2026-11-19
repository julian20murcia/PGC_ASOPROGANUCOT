import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

/// Simulación de cómo verá el productor el comunicado en su celular:
/// la notificación en la pantalla bloqueada y la tarjeta dentro de la app.
class PhonePreview extends StatelessWidget {
  const PhonePreview({
    super.key,
    required this.title,
    required this.message,
    required this.general,
    this.recipientName,
  });

  final String title;
  final String message;
  final bool general;
  final String? recipientName;

  @override
  Widget build(BuildContext context) {
    final String t = title.trim().isEmpty ? 'Título del comunicado' : title.trim();
    final String m = message.trim().isEmpty ? 'Aquí aparecerá el mensaje que escribas.' : message.trim();
    // Los avisos dirigidos llegan como notificación genérica por privacidad;
    // el contenido completo solo se ve dentro de la app.
    final String pushTitle = general ? t : AppConstants.appName;
    final String pushBody = general ? m : 'Tienes un nuevo aviso. Consúltalo en la aplicación.';

    return Center(
      child: Container(
        width: 270,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.brandInk,
          borderRadius: BorderRadius.circular(34),
          boxShadow: AppTheme.shadowMd,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: Container(
            color: AppTheme.brandDeep,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('9:41', style: AppTheme.monoStyle(fontSize: 11, color: AppTheme.surface)),
                    const Spacer(),
                    const Icon(Icons.signal_cellular_alt_rounded, size: 12, color: AppTheme.surface),
                    const SizedBox(width: 3),
                    const Icon(Icons.battery_full_rounded, size: 12, color: AppTheme.surface),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Notificación',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyStyle(fontSize: 11, color: AppTheme.brandMuted),
                ),
                const SizedBox(height: 6),
                _PushCard(title: pushTitle, body: pushBody),
                const SizedBox(height: 14),
                Text(
                  'Dentro de la app',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyStyle(fontSize: 11, color: AppTheme.brandMuted),
                ),
                const SizedBox(height: 6),
                _InAppCard(title: t, message: m, general: general, recipientName: recipientName),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PushCard extends StatelessWidget {
  const _PushCard({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: AppTheme.brand, borderRadius: BorderRadius.circular(7)),
            child: const Icon(Icons.water_drop_rounded, size: 15, color: AppTheme.surface),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        AppConstants.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyStyle(fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ),
                    Text('ahora', style: AppTheme.bodyStyle(fontSize: 10, color: AppTheme.textMuted)),
                  ],
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
                ),
                Text(
                  body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InAppCard extends StatelessWidget {
  const _InAppCard({required this.title, required this.message, required this.general, this.recipientName});
  final String title;
  final String message;
  final bool general;
  final String? recipientName;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 230),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.campaign_rounded, size: 15, color: AppTheme.accentDeep),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    general ? 'Comunicado general' : 'Aviso para ${recipientName ?? 'ti'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyStyle(fontSize: 10.5, color: AppTheme.accentDeep, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: AppTheme.bodyStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(message, style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
