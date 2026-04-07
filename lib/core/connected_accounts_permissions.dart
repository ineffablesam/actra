/// Human-readable OAuth scope descriptions aligned with [ConnectedAccountsService]
/// connect payloads (same strings sent to Auth0 — keep in sync when scopes change).
class ProviderPermissionBullet {
  const ProviderPermissionBullet({
    required this.scope,
    required this.title,
    required this.description,
  });

  final String scope;
  final String title;
  final String description;
}

/// Scopes and copy for each linkable provider id (backend `providers` strings).
abstract final class ConnectedAccountsPermissions {
  static List<String> scopesForProvider(String provider) {
    if (provider == 'slack') {
      return const [
        'channels:read',
        'channels:history',
        'users:read',
        'team:read',
      ];
    }
    if (provider == 'github') {
      // Auth0 requires at least one scope (A0E-400-0003 if empty). Match your GitHub OAuth App.
      return const [
        'read:user',
        'repo',
      ];
    }
    if (provider.contains('calendar')) {
      return const [
        'openid',
        'profile',
        'https://www.googleapis.com/auth/calendar.readonly',
        'https://www.googleapis.com/auth/calendar.events',
      ];
    }
    return const [
      'openid',
      'profile',
      'https://www.googleapis.com/auth/gmail.send',
      'https://www.googleapis.com/auth/gmail.readonly',
    ];
  }

  static List<ProviderPermissionBullet> bulletsForProvider(String provider) {
    return scopesForProvider(provider).map(_bulletForScope).toList();
  }

  static ProviderPermissionBullet _bulletForScope(String scope) {
    switch (scope) {
      case 'channels:read':
        return const ProviderPermissionBullet(
          scope: 'channels:read',
          title: 'View channels',
          description: 'See public channels in your workspace so Actra can target the right place.',
        );
      case 'channels:history':
        return const ProviderPermissionBullet(
          scope: 'channels:history',
          title: 'Read messages',
          description: 'Read channel history when you ask Actra to summarize or search Slack.',
        );
      case 'users:read':
        return const ProviderPermissionBullet(
          scope: 'users:read',
          title: 'View people',
          description: 'Resolve mentions and basic user info for Slack actions.',
        );
      case 'team:read':
        return const ProviderPermissionBullet(
          scope: 'team:read',
          title: 'Workspace info',
          description: 'Identify your workspace for Token Vault and API calls.',
        );
      case 'openid':
        return const ProviderPermissionBullet(
          scope: 'openid',
          title: 'OpenID',
          description: 'Verify your identity with Google for OAuth.',
        );
      case 'profile':
        return const ProviderPermissionBullet(
          scope: 'profile',
          title: 'Profile',
          description: 'Basic profile details required for the Google connection.',
        );
      case 'https://www.googleapis.com/auth/calendar.readonly':
        return const ProviderPermissionBullet(
          scope: 'https://www.googleapis.com/auth/calendar.readonly',
          title: 'Read calendar',
          description: 'View your calendars and events when you ask Actra about your schedule.',
        );
      case 'https://www.googleapis.com/auth/calendar.events':
        return const ProviderPermissionBullet(
          scope: 'https://www.googleapis.com/auth/calendar.events',
          title: 'Manage events',
          description: 'Create or update events when you ask Actra to schedule something.',
        );
      case 'https://www.googleapis.com/auth/gmail.send':
        return const ProviderPermissionBullet(
          scope: 'https://www.googleapis.com/auth/gmail.send',
          title: 'Send email',
          description: 'Send messages on your behalf when you confirm drafts in Actra.',
        );
      case 'https://www.googleapis.com/auth/gmail.readonly':
        return const ProviderPermissionBullet(
          scope: 'https://www.googleapis.com/auth/gmail.readonly',
          title: 'Read email',
          description: 'Read threads and metadata to draft replies or summarize mail.',
        );
      case 'read:user':
        return const ProviderPermissionBullet(
          scope: 'read:user',
          title: 'Profile',
          description: 'Identify your GitHub user for Token Vault and API calls.',
        );
      case 'repo':
        return const ProviderPermissionBullet(
          scope: 'repo',
          title: 'Repositories',
          description:
              'Read and write repository contents, issues, and pull requests Actra needs for your requests.',
        );
      default:
        return ProviderPermissionBullet(
          scope: scope,
          title: scope,
          description: 'Requested for this integration via Auth0 Connected Accounts.',
        );
    }
  }
}
