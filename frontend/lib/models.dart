class Draw {
  final String game;
  final String issue;
  final String date;
  final List<int> primary;
  final List<int> secondary;
  final int? sales;
  final int? pool;

  const Draw({
    required this.game,
    required this.issue,
    required this.date,
    required this.primary,
    required this.secondary,
    this.sales,
    this.pool,
  });

  factory Draw.fromJson(Map<String, dynamic> json) {
    return Draw(
      game: json['game'] as String? ?? '',
      issue: json['issue'] as String? ?? '',
      date: json['date'] as String? ?? '',
      primary: (json['primary'] as List? ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      secondary: (json['secondary'] as List? ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      sales: (json['sales'] as num?)?.toInt(),
      pool: (json['pool'] as num?)?.toInt(),
    );
  }
}

class GameInfo {
  final String id;
  final String name;
  final String primaryLabel;
  final int primaryCount;
  final int primaryMax;
  final String secondaryLabel;
  final int secondaryCount;
  final int secondaryMax;
  final double price;
  final String prizeNote;
  final int count;
  final Draw? latest;
  final String? firstDate;
  final String? lastDate;

  const GameInfo({
    required this.id,
    required this.name,
    required this.primaryLabel,
    required this.primaryCount,
    required this.primaryMax,
    required this.secondaryLabel,
    required this.secondaryCount,
    required this.secondaryMax,
    required this.price,
    required this.prizeNote,
    required this.count,
    this.latest,
    this.firstDate,
    this.lastDate,
  });

  factory GameInfo.fromJson(Map<String, dynamic> json) {
    return GameInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      primaryLabel: json['primary_label'] as String? ?? '主号码',
      primaryCount: (json['primary_count'] as num).toInt(),
      primaryMax: (json['primary_max'] as num).toInt(),
      secondaryLabel: json['secondary_label'] as String? ?? '特别号码',
      secondaryCount: (json['secondary_count'] as num).toInt(),
      secondaryMax: (json['secondary_max'] as num).toInt(),
      price: (json['price'] as num?)?.toDouble() ?? 2,
      prizeNote: json['prize_note'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      latest: json['latest'] == null
          ? null
          : Draw.fromJson(json['latest'] as Map<String, dynamic>),
      firstDate: json['first_date'] as String?,
      lastDate: json['last_date'] as String?,
    );
  }

  /// Exact jackpot probability denominator, e.g. 17,721,088 for 双色球.
  int get jackpotOdds {
    var c = 1.0;
    for (var i = 0; i < primaryCount; i++) {
      c = c * (primaryMax - i) / (i + 1);
    }
    var s = 1.0;
    for (var i = 0; i < secondaryCount; i++) {
      s = s * (secondaryMax - i) / (i + 1);
    }
    return (c * s).round();
  }
}

class StrategyInfo {
  final String id;
  final String label;
  final String description;

  const StrategyInfo({
    required this.id,
    required this.label,
    required this.description,
  });

  factory StrategyInfo.fromJson(Map<String, dynamic> json) {
    return StrategyInfo(
      id: json['id'] as String,
      label: json['label'] as String,
      description: json['description'] as String? ?? '',
    );
  }
}
