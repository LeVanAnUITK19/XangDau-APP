import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/screens.dart';

const green = Color(0xff008744);
const greenDark = Color(0xff005c43);
const greenLight = Color(0xffe8f7ef);
final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final router = GoRouter(initialLocation: '/prices', routes: [
  StatefulShellRoute.indexedStack(
    builder: (context, state, shell) => AppShell(shell: shell),
    branches: [
      StatefulShellBranch(routes: [
        GoRoute(path: '/prices', builder: (_, __) => const PricesScreen())
      ]),
      StatefulShellBranch(routes: [
        GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen())
      ]),
      StatefulShellBranch(routes: [
        GoRoute(
            path: '/calculator',
            builder: (_, state) => CalculatorScreen(
                initialFuel: state.uri.queryParameters['fuel'],
                initialRegion: state.uri.queryParameters['region']))
      ]),
      StatefulShellBranch(routes: [
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen())
      ]),
    ],
  ),
  GoRoute(
      path: '/prices/:fuelCode',
      builder: (context, state) => FuelDetailScreen(
          code: state.pathParameters['fuelCode']!,
          region: state.uri.queryParameters['region'] ?? 'REGION_1')),
]);

class GiaXangDauApp extends StatelessWidget {
  const GiaXangDauApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
      title: 'Giá Xăng Dầu',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff5f7f8),
          colorScheme: ColorScheme.fromSeed(
              seedColor: green, primary: green, surface: Colors.white),
          appBarTheme: const AppBarTheme(
              backgroundColor: greenDark,
              foregroundColor: Colors.white,
              centerTitle: false),
          cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xffe1e7eb)))),
          inputDecorationTheme: InputDecorationTheme(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white)),
      routerConfig: router);
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;
  static const paths = ['/prices', '/analytics', '/calculator', '/settings'];
  @override
  Widget build(BuildContext context) => Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) =>
              shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.local_gas_station_outlined),
                selectedIcon: Icon(Icons.local_gas_station),
                label: 'Giá'),
            NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: 'Biểu đồ'),
            NavigationDestination(
                icon: Icon(Icons.calculate_outlined),
                selectedIcon: Icon(Icons.calculate),
                label: 'Tính phí'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Cài đặt')
          ]));
}
