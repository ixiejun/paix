import 'package:flutter/foundation.dart';

@immutable
class StrategyProduct {
  const StrategyProduct({
    required this.id,
    required this.name,
    required this.shortDescription,
    required this.riskNote,
    required this.performance3mPercentSeries,
    required this.annualizedReturnPercent,
    required this.investorCount,
    required this.aumUsd,
    required this.suitableFor,
    required this.notSuitableFor,
  });

  final String id;
  final String name;
  final String shortDescription;
  final String riskNote;

  final List<double> performance3mPercentSeries;

  final double? annualizedReturnPercent;
  final int? investorCount;
  final double? aumUsd;

  final List<String> suitableFor;
  final List<String> notSuitableFor;

  bool get hasPerformanceSeries => performance3mPercentSeries.length >= 2;

  double? get return3mPercent {
    if (!hasPerformanceSeries) return null;
    return performance3mPercentSeries.last - performance3mPercentSeries.first;
  }
}
