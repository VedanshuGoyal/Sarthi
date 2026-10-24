import 'package:flutter/material.dart';

/// A responsive scaffold for single-column onboarding/auth forms.
///
/// On phones the content fills the width; on tablets and desktop it is centred
/// and width-capped at [maxContentWidth] so fields don't stretch awkwardly
/// (per the responsive-layout guidelines: measure available space, constrain,
/// centre). Content scrolls and stays clear of the keyboard inset.
///
/// It renders a [title] + optional [subtitle] header, the caller's [children]
/// in a column, and pins [footer] (typically the primary button) to the bottom
/// on tall screens.
class SarthiFormScaffold extends StatelessWidget {
  const SarthiFormScaffold({
    super.key,
    required this.title,
    required this.fields,
    this.subtitle,
    this.footer,
    this.leading,
    this.header,
    this.maxContentWidth = 480,
  });

  final String title;
  final String? subtitle;

  /// The form's body widgets, laid out in a column under the header.
  final List<Widget> fields;

  /// Pinned to the bottom of the viewport on tall screens (e.g. a CTA button).
  final Widget? footer;

  /// Optional leading widget in the app bar (e.g. a back button).
  final Widget? leading;

  /// Optional widget shown above the title (e.g. a brand header).
  final Widget? header;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: leading),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 32,
                    ),
                    // IntrinsicHeight gives the Column a bounded height inside
                    // the scroll view so the [Spacer] that pins the footer to
                    // the bottom works instead of throwing on unbounded height.
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (header != null) ...[
                            header!,
                            const SizedBox(height: 24),
                          ],
                          Text(
                            title,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              subtitle!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          ...fields,
                          if (footer != null) ...[
                            const Spacer(),
                            const SizedBox(height: 24),
                            footer!,
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
