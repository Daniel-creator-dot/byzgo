import 'package:flutter/material.dart';

import '../../models/vendor.dart';
import '../../shared/shop_story_views.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/vendor_story_ring.dart';
import 'vendor_story_viewer.dart';

/// Horizontal "Shop Drops" rail — tap a ring to open full-screen flyer story.
class CustomerShopStoriesRail extends StatelessWidget {
  const CustomerShopStoriesRail({
    super.key,
    required this.vendors,
    required this.seenPostedAt,
    required this.onSeenVendor,
    required this.onOrderFromStory,
  });

  final List<Vendor> vendors;
  final Map<String, int> seenPostedAt;
  final void Function(Vendor vendor) onSeenVendor;
  final void Function(Vendor vendor) onOrderFromStory;

  List<Vendor> get _storyVendors {
    final list = vendors.where((v) => v.hasActiveStory).toList();
    list.sort((a, b) {
      final aUnseen = ShopStoryViews.showStoryRing(a, seenPostedAt) ? 0 : 1;
      final bUnseen = ShopStoryViews.showStoryRing(b, seenPostedAt) ? 0 : 1;
      if (aUnseen != bUnseen) return aUnseen.compareTo(bUnseen);
      final at = a.shopStoryPostedAt;
      final bt = b.shopStoryPostedAt;
      if (at != null && bt != null) return bt.compareTo(at);
      return a.name.compareTo(b.name);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final stories = _storyVendors;
    if (stories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: BytzGoTheme.accent),
              const SizedBox(width: 6),
              Text(
                'Shop Drops',
                style: BytzGoTheme.sheetTitle(14).copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              Text(
                '${stories.length} live',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: BytzGoTheme.sheetMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Tap a ring to watch — like a shop status. New drops fade after 24 hours.',
            style: TextStyle(
              fontSize: 11,
              color: BytzGoTheme.sheetMuted.withValues(alpha: 0.9),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: stories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final v = stories[i];
              final unseen = ShopStoryViews.showStoryRing(v, seenPostedAt);
              return SizedBox(
                width: 76,
                child: Column(
                  children: [
                    VendorStoryRing(
                      vendor: v,
                      unseen: unseen,
                      size: 68,
                      onTap: () => _openStory(context, stories, i),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      v.name.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: unseen ? FontWeight.w900 : FontWeight.w600,
                        color: unseen ? BytzGoTheme.sheetText : BytzGoTheme.sheetMuted,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openStory(
    BuildContext context,
    List<Vendor> stories,
    int initialIndex,
  ) async {
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) => VendorStoryViewer(
          vendors: stories,
          initialIndex: initialIndex,
          seenPostedAt: seenPostedAt,
          onSeen: onSeenVendor,
          onOrder: onOrderFromStory,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}
