import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_legal.dart';
import '../../../../core/constants/app_tokens.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Rechtliches')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          Text(
            'Datenschutz, Impressum und Open-Source-Lizenzen liegen hier gebündelt an einem Ort.',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.lg),
          _LegalCard(
            title: 'Impressum',
            subtitle: 'Angaben nach · 5 DDG und Kontakt zur App',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _LegalFact(label: 'Angebot', value: AppLegal.appName),
                _LegalFact(
                  label: 'Betreiber',
                  value: AppLegal.valueOrMissing(AppLegal.operatorName),
                ),
                _LegalFact(
                  label: 'Verantwortliche Person',
                  value: AppLegal.valueOrMissing(AppLegal.managingDirector),
                ),
                _LegalFact(
                  label: 'Postanschrift',
                  value: AppLegal.valueOrMissing(AppLegal.postalAddress),
                ),
                _LegalFact(
                  label: 'E-Mail',
                  value: AppLegal.valueOrMissing(AppLegal.contactEmail),
                ),
                _LegalFact(
                  label: 'Telefon',
                  value: AppLegal.valueOrMissing(AppLegal.phone),
                ),
                _LegalFact(
                  label: 'Website',
                  value: AppLegal.valueOrMissing(AppLegal.websiteUrl),
                ),
                _LegalFact(
                  label: 'USt-ID',
                  value: AppLegal.valueOrMissing(AppLegal.vatId),
                ),
                _LegalFact(
                  label: 'Registergericht',
                  value: AppLegal.valueOrMissing(AppLegal.registerCourt),
                ),
                _LegalFact(
                  label: 'Registernummer',
                  value: AppLegal.valueOrMissing(AppLegal.registerNumber),
                ),
                if (!AppLegal.hasCompleteImpressum) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4F6),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFFFD6DE)),
                    ),
                    child: Text(
                      'Vor dem produktiven Livegang müssen hier die echten Betreiber- und Kontaktdaten hinterlegt werden. Es wurden bewusst keine Fantasiedaten eingesetzt.',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ),
                ],
                if (AppLegal.websiteUrl.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _openUrl(context, AppLegal.websiteUrl),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Website öffnen'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _LegalCard(
            title: 'Datenschutz',
            subtitle: 'Welche Daten sparGO verarbeitet und warum',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _LegalParagraph(
                  text:
                      'sparGO verarbeitet Konto-, Profil-, Favoriten-, Wallet-, Bewertungs-, Story- und Businessdaten, damit Anmeldung, personalisierte Gutscheine, Einlösungen, Bewertungen und Business-Funktionen sauber funktionieren.',
                ),
                const SizedBox(height: AppSpacing.sm),
                _LegalParagraph(
                  text:
                      'Standortdaten werden nur nach ausdrücklicher Freigabe verwendet. Wenn du Stadt oder Umkreis manuell Änderst, nutzt sparGO diese Angaben statt einer automatischen Standortabfrage.',
                ),
                const SizedBox(height: AppSpacing.sm),
                _LegalParagraph(
                  text:
                      'Öffentliche Coupons stammen aus frei sichtbaren Quellen, werden als Drittquelle markiert und regelmäßig neu geprüft, bevor sie erneut im Flow erscheinen.',
                ),
                const SizedBox(height: AppSpacing.sm),
                _LegalParagraph(
                  text:
                      'Technisch nutzt sparGO Firebase Authentication, Cloud Firestore, Cloud Storage, Cloud Functions sowie Google Maps Platform für Karten-, Geocoding- und Places-Daten.',
                ),
                const SizedBox(height: AppSpacing.sm),
                _LegalFact(
                  label: 'Stand Datenschutzhinweise',
                  value: AppLegal.privacyLastUpdated,
                ),
                _LegalFact(
                  label: 'Kontakt Datenschutz',
                  value: AppLegal.valueOrMissing(
                    AppLegal.privacyEmail.isEmpty
                        ? AppLegal.contactEmail
                        : AppLegal.privacyEmail,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _LegalCard(
            title: 'Nutzung & Quellen',
            subtitle: 'Hinweise zu Gutscheinen und Drittquellen',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const <Widget>[
                _LegalParagraph(
                  text:
                      'Direkte Gutscheine aus sparGO und öffentliche Drittquellen werden im selben Produktfluss dargestellt, Drittquellen aber klar gekennzeichnet.',
                ),
                SizedBox(height: AppSpacing.sm),
                _LegalParagraph(
                  text:
                      'Die tatsächliche Einlösbarkeit, Laufzeit und Verfügbarkeit eines öffentlichen Angebots richtet sich immer nach dem jeweiligen Unternehmen oder der extern veröffentlichten Quelle.',
                ),
                SizedBox(height: AppSpacing.sm),
                _LegalParagraph(
                  text:
                      'Business-Konten sollen nur von Personen verwendet werden, die zum Unternehmen gehören. Die App verknüpft deshalb Registrierungen mit Website-Domain und Verifizierungs-E-Mail.',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _LegalCard(
            title: 'Open Source',
            subtitle: 'Bibliotheken und Lizenzen',
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  showLicensePage(
                    context: context,
                    applicationName: AppLegal.appName,
                  );
                },
                icon: const Icon(Icons.menu_book_rounded),
                label: const Text('Open-Source-Lizenzen öffnen'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String rawValue) async {
    final uri = Uri.tryParse(rawValue.trim());
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link ist gerade nicht gültig.')),
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link konnte gerade nicht geöffnet werden.'),
        ),
      );
    }
  }
}

class _LegalCard extends StatelessWidget {
  const _LegalCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFFD6DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _LegalFact extends StatelessWidget {
  const _LegalFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _LegalParagraph extends StatelessWidget {
  const _LegalParagraph({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
    );
  }
}
