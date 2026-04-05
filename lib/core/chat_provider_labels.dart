/// Display names for backend provider ids (`slack`, `google_gmail`, etc.).
String providerDisplayName(String providerId) {
  if (providerId == 'slack') return 'Slack';
  if (providerId.contains('gmail')) return 'Gmail';
  if (providerId.contains('calendar')) return 'Google Calendar';
  return providerId;
}

/// Short system line, e.g. "Slack connection required".
String connectionRequiredCaption(List<String> providerIds) {
  if (providerIds.isEmpty) return 'Connection required';
  final names = providerIds.map(providerDisplayName).toList();
  if (names.length == 1) {
    return '${names.first} connection required';
  }
  if (names.length == 2) {
    return '${names[0]} and ${names[1]} connection required';
  }
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last} connection required';
}

String successfullyConnectedCaption(String providerId) {
  return 'Successfully connected to ${providerDisplayName(providerId)}';
}
