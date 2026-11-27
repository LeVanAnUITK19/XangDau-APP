import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gia_xang_dau/app.dart';
import 'package:gia_xang_dau/core/api.dart';
import 'package:gia_xang_dau/core/calculator.dart';
import 'package:gia_xang_dau/core/push_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

final api = FuelApi();
final money = NumberFormat('#,##0', 'vi_VN');

String titleOf(String code) =>
    const {
      'E5_RON_92': 'Xăng E5 RON 92',
      'E10_RON_95_III': 'Xăng E10 RON 95-III',
      'E10_RON_95_V': 'Xăng E10 RON 95-V',
      'RON_95_III': 'Xăng RON 95-III',
      'RON_95_V': 'Xăng RON 95-V',
      'DIESEL_001S': 'Dầu diesel 0,001S (Mức 5)',
      'DIESEL_005S': 'Dầu diesel 0.05S',
      'KEROSENE': 'Dầu hỏa',
      'MAZUT_180CST_35S': 'Dầu mazut 180CST 3.5S',
    }[code] ??
    code.replaceAll('_', ' ');

String formatPrice(num price, String unit) =>
    '${money.format(price)} đ/${unit == 'kg' ? 'kg' : 'L'}';

String formatUpdatedAt(Object? value) {
  final parsed = value == null ? null : DateTime.tryParse(value.toString());
  return parsed == null
      ? 'Chưa có lần đồng bộ thành công'
      : DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
}

String formatEffectiveDate(Object? value) {
  if (value == null) return 'Chưa xác định';
  final raw = value.toString();
  final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (dateOnly != null) {
    return '${dateOnly.group(3)}/${dateOnly.group(2)}/${dateOnly.group(1)}';
  }
  final parsed = DateTime.tryParse(raw);
  return parsed == null
      ? 'Chưa xác định'
      : DateFormat('dd/MM/yyyy').format(parsed.toLocal());
}

class PricesScreen extends StatefulWidget {
  const PricesScreen({super.key});

  @override
  State<PricesScreen> createState() => _PricesScreenState();
}

class _PricesScreenState extends State<PricesScreen> {
  String region = 'REGION_1';
  late Future<Map<String, dynamic>> future = _load();

  @override
  void initState() {
    super.initState();
    _restoreRegion();
  }

  Future<void> _restoreRegion() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('region.default') ?? 'REGION_1';
    if (mounted && saved != region) {
      setState(() {
        region = saved;
        future = _load();
      });
    }
  }

  Future<Map<String, dynamic>> _load() =>
      api.cachedGet('/api/v1/prices/latest', query: {'region': region});

  void _reloadPrices() {
    final next = _load();
    setState(() {
      future = next;
    });
  }

  Future<void> _refreshPrices() async {
    final next = _load();
    setState(() {
      future = next;
    });
    try {
      await next;
    } on Object {
      // FutureBuilder renders the existing error state for this request.
    }
  }

  Future<void> _chooseRegion() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: const Text('Toàn quốc (Vùng 1)'),
            onTap: () => Navigator.pop(context, 'REGION_1'),
          ),
          ListTile(
            title: const Text('Vùng 2'),
            onTap: () => Navigator.pop(context, 'REGION_2'),
          ),
        ]),
      ),
    );
    if (selected == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('region.default', selected);
    setState(() {
      region = selected;
      future = _load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Giá xăng dầu'),
          actions: [
            IconButton(
              tooltip: 'So sánh Vùng 1 và Vùng 2',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const RegionCompareScreen())),
              icon: const Icon(Icons.compare_arrows),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshPrices,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.location_on, color: green),
                title: const Text('Khu vực'),
                subtitle: Text(
                    region == 'REGION_1' ? 'Toàn quốc (Vùng 1)' : 'Vùng 2'),
                trailing: const Icon(Icons.expand_more),
                onTap: _chooseRegion,
              ),
            ),
            FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return ErrorState(
                    message: 'Không tải được giá. Kiểm tra kết nối máy chủ.',
                    retry: _reloadPrices,
                  );
                }
                final response = snapshot.data!;
                final rows = (response['data'] as List? ?? []).cast<Map>();
                if (rows.isEmpty) {
                  return const EmptyState(
                    message: 'Chưa có giá được xác nhận từ nguồn dữ liệu.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (response['_cached'] == true)
                      const Notice(text: 'Đang xem dữ liệu đã lưu trên máy.'),
                    if ((response['meta'] as Map?)?['stale'] == true)
                      const Notice(
                          text: 'Dữ liệu có thể đã cũ. Kéo xuống để cập nhật.'),
                    _PriceUpdateCard(
                      meta: response['meta'] as Map? ?? const {},
                      currentPrice: rows.first,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text('Giá nhiên liệu hiện tại',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    for (final row in rows)
                      FuelTile(
                        row: row,
                        onTap: () => context
                            .push('/prices/${row['fuelCode']}?region=$region'),
                      ),
                  ],
                );
              },
            ),
          ]),
        ),
      );
}

