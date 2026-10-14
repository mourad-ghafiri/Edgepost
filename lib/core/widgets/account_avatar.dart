import 'package:flutter/material.dart';

import '../accounts/account.dart';
import '../theme/tokens.dart';

/// What the small dot on an avatar says about *other* accounts.
enum AvatarDot {
  none,

  /// Another account has something that needs the user (red pencil).
  needsYou,

  /// Another account has unread mail (tint).
  unread,
}

/// An account's initials on its identity colour. The colour identifies the
/// account and never carries a state; a [dot] can.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.account, this.size = 30, this.dot = AvatarDot.none});

  final Account account;
  final double size;
  final AvatarDot dot;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    // Initials scale with the disc, not with the text size setting: the disc
    // is a fixed-size control and the name is spoken.
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.account(account.colorIndex), shape: BoxShape.circle),
      child: Text(
        account.initials,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          color: c.onAccount,
          fontSize: size * (account.initials.length > 1 ? 0.4 : 0.46),
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          height: 1,
        ),
      ),
    );
    if (dot == AvatarDot.none) return disc;
    final dotSize = (size * 0.32).clamp(8.0, 12.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          disc,
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: dot == AvatarDot.needsYou ? c.attention : c.tint,
                shape: BoxShape.circle,
                // A ring in the ground colour keeps the dot legible on the disc.
                border: Border.all(color: c.canvas, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
