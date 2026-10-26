import 'package:flutter/material.dart';
import 'package:sarthi_shared/sarthi_shared.dart';
import 'package:url_launcher/url_launcher.dart';

/// The assigned driver: their [photo] (their initial until it loads, or when
/// they have none), a [title] ("Ravi is your driver"), an optional
/// [subtitle] (their rating) and, when there's a [phone], a call button that
/// hands off to the phone's dialer.
class DriverRow extends StatelessWidget {
  const DriverRow({
    super.key,
    required this.name,
    required this.phone,
    String? title,
    this.subtitle,
    this.photo,
    this.avatarRadius = 18,
  }) : title = title ?? '$name is your driver';

  final String name;
  final String? phone;
  final String title;
  final String? subtitle;
  final ImageProvider? photo;
  final double avatarRadius;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final phone = this.phone;
    final subtitle = this.subtitle;
    return Row(
      children: [
        DriverAvatar(name: name, photo: photo, radius: avatarRadius),
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

/// A driver's [photo] in a circle, or their initial while it loads and when
/// there's none or it fails.
class DriverAvatar extends StatelessWidget {
  const DriverAvatar({
    super.key,
    required this.name,
    this.photo,
    this.radius = 18,
  });

  final String name;
  final ImageProvider? photo;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = SkylineTokens.of(context);
    final initial = CircleAvatar(
      radius: radius,
      backgroundColor: t.sunken,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: t.title(radius * 0.78, color: t.primaryText),
      ),
    );
    final photo = this.photo;
    if (photo == null) return initial;
    return Semantics(
      label: 'Photo of $name',
      image: true,
      child: ClipOval(
        child: Image(
          image: photo,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
              frame == null && !wasSynchronouslyLoaded ? initial : child,
          errorBuilder: (_, _, _) => initial,
        ),
      ),
    );
  }
}
