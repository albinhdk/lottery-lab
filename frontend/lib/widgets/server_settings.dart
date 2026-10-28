import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';

Future<void> showServerSettings(BuildContext context, AppState state) async {
  final controller = TextEditingController(text: state.apiBase);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var saving = false;
      String? error;

      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            if (saving) return;
            setDialogState(() {
              saving = true;
              error = null;
            });
            final err = await state.setApiBase(controller.text);
            if (!context.mounted) return;
            if (err != null) {
              setDialogState(() {
                saving = false;
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
              '服务器地址',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '手机需要和运行后端的电脑在同一个局域网。填写电脑的局域网地址，例如 '
                    'http://192.168.1.10:8787。保存后会立即重新连接。',
                    style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.6),
                  ),
                  const SizedBox(height: 14),
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
                    onSubmitted: (_) => save(),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '当前：${state.apiBase}',
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
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: saving ? null : save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: const Color(0xFF241800),
                ),
                child: saving
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
