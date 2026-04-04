import 'dart:async';

import 'package:actra/core/env.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [startUrl] in the **system browser** (Safari / Chrome). Google OAuth rejects
/// embedded WebViews (`403 disallowed_useragent`); this flow satisfies their policy.
///
/// Waits until the app receives `com.actra.app://connected-accounts-callback?...`
/// from the redirect (via [AppLinks]).
Future<String?> openExternalBrowserAndAwaitConnectedAccountsCallback(
  String startUrl,
) async {
  final appLinks = AppLinks();

  bool isCallback(Uri uri) =>
      uri.scheme == Env.auth0Scheme && uri.host == 'connected-accounts-callback';

  final completer = Completer<String?>();
  final sub = appLinks.uriLinkStream.listen((uri) {
    if (isCallback(uri) && !completer.isCompleted) {
      completer.complete(uri.toString());
    }
  });

  try {
    final uri = Uri.parse(startUrl);
    if (!await canLaunchUrl(uri)) {
      debugPrint('[ConnectedAccounts] canLaunchUrl false for $startUrl');
      return null;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      debugPrint('[ConnectedAccounts] launchUrl returned false');
      return null;
    }

    return await Future.any<String?>([
      completer.future,
      Future<String?>.delayed(const Duration(minutes: 5), () => null),
    ]);
  } finally {
    await sub.cancel();
  }
}