class FuelTile extends StatelessWidget {
  const FuelTile({super.key, required this.row, this.onTap});
  final Map row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final change = (row['priceChange'] as num?)?.toDouble() ?? 0;
    final unit = '${row['unit'] ?? 'liter'}';
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          unit == 'kg' ? Icons.water_drop : Icons.local_gas_station,
          color: green,
        ),
        title: Text(titleOf('${row['fuelCode']}'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(unit == 'kg' ? 'Đơn vị: đ/kg' : 'Đơn vị: đ/lít'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatPrice(row['currentPrice'] as num, unit),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              change == 0
                  ? 'Chưa có kỳ trước'
                  : '${change > 0 ? '▲' : '▼'} ${money.format(change.abs())} đ',
              style: TextStyle(
                  color: change > 0
                      ? Colors.red
                      : change < 0
                          ? green
                          : Colors.blueGrey,
                  fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceUpdateCard extends StatelessWidget {
  const _PriceUpdateCard({required this.meta, required this.currentPrice});

  final Map meta;
  final Map currentPrice;

  @override
  Widget build(BuildContext context) {
    final source = meta['source'] ?? currentPrice['source'];
    return Card(
      color: greenLight,
      child: ListTile(
        leading: const Icon(Icons.schedule, color: green),
        title: const Text('Thời điểm dữ liệu'),
        subtitle: Text([
          'Đồng bộ gần nhất: ${formatUpdatedAt(meta['lastSuccessfulSyncAt'])}',
          'Giá có hiệu lực từ: ${formatEffectiveDate(currentPrice['effectiveDate'] ?? currentPrice['effectiveAt'])}',
          if (source != null) 'Nguồn: $source',
        ].join('\n')),
      ),
    );
  }
}

class RegionCompareScreen extends StatelessWidget {
  const RegionCompareScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('So sánh theo vùng')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: api.cachedGet('/api/v1/prices/compare-regions'),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const ErrorState(message: 'Không tải được giá hai vùng.');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = (snapshot.data!['data'] as List? ?? []).cast<Map>();
            if (rows.isEmpty) {
              return const EmptyState(
                  message: 'Chưa có giá xác nhận cho cả hai vùng.');
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              const Notice(
                  text: 'Chỉ đối chiếu cùng nhiên liệu và cùng đơn vị tính.'),
              for (final row in rows)
                Card(
                  child: ListTile(
                    title: Text(titleOf('${row['fuelCode']}')),
                    subtitle: Text(
                        'Vùng 1: ${row['region1'] == null ? '—' : formatPrice(row['region1'] as num, '${row['unit']}')}\nVùng 2: ${row['region2'] == null ? '—' : formatPrice(row['region2'] as num, '${row['unit']}')}'),
                    isThreeLine: true,
                    trailing: row['region1'] != null && row['region2'] != null
                        ? Text(
                            '${money.format((row['region2'] as num) - (row['region1'] as num))} đ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          )
                        : const Text('—'),
                  ),
                ),
            ]);
          },
        ),
      );
}

class FuelDetailScreen extends StatelessWidget {
  const FuelDetailScreen(
      {super.key, required this.code, this.region = 'REGION_1'});
  final String code;
  final String region;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Chi tiết nhiên liệu')),
        body: FutureBuilder<Map<String, dynamic>>(
          future:
              api.cachedGet('/api/v1/prices/$code', query: {'region': region}),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const ErrorState(message: 'Chưa có dữ liệu chi tiết.');
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!['data'] as Map;
            final current = data['current'] as Map;
            final unit = '${current['unit'] ?? 'liter'}';
            return ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.local_gas_station,
                      color: green, size: 34),
                  title: Text(titleOf(code)),
                  subtitle:
                      Text(formatPrice(current['currentPrice'] as num, unit)),
                ),
              ),
              Card(
                child: Column(children: [
                  ListTile(
                    title: const Text('Có hiệu lực từ'),
                    trailing: Text('${current['effectiveDate'] ?? 'Chưa rõ'}'),
                  ),
                  ListTile(
                    title: const Text('Nguồn'),
                    trailing: Text('${current['source']}'),
                  ),
                  ListTile(
                    title: const Text('Kỳ trước'),
                    trailing: Text(current['previousPrice'] == null
                        ? 'Chưa có dữ liệu'
                        : formatPrice(current['previousPrice'] as num, unit)),
                  ),
                ]),
              ),
              FilledButton.icon(
                onPressed: () => context.go('/analytics'),
                icon: const Icon(Icons.show_chart),
                label: const Text('Xem biểu đồ'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    context.go('/calculator?fuel=$code&region=$region'),
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Tính chi phí nhiên liệu này'),
              ),
            ]);
          },
        ),
      );
}

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String fuel = 'E10_RON_95_III';
  String period = '30d';
  String region = 'REGION_1';
  bool comparisonMode = false;
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<Map<String, dynamic>> _load() => comparisonMode
      ? api.cachedGet('/api/v1/analytics/compare',
          query: {'region': region, 'unit': 'liter'})
      : api.cachedGet('/api/v1/history',
          query: {'fuelCode': fuel, 'region': region, 'period': period});

  void _update(VoidCallback change) {
    setState(() {
      change();
      future = _load();
    });
  }

  void _retry() => _update(() {});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Biểu đồ & phân tích')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorState(
                message: 'Không tải được lịch sử giá. Thử tải lại sau.',
                retry: _retry,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rawData = snapshot.data!['data'];
            if (comparisonMode) {
              final fuels = (rawData as List? ?? []).cast<Map>();
              return ListView(padding: const EdgeInsets.all(16), children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Biểu đồ giá')),
                    ButtonSegment(
                        value: true, label: Text('So sánh nhiên liệu')),
                  ],
                  selected: {true},
                  onSelectionChanged: (_) =>
                      _update(() => comparisonMode = false),
                ),
                const SizedBox(height: 12),
                if (fuels.isEmpty)
                  const EmptyState(message: 'Chưa có giá để so sánh.'),
                if (fuels.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        height: 300,
                        child: BarChart(BarChartData(
                          barGroups: [
                            for (var index = 0; index < fuels.length; index++)
                              BarChartGroupData(x: index, barRods: [
                                BarChartRodData(
                                    toY: (fuels[index]['currentPrice'] as num)
                                        .toDouble(),
                                    color: green,
                                    width: 18,
                                    borderRadius: BorderRadius.circular(4)),
                              ]),
                          ],
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index < 0 || index >= fuels.length) {
                                    return const SizedBox.shrink();
                                  }
                                  return SideTitleWidget(
                                      meta: meta,
                                      child:
                                          Text('${fuels[index]['fuelCode']}'));
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                          ),
                        )),
                      ),
                    ),
                  ),
                const Notice(
                    text:
                        'Chỉ nhiên liệu bán theo lít được so sánh cùng đơn vị.'),
              ]);
            }
            final data = rawData as Map;
            final rows = (data['items'] as List? ?? []).cast<Map>();
            final prices =
                rows.map((row) => (row['price'] as num).toDouble()).toList();
            final lowestPrice = prices.isEmpty
                ? 0.0
                : prices.reduce((left, right) => left < right ? left : right);
            final highestPrice = prices.isEmpty
                ? 1.0
                : prices.reduce((left, right) => left > right ? left : right);
            final yPadding =
                (highestPrice - lowestPrice) * 0.15 > highestPrice * 0.01
                    ? (highestPrice - lowestPrice) * 0.15
                    : (highestPrice == 0 ? 1.0 : highestPrice * 0.01);
            return ListView(padding: const EdgeInsets.all(16), children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Biểu đồ giá')),
                  ButtonSegment(value: true, label: Text('So sánh nhiên liệu')),
                ],
                selected: {false},
                onSelectionChanged: (_) => _update(() => comparisonMode = true),
              ),
              DropdownButtonFormField<String>(
                initialValue: fuel,
                decoration: const InputDecoration(labelText: 'Nhiên liệu'),
                items: const [
                  'E10_RON_95_III',
                  'E10_RON_95_V',
                  'RON_95_III',
                  'RON_95_V',
                  'E5_RON_92',
                  'DIESEL_001S',
                  'DIESEL_005S',
                  'KEROSENE'
                ]
                    .map((code) => DropdownMenuItem(
                        value: code, child: Text(titleOf(code))))
                    .toList(),
                onChanged: (value) => _update(() => fuel = value!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: region,
                decoration: const InputDecoration(labelText: 'Khu vực'),
                items: const [
                  DropdownMenuItem(value: 'REGION_1', child: Text('Vùng 1')),
                  DropdownMenuItem(value: 'REGION_2', child: Text('Vùng 2')),
                ],
                onChanged: (value) => _update(() => region = value!),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final entry in const {
                  '7d': '7 ngày',
                  '30d': '1 tháng',
                  '1y': '1 năm',
                  '3y': '3 năm',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: period == entry.key,
                    onSelected: (_) => _update(() => period = entry.key),
                  ),
              ]),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: rows.isEmpty
                      ? const SizedBox(
                          height: 240,
                          child: Center(
                              child: Text('Chưa có mốc giá lịch sử để vẽ')))
                      : Column(children: [
                          SizedBox(
                            height: 270,
                            child: LineChart(LineChartData(
                              minX: 0,
                              maxX: rows.length > 1 ? rows.length - 1 : 1,
                              minY: (lowestPrice - yPadding)
                                  .clamp(0, double.infinity)
                                  .toDouble(),
                              maxY: highestPrice + yPadding,
                              gridData: const FlGridData(show: true),
                              titlesData: FlTitlesData(
                                leftTitles: const AxisTitles(
                                    sideTitles: SideTitles(
                                        showTitles: true, reservedSize: 56)),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    interval: rows.length > 5
                                        ? (rows.length - 1) / 4
                                        : 1,
                                    reservedSize: 34,
                                    getTitlesWidget: (value, meta) {
                                      final index = value.round();
                                      if ((value - index).abs() > 0.001 ||
                                          index < 0 ||
                                          index >= rows.length) {
                                        return const SizedBox.shrink();
                                      }
                                      return SideTitleWidget(
                                        meta: meta,
                                        child: Text(
                                          formatEffectiveDate(
                                            rows[index]['effectiveDate'] ??
                                                rows[index]['effectiveAt'],
                                          ),
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false)),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  isStepLineChart: true,
                                  spots: [
                                    for (var i = 0; i < rows.length; i++)
                                      FlSpot(i.toDouble(),
                                          (rows[i]['price'] as num).toDouble())
                                  ],
                                  color: green,
                                  barWidth: rows.length > 1 ? 3 : 0,
                                  dotData: const FlDotData(show: true),
                                  belowBarData: BarAreaData(
                                      show: rows.length > 1, color: greenLight),
                                )
                              ],
                            )),
                          ),
                          if (rows.length < 2)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                  'Mới có 1 mốc giá đã xác nhận; biểu đồ xu hướng sẽ hiện khi có thêm kỳ giá.'),
                            ),
                        ]),
                ),
              ),
              if (data['coverageComplete'] != true)
                const Notice(
                    text:
                        'Lịch sử hiện chưa đầy đủ. Biểu đồ chỉ dùng các mốc giá đã ghi nhận.'),
              Text(
                  'Phạm vi dữ liệu: ${data['earliestAvailableDate'] ?? '—'} → ${data['latestAvailableDate'] ?? '—'}'),
            ]);
          },
        ),
      );
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key, this.initialFuel, this.initialRegion});
  final String? initialFuel;
  final String? initialRegion;
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  final distance = TextEditingController(text: '100');
  final consumption = TextEditingController(text: '7.5');
  final monthly = TextEditingController(text: '1200');
  final price = TextEditingController();
  late String fuel = widget.initialFuel ?? 'E10_RON_95_III';
  late String region = widget.initialRegion ?? 'REGION_1';
  FuelEstimate? result;
  String? error;

  @override
  void initState() {
    super.initState();
    _restoreSettings();
  }

  Future<void> _restoreSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString('calculator.last') ?? '').split('|');
    if (!mounted) return;
    setState(() {
      if (widget.initialRegion == null) {
        region = prefs.getString('region.default') ?? 'REGION_1';
      }
      if (saved.length == 5) {
        distance.text = saved[0];
        consumption.text = saved[1];
        monthly.text = saved[2];
        price.text = saved[3];
        if (widget.initialFuel == null) fuel = saved[4];
      }
    });
  }

  Future<void> loadCurrentPrice() async {
    try {
      final response = await api
          .cachedGet('/api/v1/prices/latest', query: {'region': region});
      final rows = (response['data'] as List? ?? []).cast<Map>();
      final matches = rows.where((row) => row['fuelCode'] == fuel);
      final current = matches.isEmpty ? null : matches.first;
      if (current == null || current['unit'] != 'liter') {
        throw StateError('Chưa có giá theo lít cho nhiên liệu đã chọn.');
      }
      price.text = '${current['currentPrice']}';
      setState(() => error = null);
    } on Object catch (exception) {
      setState(() => error = exception is StateError
          ? exception.message
          : 'Không lấy được giá hiện tại. Bạn có thể nhập giá thủ công.');
    }
  }

  Future<void> calculate() async {
    try {
      final parsedPrice = double.tryParse(price.text.replaceAll(',', '.'));
      if (parsedPrice == null) throw ArgumentError('Nhập giá nhiên liệu.');
      final estimate = FuelEstimate.calculate(
        distanceKm: double.parse(distance.text.replaceAll(',', '.')),
        consumptionPer100Km:
            double.parse(consumption.text.replaceAll(',', '.')),
        pricePerLiter: parsedPrice,
        monthlyDistanceKm: double.parse(monthly.text.replaceAll(',', '.')),
      );
      setState(() {
        result = estimate;
        error = null;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('calculator.last',
          '${distance.text}|${consumption.text}|${monthly.text}|${price.text}|$fuel');
    } on Object catch (exception) {
      setState(() {
        error = exception is ArgumentError
            ? exception.message.toString()
            : 'Vui lòng nhập các thông số hợp lệ.';
      });
    }
  }

  @override
  void dispose() {
    distance.dispose();
    consumption.dispose();
    monthly.dispose();
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tính chi phí nhiên liệu')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<String>(
            initialValue: fuel,
            decoration: const InputDecoration(labelText: 'Loại nhiên liệu'),
            items: const [
              'E10_RON_95_III',
              'E10_RON_95_V',
              'RON_95_III',
              'E5_RON_92',
              'DIESEL_001S',
              'DIESEL_005S',
              'KEROSENE',
            ]
                .map((code) =>
                    DropdownMenuItem(value: code, child: Text(titleOf(code))))
                .toList(),
            onChanged: (value) => setState(() => fuel = value!),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: region,
            decoration: const InputDecoration(labelText: 'Khu vực'),
            items: const [
              DropdownMenuItem(value: 'REGION_1', child: Text('Vùng 1')),
              DropdownMenuItem(value: 'REGION_2', child: Text('Vùng 2')),
            ],
            onChanged: (value) => setState(() => region = value!),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: loadCurrentPrice,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Dùng giá mới nhất'),
            ),
          ),
          for (final entry in {
            'Giá nhiên liệu (đ/lít)': price,
            'Mức tiêu hao (L/100 km)': consumption,
            'Quãng đường (km)': distance,
            'Quãng đường mỗi tháng (km)': monthly,
          }.entries)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: TextField(
                controller: entry.value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: entry.key),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
              onPressed: calculate,
              icon: const Icon(Icons.calculate),
              label: const Text('Tính chi phí')),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          if (result != null)
            Card(
              color: greenLight,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Text('Chi phí cho quãng đường'),
                  Text('${money.format(result!.totalCost)} đ',
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: greenDark)),
                  Text(
                      'Lượng nhiên liệu: ${result!.liters.toStringAsFixed(2)} L'),
                  Text('Chi phí mỗi km: ${money.format(result!.costPerKm)} đ'),
                  Text(
                      'Ước tính theo tháng: ${money.format(result!.monthlyCost)} đ'),
                  Text(
                      'Ước tính theo năm: ${money.format(result!.yearlyCost)} đ'),
                ]),
              ),
            ),
          const Notice(
              text: 'Dầu mazut bán theo kg không dùng trong bộ tính theo lít.'),
        ]),
      );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String region = 'REGION_1';
  PushNotificationPreferences _notificationPreferences =
      PushNotificationPreferences.defaults('REGION_1');
  Map<String, dynamic>? _metadata;
  String? _appVersion;
  bool _loading = true;
  bool _savingNotifications = false;
  bool _metadataUnavailable = false;

  bool get _serverPushAvailable =>
      _metadata?['_cached'] != true &&
      _metadata?['notificationsAvailable'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRegion = prefs.getString('region.default') ?? 'REGION_1';
    final notificationPreferences = await pushNotifications.loadPreferences(
      fallbackRegion: savedRegion,
    );
    final packageInfo = await PackageInfo.fromPlatform();
    Map<String, dynamic>? metadata;
    var metadataUnavailable = false;
    try {
      metadata = await api.cachedGet('/api/v1/metadata');
    } on Object {
      metadataUnavailable = true;
    }
    if (!mounted) return;
    setState(() {
      region = savedRegion;
      _notificationPreferences = notificationPreferences;
      _metadata = metadata;
      _metadataUnavailable = metadataUnavailable;
      _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
      _loading = false;
    });
  }

  Future<void> _chooseRegion(String? selected) async {
    if (selected == null || selected == region) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('region.default', selected);
    if (mounted) setState(() => region = selected);
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    if (enabled &&
        (!_serverPushAvailable || !pushNotifications.isFirebaseReady)) {
      await _showFirebaseSetup();
      return;
    }
    if (enabled && _notificationPreferences.fuelCodes.isEmpty) {
      _showMessage('Hãy chọn ít nhất một loại nhiên liệu.');
      return;
    }
    setState(() => _savingNotifications = true);
    try {
      if (enabled) {
        await pushNotifications.enable(_notificationPreferences);
      } else {
        await pushNotifications.disable(_notificationPreferences);
      }
      if (mounted) {
        setState(() {
          _notificationPreferences =
              _notificationPreferences.copyWith(enabled: enabled);
          _savingNotifications = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          if (!enabled) {
            _notificationPreferences =
                _notificationPreferences.copyWith(enabled: false);
          }
          _savingNotifications = false;
        });
        _showMessage(_friendlyPushError(error));
      }
    }
  }

  Future<void> _saveNotificationPreferences(
    PushNotificationPreferences next,
  ) async {
    final previous = _notificationPreferences;
    setState(() => _notificationPreferences = next);
    try {
      await pushNotifications.savePreferences(next);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _notificationPreferences = previous);
      _showMessage(_friendlyPushError(error));
    }
  }

  Future<void> _showFirebaseSetup() async {
    final appMissing = !pushNotifications.isFirebaseReady;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appMissing
            ? 'Ứng dụng chưa cấu hình Firebase'
            : _metadataUnavailable || _metadata?['_cached'] == true
                ? 'Chưa kiểm tra được máy chủ'
                : 'Máy chủ chưa bật Firebase'),
        content: SingleChildScrollView(
          child: Text(appMissing
              ? 'Cần tạo Firebase project, đăng ký ứng dụng Android với mã vn.giaxang.gia_xang_dau, bật Cloud Messaging rồi truyền FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID và FIREBASE_PROJECT_ID khi chạy/build app. Xem mobile/FIREBASE_SETUP.md để làm từng bước.'
              : _metadataUnavailable || _metadata?['_cached'] == true
                  ? 'Chưa lấy được trạng thái máy chủ. Hãy kiểm tra kết nối API rồi mở lại Cài đặt.'
                  : 'App đã có Firebase, nhưng backend chưa bật FCM. Cần cấu hình FIREBASE_ENABLED, FIREBASE_PROJECT_ID và tài khoản dịch vụ Firebase ở backend. Không đưa khóa tài khoản dịch vụ vào ứng dụng mobile.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _friendlyPushError(Object error) {
    if (error is StateError) return error.message.toString();
    return 'Không lưu được cài đặt thông báo. Kiểm tra kết nối rồi thử lại.';
  }

  String _lastSyncLabel() {
    final raw = _metadata?['lastSuccessfulSyncAt'];
    if (raw is! String) return 'Chưa có lần đồng bộ thành công';
    final date = DateTime.tryParse(raw);
    if (date == null) return 'Thời gian đồng bộ không hợp lệ';
    return DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
  }

  String _syncStatus() {
    if (_metadataUnavailable && _metadata == null) {
      return 'Không kết nối được máy chủ';
    }
    final raw = _metadata?['lastSuccessfulSyncAt'];
    if (raw is! String) return 'Chưa có dữ liệu đồng bộ';
    final date = DateTime.tryParse(raw);
    if (date == null) return 'Không xác định được trạng thái dữ liệu';
    return DateTime.now().difference(date.toLocal()) <= const Duration(hours: 6)
        ? 'Đang cập nhật'
        : 'Lần đồng bộ gần nhất đã quá 6 giờ';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Cài đặt'),
          actions: [
            IconButton(
              tooltip: 'Tải lại trạng thái',
              onPressed: _loading
                  ? null
                  : () async {
                      setState(() {
                        _loading = true;
                        _metadataUnavailable = false;
                      });
                      await _load();
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      const Icon(Icons.location_on, color: green),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Khu vực mặc định',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      DropdownButton<String>(
                        value: region,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                              value: 'REGION_1', child: Text('Vùng 1')),
                          DropdownMenuItem(
                              value: 'REGION_2', child: Text('Vùng 2')),
                        ],
                        onChanged: _chooseRegion,
                      ),
                    ]),
                  ),
                ),
                const _SettingsSectionTitle('Dữ liệu giá'),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: Icon(
                        _syncStatus() == 'Đang cập nhật'
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined,
                        color: green,
                      ),
                      title: const Text('Nguồn dữ liệu'),
                      subtitle: Text(
                        '${_metadata?['source'] ?? 'VietFuelAPI'}'
                        '${_metadata?['upstreamSource'] == null ? '' : ' • ${_metadata?['upstreamSource']}'}\n'
                        'Trạng thái: ${_syncStatus()}\n'
                        'Đồng bộ gần nhất: ${_lastSyncLabel()}',
                      ),
                      isThreeLine: true,
                    ),
                    const Divider(height: 1, indent: 56),
                    const ListTile(
                      leading: Icon(Icons.verified_outlined, color: green),
                      title: Text('Cách hiển thị giá'),
                      subtitle: Text(
                        'Chỉ hiển thị giá máy chủ xác nhận. Giá từng nguồn '
                        'được giữ riêng; xăng dầu tính theo lít, mazut theo kg.',
                      ),
                    ),
                  ]),
                ),
                const _SettingsSectionTitle('Thông báo giá mới'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(
                            _notificationPreferences.enabled
                                ? Icons.notifications_active_outlined
                                : Icons.notifications_off_outlined,
                            color: green,
                          ),
                          title: const Text('Nhận thông báo khi giá thay đổi'),
                          subtitle: Text(
                            _savingNotifications
                                ? 'Đang lưu cài đặt…'
                                : _metadataUnavailable ||
                                        _metadata?['_cached'] == true
                                    ? 'Chưa xác minh được trạng thái máy chủ'
                                    : !_serverPushAvailable
                                        ? 'Firebase chưa sẵn sàng ở máy chủ'
                                        : !pushNotifications.isFirebaseReady
                                            ? 'Bản ứng dụng chưa nối Firebase'
                                            : _notificationPreferences.enabled
                                                ? 'Đã bật trên thiết bị này'
                                                : 'Đang tắt',
                          ),
                          value: _notificationPreferences.enabled,
                          onChanged: _savingNotifications
                              ? null
                              : _setNotificationsEnabled,
                        ),
                        if (!_serverPushAvailable ||
                            !pushNotifications.isFirebaseReady)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _showFirebaseSetup,
                              icon: const Icon(Icons.info_outline),
                              label: const Text('Cách cấu hình Firebase'),
                            ),
                          ),
                        const Divider(),
                        DropdownButtonFormField<String>(
                          initialValue: _notificationPreferences.region,
                          decoration: const InputDecoration(
                            labelText: 'Theo dõi giá tại',
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'REGION_1', child: Text('Vùng 1')),
                            DropdownMenuItem(
                                value: 'REGION_2', child: Text('Vùng 2')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              _saveNotificationPreferences(
                                _notificationPreferences.copyWith(
                                    region: value),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        const Text('Loại nhiên liệu'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final code in allNotificationFuelCodes)
                              FilterChip(
                                label: Text(notificationFuelNames[code]!),
                                selected: _notificationPreferences.fuelCodes
                                    .contains(code),
                                onSelected: (selected) {
                                  final codes = Set<String>.from(
                                      _notificationPreferences.fuelCodes);
                                  if (selected) {
                                    codes.add(code);
                                  } else {
                                    codes.remove(code);
                                  }
                                  _saveNotificationPreferences(
                                    _notificationPreferences.copyWith(
                                        fuelCodes: codes),
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('Thông báo khi giá'),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                                value: 'increase', label: Text('Tăng')),
                            ButtonSegment(
                                value: 'decrease', label: Text('Giảm')),
                            ButtonSegment(value: 'both', label: Text('Cả hai')),
                          ],
                          selected: {_notificationPreferences.direction},
                          onSelectionChanged: (selected) {
                            _saveNotificationPreferences(
                              _notificationPreferences.copyWith(
                                  direction: selected.first),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const _SettingsSectionTitle('Ứng dụng và quyền riêng tư'),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading:
                          const Icon(Icons.privacy_tip_outlined, color: green),
                      title: const Text('Quyền riêng tư'),
                      subtitle: const Text(
                        'Không cần tài khoản hoặc vị trí. Khi bật thông báo, '
                        'mã thiết bị Firebase cùng khu vực và loại nhiên liệu '
                        'đã chọn được lưu để gửi đúng tin giá.',
                      ),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.info_outline, color: green),
                      title: const Text('Giá Xăng Dầu'),
                      subtitle: Text('Phiên bản ${_appVersion ?? '—'}'),
                    ),
                  ]),
                ),
              ]),
      );
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: greenDark, fontWeight: FontWeight.bold),
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.retry});
  final String message;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined,
                size: 44, color: Colors.blueGrey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (retry != null)
              TextButton(onPressed: retry, child: const Text('Thử lại')),
          ]),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(26),
        child: Text(message, textAlign: TextAlign.center),
      );
}

class Notice extends StatelessWidget {
  const Notice({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Card(
        color: greenLight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.info_outline, color: green),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ]),
        ),
      );
}
