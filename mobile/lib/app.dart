import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/config_repository.dart';
import 'core/directions_service.dart';
import 'core/location_service.dart';
import 'core/places_service.dart';
import 'core/push_notification_service.dart';
import 'core/session.dart';
import 'core/socket_service.dart';
import 'features/admin/admin_repository.dart';
import 'features/auth/auth_repository.dart';
import 'features/orders/orders_repository.dart';
import 'features/rider/rider_documents_repository.dart';
import 'features/vendor/vendor_repository.dart';
import 'features/riders/riders_repository.dart';
import 'features/wallet/wallet_repository.dart';
import 'routing/app_router.dart';
import 'shared/system_chrome.dart';
import 'shared/theme.dart';
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
  late final GoRouter _router;
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    BytzSystemChrome.applyDarkHero();
    _socket = SocketService();
    _api = ApiClient();
    _session = Session(_api, _socket);
    _api.onUnauthorized = () => _session.clear();
    _router = createAppRouter(_session);
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    await _session.restore();
    if (_session.isAuthenticated) {
      await PushNotificationService.instance.ensureRegistered(
        api: _api,
        session: _session,
      );
    }
    const minSplash = Duration(milliseconds: 900);
    final elapsed = DateTime.now().difference(started);
    if (elapsed < minSplash) {
      await Future.delayed(minSplash - elapsed);
    }
    if (mounted) setState(() => _splashDone = true);
  }

  @override
  void dispose() {
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
        Provider(create: (ctx) => AuthRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => RiderDocumentsRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => AdminRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => OrdersRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => VendorRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => RidersRepository(ctx.read<ApiClient>())),
        Provider(create: (ctx) => WalletRepository(ctx.read<ApiClient>())),
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
              return child ?? const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }
}
