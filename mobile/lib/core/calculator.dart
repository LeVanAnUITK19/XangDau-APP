class FuelEstimate {
  const FuelEstimate(
      {required this.liters,
      required this.totalCost,
      required this.costPerKm,
      required this.monthlyCost,
      required this.yearlyCost});
  final double liters, totalCost, costPerKm, monthlyCost, yearlyCost;
  static FuelEstimate calculate(
      {required double distanceKm,
      required double consumptionPer100Km,
      required double pricePerLiter,
      required double monthlyDistanceKm}) {
    if ([distanceKm, consumptionPer100Km, pricePerLiter, monthlyDistanceKm]
        .any((v) => !v.isFinite || v < 0))
      throw ArgumentError('Thông số phải là số không âm');
    final liters = distanceKm * consumptionPer100Km / 100;
    final total = liters * pricePerLiter;
    final month = monthlyDistanceKm * consumptionPer100Km / 100 * pricePerLiter;
    return FuelEstimate(
        liters: liters,
        totalCost: total,
        costPerKm: distanceKm > 0 ? total / distanceKm : 0,
        monthlyCost: month,
        yearlyCost: month * 12);
  }
}
