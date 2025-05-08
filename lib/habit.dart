class Habit {
  String title;
  String unit;          // 'km' 或 'kg'
  double goal;
  double currentValue;
  List<double> quickAdds;
  bool usePedometer;    // ★ 是否走计步器，默认 false

  Habit({
    required this.title,
    required this.unit,
    required this.goal,
    required this.currentValue,
    required this.quickAdds,
    this.usePedometer = false,   // 新字段
  });

  Habit copyWith({double? currentValue}) => Habit(
    title: title,
    unit: unit,
    goal: goal,
    currentValue: currentValue ?? this.currentValue,
    quickAdds: quickAdds,
    usePedometer: usePedometer,
  );
}
