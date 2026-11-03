import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';

Future<void> showServerSettings(BuildContext context, AppState state) async {
  final controller = TextEditingController(
    text: state.usesEmbedded
        ? (state.lastRemoteBase ?? '')
        : state.apiBase,
  );
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var busy = false;
      String? error;

      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> finish(Future<String?> Function() action) async {
            if (busy) return;
            setDialogState(() {
              busy = true;
              error = null;
            });
            final err = await action();
            if (!context.mounted) return;
            if (err != null) {
              setDialogState(() {
                busy = false;
                error = err;
              });
            } else {
              Navigator.of(dialogContext).pop();
            }
          }

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text(
              '数据服务',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.embeddedSupported) ...[
                      _EmbeddedCard(
                        state: state,
                        busy: busy,
                        onUse: () => finish(state.useEmbeddedBackend),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Expanded(child: Divider(color: AppColors.border)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              '或连接电脑上的后端',
                              style: TextStyle(fontSize: 10.5, color: AppColors.faint),
                            ),
                          ),
                          Expanded(child: Divider(color: AppColors.border)),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      const Text(
                        '桌面 / Web 版需要先启动电脑上的后端。手机 App 默认使用内置引擎，无需设置。',
                        style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.6),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const Text(
                      '填写运行后端的电脑地址，例如 http://192.168.1.10:8787。'
                      '手机与电脑需要在同一个局域网。',
                      style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.6),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'http://192.168.1.10:8787',
                        prefixIcon: Icon(Icons.dns_outlined, size: 18, color: AppColors.faint),
                        isDense: true,
                      ),
                      onSubmitted: (_) => finish(() => state.setApiBase(controller.text)),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '当前：${state.apiBaseLabel}',
                      style: const TextStyle(fontSize: 11, color: AppColors.faint),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.red,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () => finish(() => state.setApiBase(controller.text)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: const Color(0xFF241800),
                ),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF241800),
                        ),
                      )
                    : const Text('保存并连接'),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
}

class _EmbeddedCard extends StatelessWidget {
  final AppState state;
  final bool busy;
  final VoidCallback onUse;

  const _EmbeddedCard({
    required this.state,
    required this.busy,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    final active = state.usesEmbedded;
    final ready = state.hasEmbedded;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      decoration: BoxDecoration(
        color: active
            ? AppColors.accent.withValues(alpha: 0.08)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: active
              ? AppColors.accent.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? Icons.offline_bolt_outlined : Icons.error_outline,
            size: 20,
            color: ready ? AppColors.accent : AppColors.red,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '内置引擎',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: (ready ? AppColors.green : AppColors.red)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        ready ? '离线可用' : '不可用',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: ready ? AppColors.green : AppColors.red,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  ready
                      ? '后端与历史数据库随 App 运行，不需要电脑或网络。数据保存在本机，可随时同步更新。'
                      : (state.embeddedError ?? '内置引擎未能启动。'),
                  style: TextStyle(
                    fontSize: 11,
                    color: ready ? AppColors.muted : AppColors.red,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (active)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.check_circle, size: 18, color: AppColors.accent),
            )
          else
            TextButton(
              onPressed: ready && !busy ? onUse : null,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('使用', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
