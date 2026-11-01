String formatMeasurement(double value, {int decimals = 4}) {
  if (value != 0 && value.abs() < 0.0001) {
    return value.toStringAsExponential(3);
  }

  return value.toStringAsFixed(decimals);
}
