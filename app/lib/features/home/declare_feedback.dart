import 'package:flutter/material.dart';

import '../../shared/haptics.dart';

/// Feedback for a declaration that failed.
///
/// The declaration is the same request whether it starts from the home button or
/// from a tapped suggestion, so both read and feel the same. A caller that owns
/// a control still shakes it itself; this only covers the haptic and the message.
void showDeclareFailure(BuildContext context) {
  AppHaptics.error();
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('宣言できなかった。もう一度試してね')),
  );
}
