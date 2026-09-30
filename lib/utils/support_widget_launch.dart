/// URI set on the locked home-screen widget. The `homeWidget` query is what
/// the iOS home_widget plugin uses to recognize a widget tap.
const supportWidgetLaunchUri = 'glicodose://support?homeWidget';

bool isSupportWidgetLaunch(Uri? uri) {
  if (uri == null) return false;
  return uri.scheme == 'glicodose' && uri.host == 'support';
}
