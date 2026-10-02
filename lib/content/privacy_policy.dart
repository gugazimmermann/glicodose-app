import 'package:url_launcher/url_launcher.dart';

const privacyPolicyUrl = 'https://glicodose.app/privacidade';

Future<void> openPrivacyPolicy() async {
  final uri = Uri.parse(privacyPolicyUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
