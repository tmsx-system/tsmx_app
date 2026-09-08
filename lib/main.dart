import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'state/app_state.dart';
import 'state/auth/auth_state.dart';
import 'state/dashboard/dashboard_state.dart';
import 'state/finance/finance_state.dart';
import 'state/logistics/logistics_delivery_state.dart';
import 'state/logistics/logistics_overview_state.dart';
import 'state/logistics/logistics_tracking_state.dart';
import 'state/purchasing/material_request_state.dart';
import 'state/purchasing/purchase_invoice_state.dart';
import 'state/purchasing/purchase_order_state.dart';
import 'state/purchasing/purchase_receipt_state.dart';
import 'state/purchasing/purchasing_filter_state.dart';
import 'state/profile/profile_state.dart';
import 'state/selling/collection_state.dart';
import 'state/selling/customer_state.dart';
import 'state/selling/delivery_note_state.dart';
import 'state/selling/noo_state.dart';
import 'state/selling/promo_state.dart';
import 'state/selling/sales_invoice_state.dart';
import 'state/selling/sales_order_state.dart';
import 'state/selling/sales_overview_state.dart';
import 'state/selling/selling_filter_state.dart';
import 'state/spg/spg_state.dart';
import 'state/todo/todo_state.dart';
import 'state/visits/visit_state.dart';
import 'state/warehouse/warehouse_aging_state.dart';
import 'state/warehouse/warehouse_dead_stock_state.dart';
import 'state/warehouse/warehouse_stock_state.dart';
import 'state/warehouse/warehouse_valuation_state.dart';
import 'services/erp_services.dart';
import 'services/native_notification_service.dart';
import 'screens/auth/loading_screen.dart';
import 'theme/app_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NativeNotificationService.instance.initialize();
  final services = ErpServices();
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: services),
        ChangeNotifierProvider(create: (_) => AppState(services: services)),
        ChangeNotifierProxyProvider<AppState, AuthState>(
          create: (context) => AuthState(appState: context.read<AppState>()),
          update: (_, appState, authState) =>
              (authState ?? AuthState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, DashboardState>(
          create: (context) =>
              DashboardState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? DashboardState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, TodoState>(
          create: (context) => TodoState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? TodoState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, ProfileState>(
          create: (context) => ProfileState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? ProfileState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, FinanceState>(
          create: (context) => FinanceState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? FinanceState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, SellingFilterState>(
          create: (context) =>
              SellingFilterState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? SellingFilterState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, SalesOrderState>(
          create: (context) =>
              SalesOrderState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? SalesOrderState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, SalesOverviewState>(
          create: (context) =>
              SalesOverviewState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? SalesOverviewState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, DeliveryNoteState>(
          create: (context) =>
              DeliveryNoteState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? DeliveryNoteState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, SalesInvoiceState>(
          create: (context) =>
              SalesInvoiceState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? SalesInvoiceState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, CustomerState>(
          create: (context) =>
              CustomerState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? CustomerState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, CollectionState>(
          create: (context) =>
              CollectionState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? CollectionState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, NooState>(
          create: (context) => NooState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? NooState(appState: appState))..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, PromoState>(
          create: (context) => PromoState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? PromoState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, SpgState>(
          create: (context) => SpgState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? SpgState(appState: appState))..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, VisitState>(
          create: (context) => VisitState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? VisitState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, PurchasingFilterState>(
          create: (context) =>
              PurchasingFilterState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? PurchasingFilterState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, MaterialRequestState>(
          create: (context) =>
              MaterialRequestState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? MaterialRequestState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, PurchaseOrderState>(
          create: (context) =>
              PurchaseOrderState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? PurchaseOrderState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, PurchaseReceiptState>(
          create: (context) =>
              PurchaseReceiptState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? PurchaseReceiptState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, PurchaseInvoiceState>(
          create: (context) =>
              PurchaseInvoiceState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? PurchaseInvoiceState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, WarehouseStockState>(
          create: (context) =>
              WarehouseStockState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? WarehouseStockState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<
          WarehouseStockState,
          WarehouseValuationState
        >(
          create: (context) => WarehouseValuationState(
            stockState: context.read<WarehouseStockState>(),
          ),
          update: (_, stockState, state) =>
              (state ?? WarehouseValuationState(stockState: stockState))
                ..updateStockState(stockState),
        ),
        ChangeNotifierProxyProvider<WarehouseStockState, WarehouseAgingState>(
          create: (context) => WarehouseAgingState(
            stockState: context.read<WarehouseStockState>(),
          ),
          update: (_, stockState, state) =>
              (state ?? WarehouseAgingState(stockState: stockState))
                ..updateStockState(stockState),
        ),
        ChangeNotifierProxyProvider<
          WarehouseStockState,
          WarehouseDeadStockState
        >(
          create: (context) => WarehouseDeadStockState(
            stockState: context.read<WarehouseStockState>(),
          ),
          update: (_, stockState, state) =>
              (state ?? WarehouseDeadStockState(stockState: stockState))
                ..updateStockState(stockState),
        ),
        ChangeNotifierProxyProvider<AppState, LogisticsOverviewState>(
          create: (context) =>
              LogisticsOverviewState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? LogisticsOverviewState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, LogisticsTrackingState>(
          create: (context) =>
              LogisticsTrackingState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? LogisticsTrackingState(appState: appState))
                ..updateAppState(appState),
        ),
        ChangeNotifierProxyProvider<AppState, LogisticsDeliveryState>(
          create: (context) =>
              LogisticsDeliveryState(appState: context.read<AppState>()),
          update: (_, appState, state) =>
              (state ?? LogisticsDeliveryState(appState: appState))
                ..updateAppState(appState),
        ),
      ],
      child: const TmsxHubApp(),
    ),
  );
}

class TmsxHubApp extends StatelessWidget {
  const TmsxHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.defaultAppName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.light,
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.accentYellow,
          surface: AppColors.surface,
          surfaceContainerLowest: AppColors.white,
          surfaceContainer: AppColors.surfaceMuted,
        ),

        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.hankenGroteskTextTheme(
          Theme.of(context).textTheme,
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.primary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: AppColors.primary),
          titleTextStyle: TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),

        dividerTheme: const DividerThemeData(
          color: AppColors.border,
          thickness: 1,
        ),

        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primary,
          linearTrackColor: AppColors.softGreen,
        ),

        cardTheme: CardThemeData(
          color: AppColors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.border),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceMuted,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),

        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 3,
        ),

        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return Colors.white;
          }),
          trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.softGreen;
          }),
        ),
      ),

      home: const LoadingScreen(),
    );
  }
}
