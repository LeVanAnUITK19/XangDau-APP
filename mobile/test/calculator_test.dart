import 'package:flutter_test/flutter_test.dart';
import 'package:gia_xang_dau/core/calculator.dart';

void main() {
  test('computes expected trip and monthly estimates', () {
    final result = FuelEstimate.calculate(
        distanceKm: 100,
        consumptionPer100Km: 7.5,
        pricePerLiter: 22980,
        monthlyDistanceKm: 1200);
    expect(result.liters, 7.5);
    expect(result.totalCost, 172350);
    expect(result.yearlyCost, 24818400);
  });
  test('rejects negative and non-finite inputs', () {
    expect(
        () => FuelEstimate.calculate(
            distanceKm: -1,
            consumptionPer100Km: 7.5,
            pricePerLiter: 22980,
            monthlyDistanceKm: 0),
        throwsArgumentError);
    expect(
        () => FuelEstimate.calculate(
            distanceKm: double.nan,
            consumptionPer100Km: 7.5,
            pricePerLiter: 22980,
            monthlyDistanceKm: 0),
        throwsArgumentError);
  });
  test('zero distance produces zero per kilometre result', () {
    final result = FuelEstimate.calculate(
        distanceKm: 0,
        consumptionPer100Km: 7.5,
        pricePerLiter: 22980,
        monthlyDistanceKm: 0);
    expect(result.costPerKm, 0);
  });
}
