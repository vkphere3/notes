// lib/app/ui.dart
import 'package:flutter/material.dart';

class Gaps {
  static const h4 = SizedBox(height: 4);
  static const h6 = SizedBox(height: 6);
  static const h8 = SizedBox(height: 8);
  static const h12 = SizedBox(height: 12);
  static const h16 = SizedBox(height: 16);
  static const h20 = SizedBox(height: 20);
  static const h24 = SizedBox(height: 24);
  static const h32 = SizedBox(height: 32);

  static const w4 = SizedBox(width: 4);
  static const w6 = SizedBox(width: 6);
  static const w8 = SizedBox(width: 8);
  static const w12 = SizedBox(width: 12);
  static const w16 = SizedBox(width: 16);
}

class Radii {
  static const small = 12.0;
  static const medium = 16.0;
  static const large = 20.0;
  static const xl = 28.0;
}

class Times {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 300);
}

extension SnackX on BuildContext {
  void showSnack(String text, {SnackBarAction? action, EdgeInsets? margin}) {
    final messenger = ScaffoldMessenger.of(this);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        behavior: SnackBarBehavior.floating,
        margin: margin ?? const EdgeInsets.fromLTRB(12, 0, 12, 80),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
