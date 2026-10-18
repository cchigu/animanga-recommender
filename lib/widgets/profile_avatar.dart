import 'package:flutter/material.dart';

/// Top-right profile button. Shows the MAL profile picture once an account
/// is connected (Milestone 2); until then a placeholder icon.
class ProfileAvatar extends StatelessWidget {
  final VoidCallback onTap;
  final String? imageUrl;
  final double size;

  const ProfileAvatar({
    super.key,
    required this.onTap,
    this.imageUrl,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: imageUrl == null
              ? const Icon(Icons.person_rounded, color: Colors.white, size: 26)
              : Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
        ),
      ),
    );
  }
}
