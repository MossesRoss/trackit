/*
 * @author Mosses
 * @version 1.1.0
 * --- CHANGELOG ---
 * v1.1.0:
 * - [FEAT] Changed title to "Upgrade to Pro".
 * - [FEAT] Added "Upgrade Now" button linking to the donation/drive page.
 * - [FEAT] Moved manual UPI instructions into a collapsible ExpansionTile.
 * v1.0.0:
 * - [FEAT] Initial creation of the dedicated 'Upgrade to Pro' page.
 * - [FEAT] Page is theme-aware and pulls layout inspiration from Gemini Pro.
 * - [FEAT] Includes clear UPI payment instructions with copy-to-clipboard actions.
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:url_launcher/url_launcher.dart'; // For launching URLs

class UpgradePage extends StatefulWidget {
  const UpgradePage({super.key});

  @override
  State<UpgradePage> createState() => _UpgradePageState();
}

class _UpgradePageState extends State<UpgradePage> {
  // --- Helper method to launch URLs ---
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not launch $urlString'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // Use theme-aware colors
    final iconColor = theme.colorScheme.primary;
    final subtleTextColor = theme.textTheme.bodySmall?.color;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Upgrade to Pro"),
        // Make app bar theme-aware
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        foregroundColor: theme.textTheme.titleLarge?.color,
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon(
                //   Icons.auto_awesome_rounded,
                //   color: iconColor,
                //   size: 48,
                // ),
                const SizedBox(height: 16),
                // Text(
                //   "Upgrade to Pro 1",
                //   textAlign: TextAlign.center,
                //   style: theme.textTheme.headlineSmall
                //       ?.copyWith(fontWeight: FontWeight.bold),
                // ),
                const SizedBox(height: 8),
                // --- MOD: Subtitle changed ---
                Text(
                  "Unlock your full potential and achieve your goals 81% more effectively!",
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: subtleTextColor),
                ),
                const SizedBox(height: 32),

                // Re-using the benefits from your old dialog
                const _BenefitTile(
                  icon: Icons.palette_rounded,
                  title: "Full App Customization",
                  subtitle:
                      "Request any feature or layout change, just for you.",
                ),
                const _BenefitTile(
                  icon: Icons.auto_awesome_rounded,
                  title: "Powerful AI Features",
                  subtitle:
                      "Get AI-powered suggestions, planning, and insights.",
                ),
                const _BenefitTile(
                  icon: Icons.bar_chart_rounded,
                  title: "Advanced Data Visualization",
                  subtitle:
                      "See beautiful charts of your progress and habits.",
                ),
                const _BenefitTile(
                  icon: Icons.schedule_rounded,
                  title: "AI-Powered Goal Scheduling",
                  subtitle:
                      "Let AI build the perfect milestone plan for you.",
                ),
                const SizedBox(height: 32),

                // --- MOD: Added "Upgrade Now" button ---
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      _launchURL(
                          "https://drive.google.com/file/d/1b2s0u5msfpqn7finiw8Vx1ELgbWUrbW9/view?usp=sharing");
                    },
                    child: const Text("Upgrade Now (₹5555)"),
                  ),
                ),
                const SizedBox(height: 16),

                // --- MOD: Payment Instructions moved into a collapsible Card ---
                Card(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias, // Ensures ExpansionTile respects card's shape
                  color: isDarkMode
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                    side: BorderSide(color: theme.dividerColor),
                  ),
                  child: ExpansionTile(
                    title: const Text(
                      "How to Upgrade Manually?",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text("Tap to see UPI instructions"),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20.0).copyWith(top: 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            const _InstructionStep(
                              step: "1",
                              title: "Pay Amount",
                              value: "₹5555",
                              subtitle: "One-time payment for lifetime access.",
                            ),
                            const Divider(height: 32),
                            _InstructionStep(
                              step: "2",
                              title: "Send to UPI ID",
                              value: "whymosses@oksbi",
                              subtitle: "Tap value to copy ID.",
                              isCopyable: true,
                              scaffoldContext: context,
                            ),
                            const Divider(height: 32),
                            _InstructionStep(
                              step: "3",
                              title: "Add UPI Caption",
                              value: "SKYFALL",
                              subtitle:
                                  "This is required for verification. Tap to copy.",
                              isCopyable: true,
                              scaffoldContext: context,
                            ),
                            const SizedBox(height: 24),
                            Center(
                              child: Text(
                                "Once payment is complete, Pro features will be activated after verification (usually within 24 hours).",
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Instruction Step Widget ---
class _InstructionStep extends StatelessWidget {
  final String step;
  final String title;
  final String value;
  final String subtitle;
  final bool isCopyable;
  final BuildContext? scaffoldContext;

  const _InstructionStep({
    required this.step,
    required this.title,
    required this.value,
    required this.subtitle,
    this.isCopyable = false,
    this.scaffoldContext,
  });

  void _copyToClipboard() {
    if (scaffoldContext == null) return;
    Clipboard.setData(ClipboardData(text: value)).then((_) {
      ScaffoldMessenger.of(scaffoldContext!).showSnackBar(
        SnackBar(
          content: Text("Copied '$value' to clipboard!"),
          backgroundColor: Colors.green,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.primary,
          child: Text(
            step,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: isCopyable ? _copyToClipboard : null,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    // MOD: Made container color theme-aware for better light/dark mode
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        value,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      if (isCopyable)
                        Icon(
                          Icons.copy_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.textTheme.bodySmall?.color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Benefit Tile Widget (re-used from your old dialog) ---
class _BenefitTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BenefitTile(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading:
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
    );
  }
}


