import 'package:flutter/material.dart';

import '../../shared/theme.dart';
import 'admin_menu_tab.dart';
import 'admin_vendors_tab.dart';

/// Stores hub — vendor accounts + menu approval (all in Flutter).
class AdminStoresHub extends StatefulWidget {
  const AdminStoresHub({
    super.key,
    required this.onVendorPendingCount,
    required this.onMenuPendingCount,
  });

  final ValueChanged<int> onVendorPendingCount;
  final ValueChanged<int> onMenuPendingCount;

  @override
  State<AdminStoresHub> createState() => AdminStoresHubState();
}

class AdminStoresHubState extends State<AdminStoresHub>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _vendorsKey = GlobalKey<AdminVendorsTabState>();
  final _menuKey = GlobalKey<AdminMenuTabState>();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void reload() {
    _vendorsKey.currentState?.load();
    _menuKey.currentState?.load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: const Color(0xFF0F172A),
          child: TabBar(
            controller: _tabs,
            indicatorColor: BytzGoTheme.accent,
            labelColor: BytzGoTheme.accent,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            tabs: const [
              Tab(text: 'Accounts'),
              Tab(text: 'Menu queue'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              AdminVendorsTab(
                key: _vendorsKey,
                onPendingCount: widget.onVendorPendingCount,
              ),
              AdminMenuTab(
                key: _menuKey,
                onPendingCount: widget.onMenuPendingCount,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
