import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_http_repository.dart';
import 'providers.dart';
import 'repository.dart';
import 'settings.dart';
import 'theme.dart';
import 'widgets.dart';

/// Modal that lets the operator type the conveyor's IP address and probes it
/// before saving. Returns `true` when a new address was connected.
Future<bool> showAddressEntryDialog(
  BuildContext context, {
  String? initial,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _AddressEntryDialog(initial: initial),
  );
  return result ?? false;
}

class _AddressEntryDialog extends ConsumerStatefulWidget {
  const _AddressEntryDialog({this.initial});

  final String? initial;

  @override
  ConsumerState<_AddressEntryDialog> createState() =>
      _AddressEntryDialogState();
}

class _AddressEntryDialogState extends ConsumerState<_AddressEntryDialog> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ip = LocalHttpRepository.normalizeBaseUrl(_controller.text);
    if (ip.isEmpty) {
      setState(() => _error = 'Enter the IP address shown on the OLED.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final probe = LocalHttpRepository(baseUrl: ip);
    try {
      await probe.fetchStatus();
      if (!mounted) return;
      ref.read(configProvider.notifier)
        ..setEspIp(ip)
        ..setMode(ConnectionMode.local);
      Navigator.of(context).pop(true);
    } on ConveyorException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not reach that address.');
      }
    } finally {
      await probe.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SubHeaderStrip(
              title: 'Conveyor address',
              trailing: 'NET_LINK',
              icon: Icons.lan_outlined,
              tint: p.textSecondary,
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Type the IP shown on the conveyor OLED, then test the link.',
                    style: AppText.body.copyWith(color: p.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  InputWell(
                    controller: _controller,
                    hint: '192.168.1.50',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    onSubmitted: (_) => _busy ? null : _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, size: 16, color: p.fault),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: AppText.labelCaps
                                  .copyWith(color: p.fault, height: 1.3)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ActionButton.secondary(
                          label: 'Cancel',
                          height: 40,
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ActionButton.primary(
                          label: _busy ? 'Testing link...' : 'Test & connect',
                          height: 40,
                          onPressed: _busy ? null : _submit,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
