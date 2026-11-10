import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'email_confirmation.dart';
import 'haras_logo.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _verificationEmail;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() => _busy = true);
    try {
      final client = Supabase.instance.client;
      if (_register) {
        final response = await client.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'full_name': _name.text.trim()},
          emailRedirectTo: emailConfirmationRedirectUrl,
        );
        if (mounted && response.session == null) {
          setState(() {
            _verificationEmail = _email.text.trim();
            _register = false;
          });
        }
      } else {
        await client.auth.signInWithPassword(
          email: _email.text.trim(), password: _password.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falha de autenticação: ${e.message}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_verificationEmail != null) {
      return Scaffold(body: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.all(24), child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Card(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.mark_email_unread_outlined, size: 70,
                  color: Color(0xFF214E42)),
              const SizedBox(height: 18),
              Text('Verifique seu e-mail',
                style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 14),
              Text('Enviamos um link de confirmação para $_verificationEmail. '
                  'Abra seu e-mail e toque no link para voltar ao aplicativo.',
                textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text('Depois, o administrador deve aprovar seu acesso.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => setState(() => _verificationEmail = null),
                child: const Text('Voltar ao login'),
              ),
            ]),
          )),
        ),
      ))));
    }
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430),
        child: Card(child: Padding(padding: const EdgeInsets.all(24), child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Center(child: HarasLogo(size: 116)),
            const SizedBox(height: 12),
            Text('HARAS F5E', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(_register ? 'Criar conta de acesso' : 'Entrar no aplicativo',
                textAlign: TextAlign.center),
            const SizedBox(height: 28),
            if (_register) ...[
              TextFormField(controller: _name, decoration: const InputDecoration(
                labelText: 'Nome completo', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe seu nome' : null),
              const SizedBox(height: 12),
            ],
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
              validator: (v) => (v == null || !v.contains('@')) ? 'Informe um e-mail válido' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _password, obscureText: !_showPassword,
              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(labelText: 'Senha', border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: Icon(_showPassword
                    ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPassword = !_showPassword))),
              validator: (v) => (v == null || v.length < 8)
                  ? 'Senha com pelo menos 8 caracteres' : null),
            const SizedBox(height: 22),
            FilledButton(onPressed: _busy ? null : _submit,
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 13),
                child: _busy ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_register ? 'Cadastrar' : 'Entrar'))),
            TextButton(onPressed: _busy ? null : () {
              _formKey.currentState?.reset();
              setState(() => _register = !_register);
            }, child: Text(_register ? 'Já tenho conta' : 'Criar meu cadastro')),
            if (_register)
              const Text('Após o cadastro, o administrador do Haras F5E precisa liberar seu acesso.',
                  textAlign: TextAlign.center),
          ]),
        ))),
      ),
    ))));
  }
}
