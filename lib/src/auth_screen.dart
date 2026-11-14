import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'haras_logo.dart';

/// Cadastro, login e confirmação de e-mail por código dentro do app.
/// O fluxo de cadastro continua exigindo confirmação no Supabase e
/// aprovação administrativa conforme as regras de acesso do projeto.
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
  final _code = TextEditingController();

  bool _register = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _verificationEmail;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _authError(AuthException error) {
    final detail = error.message.toLowerCase();
    if (detail.contains('rate limit') ||
        detail.contains('too many') ||
        detail.contains('seconds')) {
      return 'Muitas solicitações. Aguarde um pouco e tente novamente.';
    }
    if (detail.contains('expired') ||
        detail.contains('invalid otp') ||
        detail.contains('token is invalid')) {
      return 'Código inválido ou expirado. Confira o e-mail ou solicite outro.';
    }
    return 'Não foi possível concluir a operação: ${error.message}';
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    setState(() => _busy = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (_register) {
        final result = await auth.signUp(
          email: email,
          password: _password.text,
          data: {'full_name': _name.text.trim()},
          // Sem emailRedirectTo: o e-mail tem um código, não um link externo.
        );
        if (!mounted) return;
        if (result.session == null) {
          _code.clear();
          setState(() => _verificationEmail = email);
        } else {
          _message('Cadastro realizado. Aguarde a aprovação do administrador.');
        }
      } else {
        await auth.signInWithPassword(
          email: email,
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      _message(_authError(error));
    } catch (_) {
      _message('Erro inesperado. Verifique sua conexão e tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyEmail() async {
    final email = _verificationEmail;
    if (_busy || email == null) return;
    final code = _code.text.trim();
    if (code.length < 6 || code.length > 8) {
      _message('Digite o código numérico completo enviado por e-mail.');
      return;
    }
    setState(() => _busy = true);
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );
      if (!mounted) return;
      if (response.user == null) {
        _message('Não foi possível confirmar. Tente novamente.');
        return;
      }
      // O fluxo principal do app recebe a nova sessão pelo listener de auth.
      _code.clear();
      setState(() {
        _verificationEmail = null;
        _register = false;
      });
      _message('E-mail confirmado! Agora sua conta aguarda aprovação.');
    } on AuthException catch (error) {
      _message(_authError(error));
    } catch (_) {
      _message('Não foi possível confirmar agora. Tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    final email = _verificationEmail;
    if (_busy || email == null) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.resend(
        email: email,
        type: OtpType.signup,
      );
      _code.clear();
      _message('Novo código solicitado. Confira sua caixa de entrada e spam.');
    } on AuthException catch (error) {
      _message(_authError(error));
    } catch (_) {
      _message('Não foi possível reenviar agora. Tente novamente.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _verificationForm() {
    final email = _verificationEmail!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Center(
          child: CircleAvatar(
            radius: 33,
            backgroundColor: Color(0xFFE8F2ED),
            child: Icon(Icons.mark_email_unread_outlined,
                size: 34, color: Color(0xFF214E42)),
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Confirme seu e-mail',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Enviamos um código de verificação para:',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        SelectableText(
          email,
          style: const TextStyle(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _code,
          autofocus: true,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 8,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 5),
          decoration: const InputDecoration(
            labelText: 'Código de verificação',
            hintText: 'Digite o código',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _verifyEmail(),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _verifyEmail,
          icon: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_user_outlined),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Text('Confirmar e-mail'),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _busy ? null : _resendCode,
          icon: const Icon(Icons.refresh),
          label: const Text('Reenviar código'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  _code.clear();
                  setState(() => _verificationEmail = null);
                },
          child: const Text('Voltar ao cadastro ou login'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Por segurança, nunca compartilhe esse código. '
          'Após a confirmação, o administrador ainda precisará '
          'liberar seu acesso.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _credentialsForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: HarasLogo(size: 105)),
          const SizedBox(height: 15),
          Text(
            'HARAS F5E  •  TCC',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _register ? 'Crie sua conta de acesso' : 'Entre na sua conta',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 26),
          if (_register) ...[
            TextFormField(
              controller: _name,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome completo',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Informe seu nome'
                  : null,
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'E-mail',
              prefixIcon: Icon(Icons.alternate_email),
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                value == null || !value.trim().contains('@')
                    ? 'Informe um e-mail válido'
                    : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            enabled: !_busy,
            obscureText: !_showPassword,
            autofillHints: [
              _register ? AutofillHints.newPassword : AutofillHints.password,
            ],
            decoration: InputDecoration(
              labelText: 'Senha',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                icon: Icon(_showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            validator: (value) => value == null || value.length < 8
                ? 'A senha deve ter pelo menos 8 caracteres'
                : null,
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_register ? 'Criar conta' : 'Entrar'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    _formKey.currentState?.reset();
                    setState(() => _register = !_register);
                  },
            child: Text(_register
                ? 'Já tem uma conta? Entrar'
                : 'Ainda não tem conta? Cadastre-se'),
          ),
          if (_register)
            const Text(
              'Você receberá um código por e-mail. Depois da confirmação, '
              'o administrador deve aprovar seu acesso.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 1,
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: _verificationEmail == null
                      ? _credentialsForm()
                      : _verificationForm(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
