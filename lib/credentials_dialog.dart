// credentials_dialog.dart
//
// Login form shown on first launch. Credentials are checked against the
// Redis server and, if valid, saved to secure storage by GameModel.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'game_model.dart';

class CredentialsDialog extends StatefulWidget {
  const CredentialsDialog({super.key});

  @override
  State<CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<CredentialsDialog> {
  final _key = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (!_key.currentState!.validate()) return;
    setState(() { _busy = true; _err = null; });

    final model = Provider.of<GameModel>(context, listen: false);
    final ok = await model.tryLogin(
        _userCtrl.text.trim(), _passCtrl.text.trim());

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _err = 'Login failed. Check your credentials and network connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: AlertDialog(
          title: const Text('Sign in to the game server'),
          content: Form(
            key: _key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(hintText: 'Username'),
                  autocorrect: false,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(hintText: 'Password'),
                  obscureText: true,
                  autocorrect: false,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                if (_err != null) ...[
                  const SizedBox(height: 10),
                  Text(_err!,
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            _busy
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator())
                : TextButton(onPressed: _go, child: const Text('Submit')),
          ],
        ),
      ),
    );
  }
}