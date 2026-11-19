import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../controllers/producer_portal_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/input_rules.dart';
import '../../../models/privacy_notice.dart';
import '../../../models/producer_model.dart';
import '../../../models/user_model.dart';
import '../../shared/widgets/privacy_notice_view.dart';
import 'home_tab.dart' show initialsOf;
import 'mobile_kit.dart';

/// Pestaña "Perfil": datos del asociado, finca, Habeas Data y sesión.
class ProfileTab extends StatelessWidget {
  const ProfileTab({
    super.key,
    required this.portal,
    required this.user,
    required this.onReplayTour,
    required this.onSignOut,
  });

  final ProducerPortalController portal;
  final UserModel user;
  final VoidCallback onReplayTour;
  final Future<void> Function() onSignOut;

  Future<void> _confirmSignOut(BuildContext context) async {
    final bool ok = await showMobileConfirm(
      context,
      title: '¿Cerrar sesión?',
      message: 'Tendrás que volver a ingresar con tu usuario y contraseña.',
      confirmLabel: 'Cerrar sesión',
      icon: Icons.logout_rounded,
      destructive: true,
    );
    if (ok) await onSignOut();
  }

  void _showPrivacy(BuildContext context, ProducerModel? producer) {
    showMobileSheet<void>(
      context,
      builder: (BuildContext ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Tratamiento de datos personales', style: MobileTokens.title(size: 18)),
            const SizedBox(height: 12),
            FutureBuilder<PrivacyNotice>(
              future: PrivacyNotice.load(),
              builder: (BuildContext context, AsyncSnapshot<PrivacyNotice> snap) {
                if (snap.hasData) return PrivacyNoticeView(notice: snap.data!);
                if (snap.hasError) {
                  final Map<String, dynamic>? saved = producer?.avisoPrivacidad;
                  if (saved != null) return PrivacyNoticeView(notice: PrivacyNotice.fromMap(saved));
                  return Text(
                    'No se pudo cargar el aviso. Puedes solicitar una copia en la sede de la asociación.',
                    style: MobileTokens.body(),
                  );
                }
                return const LinearProgressIndicator();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ProducerModel? p = portal.activeProducer;
    final String name = p?.nombreCompleto ?? user.nombreCompleto;
    final double top = MediaQuery.paddingOf(context).top;

    return ListView(
      key: const PageStorageKey<String>('profile-list'),
      padding: EdgeInsets.zero,
      children: <Widget>[
        Container(
          decoration: const BoxDecoration(
            gradient: MobileTokens.headerGradient,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(20, top + 22, 20, 24),
          child: Column(
            children: <Widget>[
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.75), width: 3),
                ),
                child: Text(initialsOf(name), style: MobileTokens.display(size: 26, color: AppTheme.brandInk)),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: MobileTokens.title(size: 20, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: <Widget>[
                  if (p != null) TonePill('Asociado ${p.codigoAsociado}', onDark: true, icon: Icons.badge_rounded),
                  TonePill(
                    p == null ? 'Sin ficha vinculada' : (p.isActivo ? 'Activo' : 'Inactivo'),
                    onDark: true,
                    icon: p != null && p.isActivo ? Icons.verified_rounded : Icons.info_outline_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(MobileTokens.gutter, 18, MobileTokens.gutter, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SectionHeader(title: 'Datos personales'),
              SoftCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: <Widget>[
                    InfoRow(icon: Icons.credit_card_rounded, label: 'Documento', value: p?.cedula ?? user.documento, mono: true),
                    InfoRow(icon: Icons.phone_rounded, label: 'Teléfono', value: p?.telefono ?? user.telefono, mono: true),
                    // Las cuentas del alta digital usan un correo interno (*.invalid) que no se muestra.
                    if (user.correo.isNotEmpty && !user.correo.endsWith('.invalid'))
                      InfoRow(icon: Icons.alternate_email_rounded, label: 'Correo', value: user.correo),
                  ],
                ),
              ),
              if (p != null) ...<Widget>[
                const SizedBox(height: 18),
                const SectionHeader(title: 'Mi finca'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(
                    children: <Widget>[
                      InfoRow(icon: Icons.agriculture_rounded, label: 'Finca / predio', value: p.nombreFinca),
                      InfoRow(icon: Icons.place_rounded, label: 'Vereda', value: '${p.vereda}, Susa'),
                      InfoRow(icon: Icons.tag_rounded, label: 'Código asociado', value: p.codigoAsociado, mono: true),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const SectionHeader(title: 'Privacidad y datos'),
              SoftCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    _ActionTile(
                      icon: Icons.shield_rounded,
                      title: 'Habeas Data',
                      subtitle: p != null && p.hasValidHabeasData && p.fechaAutorizacionDatos != null
                          ? 'Autorizado el ${AppFormatters.formatDate(p.fechaAutorizacionDatos!)}'
                          : 'Consulta el soporte con la asociación',
                      onTap: () => _showPrivacy(context, p),
                    ),
                    const Divider(height: 1, indent: 64, color: AppTheme.dividerLight),
                    _ActionTile(
                      key: const ValueKey<String>('profile-rectification'),
                      icon: Icons.edit_note_rounded,
                      title: 'Solicitar corrección de datos',
                      subtitle: 'Ley 1581 de 2012 · lo revisa el Administrador',
                      enabled: p != null,
                      onTap: () => showMobileSheet<void>(
                        context,
                        builder: (_) => RectificationSheet(portal: portal, user: user),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const SectionHeader(title: 'Ayuda'),
              SoftCard(
                padding: EdgeInsets.zero,
                child: _ActionTile(
                  key: const ValueKey<String>('profile-replay-tour'),
                  icon: Icons.tour_rounded,
                  title: 'Ver recorrido de nuevo',
                  subtitle: 'Te mostramos cómo usar la app',
                  onTap: onReplayTour,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const ValueKey<String>('profile-logout'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.dangerBg, width: 1.5),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => _confirmSignOut(context),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Cerrar sesión'),
              ),
              const SizedBox(height: 16),
              Text(
                'ASOPROGANUCOTT · Portal del productor',
                textAlign: TextAlign.center,
                style: MobileTokens.body(size: 13, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              IconChip(icon, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: MobileTokens.body(size: 15, color: AppTheme.textPrimary, weight: FontWeight.w700)),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Campos rectificables con su formateador y validador.
class RectificationField {
  const RectificationField(this.label, this.formatters, this.validator, {this.keyboard = TextInputType.text});

  final String label;
  final List<TextInputFormatter> Function() formatters;
  final String? Function(String?) validator;
  final TextInputType keyboard;

  static final List<RectificationField> all = <RectificationField>[
    RectificationField(
      'Teléfono de contacto',
      AppInputs.phone,
      (String? v) => AppValidators.phone(v),
      keyboard: TextInputType.phone,
    ),
    RectificationField(
      'Nombre de finca / predio',
      () => AppInputs.text(max: FieldLimits.farmName),
      (String? v) => AppValidators.text(v, label: 'El nombre de la finca', max: FieldLimits.farmName),
    ),
    RectificationField(
      'Vereda',
      () => AppInputs.text(max: FieldLimits.vereda),
      (String? v) => AppValidators.text(v, label: 'La vereda', max: FieldLimits.vereda),
    ),
    RectificationField(
      'Nombres o apellidos',
      () => AppInputs.personName(max: FieldLimits.fullName),
      (String? v) => AppValidators.text(v, label: 'El nombre', max: FieldLimits.fullName),
      keyboard: TextInputType.name,
    ),
    RectificationField(
      'Otro dato personal',
      () => AppInputs.text(),
      (String? v) => AppValidators.text(v, label: 'El dato', min: 3),
    ),
  ];
}

/// Formulario de solicitud de rectificación (Ley 1581 de 2012).
class RectificationSheet extends StatefulWidget {
  const RectificationSheet({super.key, required this.portal, required this.user});

  final ProducerPortalController portal;
  final UserModel user;

  @override
  State<RectificationSheet> createState() => _RectificationSheetState();
}

class _RectificationSheetState extends State<RectificationSheet> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _comment = TextEditingController();
  int _field = 0;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final String comment = _comment.text.trim();
    final bool ok = await widget.portal.submitRectificationRequest(
      actor: widget.user,
      campo: RectificationField.all[_field].label,
      detalle: 'Dato correcto: ${_value.text.trim()}${comment.isEmpty ? '' : ' · Comentario: $comment'}',
    );
    if (!mounted) return;
    if (ok) {
      final ScaffoldMessengerState? m = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      m?.showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.brandDeep,
          content: Text(widget.portal.feedbackMessage ?? 'Solicitud enviada al Administrador.'),
        ),
      );
    } else {
      setState(() {
        _sending = false;
        _error = widget.portal.errorMessage ?? 'No se pudo enviar la solicitud.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final RectificationField f = RectificationField.all[_field];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Corregir mis datos', style: MobileTokens.title(size: 19)),
              const SizedBox(height: 4),
              Text(
                'Tu solicitud llega al Administrador, quien la revisa y actualiza tu ficha (Ley 1581 de 2012).',
                style: MobileTokens.body(size: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              Text('¿Qué dato está mal?', style: MobileTokens.label(color: AppTheme.textSecondary, size: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (int i = 0; i < RectificationField.all.length; i++)
                    ChoiceChip(
                      label: Text(RectificationField.all[i].label),
                      labelStyle: MobileTokens.body(
                        size: 14,
                        color: i == _field ? Colors.white : AppTheme.textPrimary,
                        weight: FontWeight.w600,
                      ),
                      selected: i == _field,
                      showCheckmark: false,
                      selectedColor: AppTheme.brand,
                      backgroundColor: AppTheme.surfaceMuted,
                      side: BorderSide(color: i == _field ? AppTheme.brand : AppTheme.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
                      onSelected: (_) => setState(() {
                        _field = i;
                        _value.clear();
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: ValueKey<String>('rect-value-$_field'),
                controller: _value,
                inputFormatters: f.formatters(),
                keyboardType: f.keyboard,
                validator: f.validator,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                style: MobileTokens.body(size: 15, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Dato correcto',
                  hintText: f.label == 'Teléfono de contacto' ? 'Ej. 3101234567' : 'Escribe el dato como debe quedar',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('rect-comment'),
                controller: _comment,
                maxLines: 3,
                inputFormatters: AppInputs.multiline(max: 300),
                validator: (String? v) => AppValidators.text(v, label: 'El comentario', min: 5, max: 300, required: false),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                style: MobileTokens.body(size: 15, color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Comentario (opcional)',
                  hintText: 'Cuéntanos algo más si lo necesitas',
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                ErrorBanner(message: _error!),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey<String>('rect-submit'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _sending ? null : _submit,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: const Text('Enviar solicitud'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
