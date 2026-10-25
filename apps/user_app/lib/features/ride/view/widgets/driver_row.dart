import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

/// The assigned driver: their initial, a [title] ("Ravi is your driver"), an
/// optional [subtitle] (their rating) and, when there's a [phone], a call
/// button that hands off to the phone's dialer.
class DriverRow extends StatelessWidget {
  const DriverRow({
    super.key,
    required this.name,
    required this.phone,
    String? title,
    this.subtitle,
  }) : title = title ?? '$name is your driver';

  final String name;
  final String? phone;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final phone = this.phone;
    final subtitle = this.subtitle;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: t.sunken,
          child: Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: t.title(14, color: t.primaryText),
          ),
        ),
        const SizedBox(width: Skyline.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: t.title(14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(subtitle, style: t.body(size: 12.5), maxLines: 1),
            ],
          ),
        ),
        if (phone != null)
          IconButton.filled(
            tooltip: 'Call driver',
            style: IconButton.styleFrom(
              backgroundColor: t.primarySoft,
              foregroundColor: t.primaryText,
            ),
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
            icon: const Icon(Icons.call_rounded, size: 20),
          ),
      ],
    );
  }
}
