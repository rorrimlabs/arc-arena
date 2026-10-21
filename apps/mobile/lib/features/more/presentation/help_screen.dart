import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// How the floor works (design: More → Help). Short, practical answers to the
/// questions a new staff member actually asks on their first shift.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const String path = '/help';

  static const _topics = <({String q, String a})>[
    (
      q: 'The card is the alert',
      a: 'A station card turns amber a few minutes before its time is up and '
          'red once it runs over. Nothing else needs watching — if every card '
          'is dark, the floor is comfortable.',
    ),
    (
      q: 'Starting someone quickly',
      a: 'Tap Start on a free station, then "Walk-in — start without details". '
          'No name or phone is needed; the session is still timed and billed '
          'like any other. Register them later if they come back.',
    ),
    (
      q: 'Moving someone to another system',
      a: 'Open the card’s ••• menu and choose Change system. Their clock '
          'keeps running from when they first started — moving never buys or '
          'loses time, and both stations show up on the bill.',
    ),
    (
      q: 'Changing the game or controllers mid-session',
      a: 'Also under •••. Each change starts a new stretch, priced at the rate '
          'for that configuration, so two controllers for half an hour then '
          'three for half an hour bills exactly that.',
    ),
    (
      q: 'Taking money before the end',
      a: '••• → Record payment. Part-payments are fine, and so is splitting '
          'across UPI and cash — each one is its own entry and they add up. '
          'The balance shows on the bill.',
    ),
    (
      q: 'A session ended but they have not paid',
      a: 'It moves to "Awaiting payment" at the bottom of the Floor. The '
          'station is free again; the money is still owed and tracked there '
          'until it is collected.',
    ),
    (
      q: 'Time-based prices',
      a: 'Discounts or surcharges for certain days and times are set by the '
          'owner and apply automatically. The one in force when a session '
          'starts is shown on the estimate and covers the whole session, even '
          'past the end of its window. Nothing to select.',
    ),
    (
      q: 'A game will not run on a station',
      a: 'Tap the controller icon on a free station, find the game and set its '
          'status for that station with a note. It stays playable everywhere '
          'else.',
    ),
    (
      q: 'If the internet drops',
      a: 'Nothing changes. Everything is saved on this device as it happens, '
          'and the timers are worked out from the stored start times — so a '
          'restart, a flat battery or a dead connection loses nothing.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          for (final t in _topics)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: arena.surface,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: arena.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.q, style: ArenaType.h3.copyWith(color: arena.text)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    t.a,
                    style: ArenaType.body
                        .copyWith(color: arena.textMuted, height: 1.45),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
