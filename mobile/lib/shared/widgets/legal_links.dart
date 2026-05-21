import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../legal_urls.dart';
import '../theme.dart';

Future<void> openLegalUrl(String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception('Could not open $url');
  }
}

/// Privacy + Terms links for login and profile screens.
class LegalLinksRow extends StatelessWidget {
  const LegalLinksRow({super.key, this.center = true});

  final bool center;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      color: BytzGoTheme.sheetMuted,
      decoration: TextDecoration.underline,
    );
    final base = TextStyle(fontSize: 11, color: BytzGoTheme.sheetMuted);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'By signing in you agree to our '),
          TextSpan(
            text: 'Terms',
            style: style,
            recognizer: TapGestureRecognizer()
              ..onTap = () => openLegalUrl(LegalUrls.terms),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: style,
            recognizer: TapGestureRecognizer()
              ..onTap = () => openLegalUrl(LegalUrls.privacy),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: center ? TextAlign.center : TextAlign.start,
    );
  }
}

class ProfileLegalSection extends StatelessWidget {
  const ProfileLegalSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _linkTile(
          context,
          Icons.description_outlined,
          'Privacy Policy',
          LegalUrls.privacy,
        ),
        const SizedBox(height: 8),
        _linkTile(
          context,
          Icons.gavel_outlined,
          'Terms of Service',
          LegalUrls.terms,
        ),
      ],
    );
  }

  Widget _linkTile(
    BuildContext context,
    IconData icon,
    String label,
    String url,
  ) {
    return Material(
      color: BytzGoTheme.sheetDivider.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () async {
          try {
            await openLegalUrl(url);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(e.toString())),
              );
            }
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: BytzGoTheme.brandBlue),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: BytzGoTheme.sheetText,
                  ),
                ),
              ),
              const Icon(Icons.open_in_new, size: 18, color: BytzGoTheme.sheetMuted),
            ],
          ),
        ),
      ),
    );
  }
}
