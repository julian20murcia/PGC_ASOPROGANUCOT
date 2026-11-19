import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../core/theme/app_theme.dart';
import 'mobile_kit.dart';

/// Llaves de los elementos que resalta el recorrido de bienvenida.
class ProducerTourKeys {
  final GlobalKey carousel = GlobalKey(debugLabel: 'tour-carousel');
  final GlobalKey chart = GlobalKey(debugLabel: 'tour-chart');
  final GlobalKey navHome = GlobalKey(debugLabel: 'tour-nav-home');
  final GlobalKey navDeliveries = GlobalKey(debugLabel: 'tour-nav-deliveries');
  final GlobalKey navSettlements = GlobalKey(debugLabel: 'tour-nav-settlements');
  final GlobalKey navNotices = GlobalKey(debugLabel: 'tour-nav-notices');
  final GlobalKey profile = GlobalKey(debugLabel: 'tour-profile');

  List<GlobalKey> get navKeys => <GlobalKey>[navHome, navDeliveries, navSettlements, navNotices];
}

class _Step {
  const _Step(this.key, this.title, this.text, this.align, {this.circle = false});
  final GlobalKey key;
  final String title;
  final String text;
  final ContentAlign align;
  final bool circle;
}

/// Construye el recorrido (solo con los elementos que ya están en pantalla).
TutorialCoachMark buildProducerTour({
  required ProducerTourKeys keys,
  required VoidCallback onDone,
}) {
  final List<_Step> steps = <_Step>[
    _Step(
      keys.carousel,
      'Tu quincena de un vistazo',
      'Aquí ves cuánta leche entregaste en la quincena y cuánto vas a recibir. Las tarjetas se mueven solas; también puedes deslizarlas.',
      ContentAlign.bottom,
    ),
    _Step(
      keys.chart,
      'Tu producción día a día',
      'Cada barra es un día: la parte verde es lo de la mañana y la ámbar lo de la tarde.',
      ContentAlign.top,
    ),
    _Step(
      keys.navDeliveries,
      'Mis entregas',
      'Un calendario con lo que te registraron cada mañana y cada tarde. Toca un día para ver el detalle.',
      ContentAlign.top,
      circle: true,
    ),
    _Step(
      keys.navSettlements,
      'Liquidaciones',
      'Tus quincenas cerradas, con el desprendible de pago para verlo y descargarlo.',
      ContentAlign.top,
      circle: true,
    ),
    _Step(
      keys.navNotices,
      'Avisos',
      'Aquí llegan los avisos de la asociación: entregas, pagos y comunicados.',
      ContentAlign.top,
      circle: true,
    ),
    _Step(
      keys.profile,
      'Tu perfil',
      'Tus datos y los de tu finca. Desde aquí puedes volver a ver este recorrido cuando quieras.',
      ContentAlign.top,
      circle: true,
    ),
  ].where((_Step s) => s.key.currentContext != null).toList();

  final int total = steps.length;
  final List<TargetFocus> targets = <TargetFocus>[
    for (int i = 0; i < steps.length; i++)
      TargetFocus(
        identify: 'tour-$i',
        keyTarget: steps[i].key,
        shape: steps[i].circle ? ShapeLightFocus.Circle : ShapeLightFocus.RRect,
        radius: 18,
        enableOverlayTab: true,
        contents: <TargetContent>[
          TargetContent(
            align: steps[i].align,
            builder: (BuildContext context, TutorialCoachMarkController c) => _TourCard(
              index: i,
              total: total,
              title: steps[i].title,
              text: steps[i].text,
              onNext: c.next,
            ),
          ),
        ],
      ),
  ];

  bool closed = false;
  void close() {
    if (closed) return;
    closed = true;
    onDone();
  }

  return TutorialCoachMark(
    targets: targets,
    colorShadow: AppTheme.brandInk,
    opacityShadow: 0.86,
    paddingFocus: 6,
    pulseEnable: false,
    alignSkip: Alignment.topRight,
    skipWidget: Container(
      key: const ValueKey<String>('tour-skip'),
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: Text('Saltar', style: MobileTokens.body(size: 14.5, color: Colors.white, weight: FontWeight.w700)),
    ),
    onFinish: close,
    onSkip: () {
      close();
      return true;
    },
  );
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.index,
    required this.total,
    required this.title,
    required this.text,
    required this.onNext,
  });

  final int index;
  final int total;
  final String title;
  final String text;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final bool last = index == total - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: MobileTokens.cardShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (int i = 0; i < total; i++)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  width: i == index ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == index ? AppTheme.brand : AppTheme.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              const Spacer(),
              Text('${index + 1} de $total', style: MobileTokens.label()),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: MobileTokens.title(size: 17)),
          const SizedBox(height: 6),
          Text(text, style: MobileTokens.body(size: 14.5, height: 1.45)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey<String>('tour-next'),
              onPressed: onNext,
              child: Text(last ? '¡Listo!' : 'Siguiente'),
            ),
          ),
        ],
      ),
    );
  }
}
