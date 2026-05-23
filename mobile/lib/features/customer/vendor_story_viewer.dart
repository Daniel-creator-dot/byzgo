import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/vendor.dart';
import '../../shared/vendor_contact.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/app_network_image.dart';
import '../../shared/widgets/vendor_promo_badge.dart';

/// Full-screen Shop Drop viewer (flyer + status + order CTA).
class VendorStoryViewer extends StatefulWidget {
  const VendorStoryViewer({
    super.key,
    required this.vendors,
    required this.initialIndex,
    required this.seenPostedAt,
    required this.onSeen,
    required this.onOrder,
  });

  final List<Vendor> vendors;
  final int initialIndex;
  final Map<String, int> seenPostedAt;
  final void Function(Vendor vendor) onSeen;
  final void Function(Vendor vendor) onOrder;

  @override
  State<VendorStoryViewer> createState() => _VendorStoryViewerState();
}

class _VendorStoryViewerState extends State<VendorStoryViewer> {
  late final PageController _pageCtrl;
  late int _index;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.vendors.length - 1);
    _pageCtrl = PageController(initialPage: _index);
    _markCurrentSeen();
    _startAutoAdvance();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Vendor get _vendor => widget.vendors[_index];

  void _markCurrentSeen() {
    widget.onSeen(_vendor);
  }

  void _startAutoAdvance() {
    _autoTimer?.cancel();
    if (widget.vendors.length <= 1) return;
    _autoTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_index < widget.vendors.length - 1) {
        _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } else {
        Navigator.of(context).pop();
      }
    });
  }

  String _timeLeftLabel(Vendor v) {
    final exp = v.shopStoryExpiresAt;
    if (exp == null) return 'Live now';
    final left = exp.difference(DateTime.now());
    if (left.isNegative) return 'Expired';
    if (left.inHours >= 1) return '${left.inHours}h left';
    return '${left.inMinutes}m left';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragEnd: (d) {
          if (d.primaryVelocity != null && d.primaryVelocity! > 200) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.vendors.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                _markCurrentSeen();
                _startAutoAdvance();
              },
              itemBuilder: (_, i) => _StoryPage(vendor: widget.vendors[i]),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _vendor.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                _timeLeftLabel(_vendor),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.vendors.length > 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: List.generate(widget.vendors.length, (i) {
                          final active = i == _index;
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: 3,
                              decoration: BoxDecoration(
                                color: active
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _bottomPanel(context),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 56,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_index > 0) {
                    _pageCtrl.previousPage(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 56,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_index < widget.vendors.length - 1) {
                    _pageCtrl.nextPage(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomPanel(BuildContext context) {
    final v = _vendor;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.85),
            Colors.black,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          VendorPromoBadgeRow(promo: v.promo),
          if (v.shopStatusMessage != null && v.shopStatusMessage!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              v.shopStatusMessage!.trim(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          if (v.shopDiscountLabel != null && v.shopDiscountLabel!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              v.shopDiscountLabel!.trim(),
              style: const TextStyle(
                color: Color(0xFF4ADE80),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: v.shopOpenStatus == 'closed'
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    Navigator.of(context).pop();
                    widget.onOrder(v);
                  },
            style: FilledButton.styleFrom(
              backgroundColor: BytzGoTheme.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              disabledBackgroundColor: Colors.white24,
            ),
            child: Text(
              v.shopOpenStatus == 'closed' ? 'Shop closed' : 'Order from ${v.name}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
          if (v.phone != null && v.phone!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              formatVendorPhone(v.phone),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _StoryPage extends StatelessWidget {
  const _StoryPage({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final url = vendor.shopStoryImage?.trim();
    if (url == null || url.isEmpty) {
      return const Center(
        child: Text('No flyer', style: TextStyle(color: Colors.white54)),
      );
    }
    return AppNetworkImage(
      url: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      semanticLabel: '${vendor.name} shop drop flyer',
    );
  }
}
