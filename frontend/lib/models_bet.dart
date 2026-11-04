
/// One personal ticket record: a hand-picked set of numbers against a
/// specific issue of a specific game.
class Bet {
  final int id;
  final String game;
  final String gameName;
  final String issue;
  /// Draw date of the issue once it has been drawn; empty while pending.
  final String date;
  final List<int> primary;
  final List<int> secondary;
  final int multiple;
  final String note;
  final BetStatus status;
  final int tier;
  final String tierName;
  final int primaryHits;
  final int secondaryHits;
  final List<int> matchedPrimary;
  final List<int> matchedSecondary;
  /// Prize of one ticket from the config table.
  final double amount;
  /// Real payout the user recorded, when known.
  final double? actualAmount;
  /// True while [amount] is a tier-1/2 estimate.
  final bool estimated;
  /// Total stake: multiple x ticket price.
  final double cost;
  /// Total payout: multiple x (actualAmount ?? amount).
  final double payout;
  final String createdAt;
  final String? checkedAt;

  const Bet({
    required this.id,
    required this.game,
    required this.gameName,
    required this.issue,
    required this.date,
    required this.primary,
    required this.secondary,
    required this.multiple,
    required this.note,
    required this.status,
    required this.tier,
    required this.tierName,
    required this.primaryHits,
    required this.secondaryHits,
    required this.matchedPrimary,
    required this.matchedSecondary,
    required this.amount,
    required this.actualAmount,
    required this.estimated,
    required this.cost,
    required this.payout,
    required this.createdAt,
    required this.checkedAt,
  });

  bool get won => status == BetStatus.won;
  bool get pending => status == BetStatus.pending;

  /// Amount actually counted in the ledger, honouring the user override.
  double get effectiveAmount => actualAmount ?? amount;

  factory Bet.fromJson(Map<String, dynamic> json) {
    return Bet(
      id: (json['id'] as num?)?.toInt() ?? 0,
      game: json['game'] as String? ?? '',
      gameName: json['game_name'] as String? ?? '',
      issue: json['issue'] as String? ?? '',
      date: json['date'] as String? ?? '',
      primary: _intList(json['primary']),
      secondary: _intList(json['secondary']),
      multiple: (json['multiple'] as num?)?.toInt() ?? 1,
      note: json['note'] as String? ?? '',
      status: BetStatus.fromJson(json['status'] as String?),
      tier: (json['tier'] as num?)?.toInt() ?? 0,
      tierName: json['tier_name'] as String? ?? '未中奖',
      primaryHits: (json['primary_hits'] as num?)?.toInt() ?? 0,
      secondaryHits: (json['secondary_hits'] as num?)?.toInt() ?? 0,
      matchedPrimary: _intList(json['matched_primary']),
      matchedSecondary: _intList(json['matched_secondary']),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      actualAmount: (json['actual_amount'] as num?)?.toDouble(),
      estimated: json['estimated'] as bool? ?? false,
      cost: (json['cost'] as num?)?.toDouble() ?? 0,
      payout: (json['payout'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] as String? ?? '',
      checkedAt: json['checked_at'] as String?,
    );
  }
}

/// Lifecycle of one bet. Mirrors the backend enum.
enum BetStatus {
  pending,
  won,
  lost;

  static BetStatus fromJson(String? value) {
    switch (value) {
      case 'won':
        return BetStatus.won;
      case 'lost':
        return BetStatus.lost;
      default:
        return BetStatus.pending;
    }
  }

  String get label => switch (this) {
        BetStatus.pending => '待开奖',
        BetStatus.won => '已中奖',
        BetStatus.lost => '未中奖',
      };
}

/// Ledger totals for a set of bets.
class BetSummary {
  final int total;
  final int pending;
  final int won;
  final int lost;
  final double cost;
  final double payout;
  final double net;
  /// How much of [payout] rests on tier-1/2 estimates.
  final double estimatedPayout;
  final List<TierCount> byTier;

  const BetSummary({
    required this.total,
    required this.pending,
    required this.won,
    required this.lost,
    required this.cost,
    required this.payout,
    required this.net,
    required this.estimatedPayout,
    required this.byTier,
  });

  int get settled => won + lost;

  factory BetSummary.fromJson(Map<String, dynamic> json) {
    return BetSummary(
      total: (json['total'] as num?)?.toInt() ?? 0,
      pending: (json['pending'] as num?)?.toInt() ?? 0,
      won: (json['won'] as num?)?.toInt() ?? 0,
      lost: (json['lost'] as num?)?.toInt() ?? 0,
      cost: (json['cost'] as num?)?.toDouble() ?? 0,
      payout: (json['payout'] as num?)?.toDouble() ?? 0,
      net: (json['net'] as num?)?.toDouble() ?? 0,
      estimatedPayout: (json['estimated_payout'] as num?)?.toDouble() ?? 0,
      byTier: (json['by_tier'] as List? ?? const [])
          .map((e) => TierCount.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TierCount {
  final String game;
  final String gameName;
  final int tier;
  final String tierName;
  final int count;
  /// Prize of one ticket at this tier.
  final double amount;
  /// Sum over bets, honouring `actual_amount`.
  final double payout;

  const TierCount({
    required this.game,
    required this.gameName,
    required this.tier,
    required this.tierName,
    required this.count,
    required this.amount,
    required this.payout,
  });

  factory TierCount.fromJson(Map<String, dynamic> json) {
    return TierCount(
      game: json['game'] as String? ?? '',
      gameName: json['game_name'] as String? ?? '',
      tier: (json['tier'] as num?)?.toInt() ?? 0,
      tierName: json['tier_name'] as String? ?? '未中奖',
      count: (json['count'] as num?)?.toInt() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      payout: (json['payout'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Outcome of a checking pass.
class BetCheckResult {
  final int settled;
  final int won;
  final int stillPending;
  final int skipped;

  const BetCheckResult({
    required this.settled,
    required this.won,
    required this.stillPending,
    required this.skipped,
  });

  factory BetCheckResult.fromJson(Map<String, dynamic> json) {
    return BetCheckResult(
      settled: (json['settled'] as num?)?.toInt() ?? 0,
      won: (json['won'] as num?)?.toInt() ?? 0,
      stillPending: (json['still_pending'] as num?)?.toInt() ?? 0,
      skipped: (json['skipped'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Result of saving one or more bets.
class BetSaveResult {
  final int inserted;
  final int duplicates;
  final BetCheckResult checked;

  const BetSaveResult({
    required this.inserted,
    required this.duplicates,
    required this.checked,
  });

  factory BetSaveResult.fromJson(Map<String, dynamic> json) {
    return BetSaveResult(
      inserted: (json['inserted'] as num?)?.toInt() ?? 0,
      duplicates: (json['duplicates'] as num?)?.toInt() ?? 0,
      checked: BetCheckResult.fromJson(
          (json['checked'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{}),
    );
  }
}

List<int> _intList(dynamic value) {
  if (value is! List) return const [];
  return value.map((e) => (e as num).toInt()).toList();
}
