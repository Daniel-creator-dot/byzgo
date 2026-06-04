import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/auth_user.dart';
import '../../models/location_point.dart';
import '../../models/order.dart';
import '../../shared/format.dart';
import '../../shared/system_chrome.dart';
import '../../shared/responsive_layout.dart';
import '../../shared/theme.dart';
import '../../shared/user_display.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/bytz_brand.dart';
import '../../shared/widgets/sheet_theme_scope.dart';
import '../../shared/widgets/ride_ui.dart';
import 'customer_activity_tab.dart';
import 'customer_home_screen.dart';
import 'customer_profile_tab.dart';
import 'customer_shops_tab.dart';
import 'customer_tab.dart';
import 'customer_wallet_sheet.dart';

/// Full customer app chrome — header, tabs, wallet, profile (web parity).
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  CustomerTab _tab = CustomerTab.courier;
  LocationPoint? _shopPickup;
  final _homeKey = GlobalKey<CustomerHomeScreenState>();
  final _activityKey = GlobalKey<CustomerActivityTabState>();

  @override
  void initState() {
    super.initState();
    BytzSystemChrome.applyMap();
  }

  void _goTab(CustomerTab tab) {
    final prev = _tab;
    setState(() => _tab = tab);
    if (tab == CustomerTab.courier) {
      BytzSystemChrome.applyMap();
    } else {
      BytzSystemChrome.applyLightSheet();
    }
    if (tab == CustomerTab.activity && prev != CustomerTab.activity) {
      _activityKey.currentState?.reload();
    }
  }

  void _onShopOrderPlaced(Order order) {
    _homeKey.currentState?.noteOrder(order);
    _activityKey.currentState?.noteOrder(order);
    _goTab(CustomerTab.activity);
  }

  void _onShopPickup(LocationPoint pickup) {
    setState(() {
      _shopPickup = pickup;
      _tab = CustomerTab.courier;
    });
    _homeKey.currentState?.applyShopPickup(pickup);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pickup set to ${pickup.address}'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: BytzGoTheme.accentDark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user!;
    final firstName = userFirstName(user);
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    final onMap = _tab == CustomerTab.courier;
    final body = Column(
      children: [
        _CustomerHeader(
          tab: _tab,
          firstName: firstName,
          user: user,
          onWallet: () => showCustomerWalletSheet(context),
          onProfile: () => _goTab(CustomerTab.profile),
          onNotifications: () => _goTab(CustomerTab.activity),
        ),
        if (!onMap)
          _walletBanner(user.balance, onTap: () => showCustomerWalletSheet(context)),
        Expanded(
          child: IndexedStack(
            index: _tab.index,
            children: [
              CustomerHomeScreen(
                key: _homeKey,
                initialPickup: _shopPickup,
                embedded: true,
                onOpenShops: () => _goTab(CustomerTab.shops),
                onOpenWallet: () => showCustomerWalletSheet(context),
                onOpenActivity: () => _goTab(CustomerTab.activity),
                onOpenProfile: () => _goTab(CustomerTab.profile),
              ),
              CustomerShopsTab(
                onShopPickup: _onShopPickup,
                onShopOrderPlaced: _onShopOrderPlaced,
              ),
              CustomerActivityTab(
                key: _activityKey,
                onTrackOrder: () => _goTab(CustomerTab.courier),
              ),
              const CustomerProfileTab(),
            ],
          ),
        ),
      ],
    );

    return SheetThemeScope(
      child: Scaffold(
      backgroundColor: onMap ? BytzGoTheme.background : BytzGoTheme.sheetBg,
      body: onMap
          ? body
          : BytzLayout.tabletFrame(
              context,
              backgroundColor: BytzGoTheme.sheetBg,
              child: body,
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: BytzGoTheme.sheetBg,
          border: Border(top: BorderSide(color: BytzGoTheme.sheetDivider)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPad > 0 ? bottomPad : 12),
        child: BytzLayout.constrainContent(
          context,
          maxWidth: BytzLayout.contentMaxWidth(context),
          child: Row(
          children: CustomerTab.values.map((t) {
            final selected = _tab == t;
            return Expanded(
              child: _NavItem(
                tab: t,
                selected: selected,
                onTap: () => _goTab(t),
              ),
            );
          }).toList(),
        ),
        ),
      ),
    ),
    );
  }

  Widget _walletBanner(double balance, {required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: BytzGoTheme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: BytzGoTheme.accentDark, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Wallet ${formatCedisCompact(balance)} · Tap to top up',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: BytzGoTheme.accentDark,
                  ),
                ),
              ),
              const Icon(Icons.add_circle_outline,
                  color: BytzGoTheme.accentDark, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({
    required this.tab,
    required this.firstName,
    required this.user,
    required this.onWallet,
    required this.onProfile,
    required this.onNotifications,
  });

  final CustomerTab tab;
  final String firstName;
  final AuthUser user;
  final VoidCallback onWallet;
  final VoidCallback onProfile;
  final VoidCallback onNotifications;

  String get _title {
    switch (tab) {
      case CustomerTab.courier:
        return 'Book a delivery';
      case CustomerTab.shops:
        return 'Shops';
      case CustomerTab.activity:
        return 'Your trips';
      case CustomerTab.profile:
        return 'Account';
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final onMap = tab == CustomerTab.courier;

    if (onMap) {
      return Container(
        padding: EdgeInsets.fromLTRB(12, top + 6, 12, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              BytzGoTheme.sheetBg.withValues(alpha: 0.94),
              BytzGoTheme.sheetBg.withValues(alpha: 0.72),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            const BytzGoLogo(fontSize: 16),
            const Spacer(),
            _walletChip(),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onProfile,
              child: UserAvatar(user: user, radius: 18),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 12),
      decoration: BoxDecoration(
        color: BytzGoTheme.sheetBg,
        border: Border(
          bottom: BorderSide(color: BytzGoTheme.sheetDivider),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BytzGoLogo(fontSize: 18),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: BytzGoTheme.sheetText,
                    ),
                    children: [
                      const TextSpan(text: 'Hey, '),
                      TextSpan(
                        text: firstName,
                        style: const TextStyle(color: BytzGoTheme.accentDark),
                      ),
                    ],
                  ),
                ),
                Text(
                  _title,
                  style: BytzGoTheme.sheetBody(12),
                ),
              ],
            ),
          ),
          _HeaderIcon(
            icon: Icons.notifications_outlined,
            semanticLabel: 'Trip updates',
            onTap: onNotifications,
          ),
          const SizedBox(width: 6),
          _walletChip(),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onProfile,
            child: UserAvatar(
              user: user,
              radius: 22,
              backgroundColor: BytzGoTheme.brandBlue.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _walletChip() {
    return Material(
      color: BytzGoTheme.accent.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onWallet,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: BytzGoTheme.accentDark,
              ),
              const SizedBox(width: 6),
              Text(
                formatCedisCompact(user.balance),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: BytzGoTheme.accentDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: BytzGoTheme.sheetDivider.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              size: 22,
              color: BytzGoTheme.sheetText,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final CustomerTab tab;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (tab) {
      case CustomerTab.courier:
        return Icons.bolt;
      case CustomerTab.shops:
        return Icons.storefront_outlined;
      case CustomerTab.activity:
        return Icons.route_outlined;
      case CustomerTab.profile:
        return Icons.person_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? BytzGoTheme.accent.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(color: BytzGoTheme.accent.withValues(alpha: 0.45))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Icon(
                _icon,
                size: 22,
                color: selected ? BytzGoTheme.accentDark : BytzGoTheme.sheetMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
                color: selected ? BytzGoTheme.accentDark : BytzGoTheme.sheetMuted,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
