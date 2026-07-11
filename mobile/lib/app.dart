import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/config_repository.dart';
import 'core/delivery_pricing_config.dart';
import 'core/maps_runtime_config.dart';
import 'core/directions_service.dart';
import 'core/location_service.dart';
import 'core/places_service.dart';
import 'core/push_notification_service.dart';
import 'core/session.dart';
import 'core/socket_service.dart';
import 'core/shop_chat_unread.dart';
import 'core/trip_chat_unread.dart';
import 'features/admin/admin_repository.dart';
import 'features/auth/auth_repository.dart';
import 'features/orders/orders_repository.dart';
import 'features/shop_chat/shop_chat_repository.dart';
import 'features/rider/rider_commission_repository.dart';
import 'features/rider/rider_documents_repository.dart';
import 'features/owner/owner_repository.dart';
import 'features/vendor/vendor_repository.dart';
import 'features/riders/riders_repository.dart';
import 'features/support/support_repository.dart';
import 'features/wallet/wallet_repository.dart';
import 'features/rider/rider_stats_repository.dart';
import 'routing/app_router.dart';
import 'shared/system_chrome.dart';
import 'shared/theme.dart';
import 'shared/client_image_url.dart';
import 'shared/widgets/app_launch_carousel.dart';

class BytzGoApp extends StatefulWidget {
  const BytzGoApp({super.key});

  @override
  State<BytzGoApp> createState() => _BytzGoAppState();
}

class _BytzGoAppState extends State<BytzGoApp> {
  late final ApiClient _api;
  late final SocketService _socket;
  late final Session _session;
  late final TripChatUnread _tripChatUnread;
  late final ShopChatUnread _shopChatUnread;
  late final DeliveryPricingConfig _deliveryPricing;
  late final MapsRuntimeConfig _mapsRuntime;
  late final GoRouter _router;
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    BytzSystemChrome.applyDarkHero();
    _socket = SocketService();
    _api = ApiClient();
    _deliveryPricing = DeliveryPricingConfig(_api, _socket);
    _mapsRuntime = MapsRuntimeConfig(_api);
    _session = Session(_api, _socket);
    _tripChatUnread = TripChatUnread();
    _shopChatUnread = ShopChatUnread();
    _session.onAuthChanged = () async {
      await _deliveryPricing.onAuthChanged();
      await PushNotificationService.instance.syncActiveRole(
        api: _api,
        user: _session.user,
        session: _session,
      );
    };
    _api.onRefreshToken = () => _session.refreshAuthFromServer();
    _api.onUnauthorized = () {
      _tripChatUnread.clear();
      _shopChatUnread.applyConversationList(const []);
      _session.clear();
    };
    _router = createAppRouter(_session);
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();

    Future<void> loadHealth() async {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final health = await _api.dio.get<Map<String, dynamic>>(
            '/api/health',
            options: Options(
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          );
          await ClientImageUrl.loadFromHealth(health.data);
          return;
        } catch (_) {
          if (attempt == 2) {
            ClientImageUrl.setPublicBase(ClientImageUrl.defaultPublicBase);
          } else {
            await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
          }
        }
      }
    }

    await Future.wait([
      loadHealth(),
      _session.restore(),
    ]);

    final postAuth = <Future<void>>[];
    if (_session.isAuthenticated) {
      postAuth.add(_session.refreshAuthFromServer());
    }
    postAuth.add(_deliveryPricing.start());
    postAuth.add(_mapsRuntime.ensureLoaded());
    await Future.wait(postAuth);

    await PushNotificationService.instance.syncActiveRole(
      api: _api,
      user: _session.user,
      session: _session,
    );
    const minSplash = Duration(milliseconds: 600);
    final elapsed = DateTime.now().difference(started);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }
    if (mounted) setState(() => _splashDone = true);
  }

  @override
  void dispose() {
    _deliveryPricing.dispose();
    _socket.disconnect();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: _api),
        Provider<SocketService>.value(value: _socket),
        ChangeNotifierProvider<Session>.value(value: _session),
        ChangeNotifierProvider<TripChatUnread>.value(value: _tripChatUnread),
        ChangeNotifierProvider<ShopChatUnread>.value(value: _shopChatUnread),
        ChangeNotifierProvider<DeliveryPricingConfig>.value(value: _deliveryPricing),
        ChangeNotifierProvider<MapsRuntimeConfig>.value(value: _mapsRuntime),
        Provider(create: (ctx) => AuthRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => RiderDocumentsRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => AdminRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => OrdersRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => VendorRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => OwnerRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => RidersRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => WalletRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => RiderStatsRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => RiderCommissionRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => SupportRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => ShopChatRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => ConfigRepository(ctx.read<ApiClient>())),
        Provider(create: (_) => LocationService()),
        Provider(create: (ctx) => PlacesService(ctx.read<ApiClient>())),
        Provider(create: (ctx) => DirectionsService(ctx.read<ApiClient>())),
      ],
      child: MaterialApp.router(
        title: 'BytzGo',
        debugShowCheckedModeBanner: false,
        theme: BytzGoTheme.dark(),
        routerConfig: _router,
        builder: (context, child) {
          return Consumer<Session>(
            builder: (context, session, _) {
              if (!_splashDone || session.isRestoring) {
                return const Material(
                  child: AppLaunchCarousel(message: 'Loading your city…'),
                );
              }
              if (child == null) {
                return const Material(
                  child: AppLaunchCarousel(message: 'Loading your city…'),
                );
              }
              return child;
            },
          );
        },
      ),
    );
  }
}
