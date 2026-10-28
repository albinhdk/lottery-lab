import 'package:flutter/material.dart';

/// Like [IndexedStack] but only builds a page the first time it is visited.
/// Keeps visited pages alive so search state / backtest results survive tab
/// switches, while avoiding a burst of API calls when the app starts.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late final Set<int> _activated = {widget.index};

  @override
  void didUpdateWidget(covariant LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activated.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          Offstage(
            offstage: i != widget.index,
            child: TickerMode(
              enabled: i == widget.index,
              child: _activated.contains(i)
                  ? widget.children[i]
                  : const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}
