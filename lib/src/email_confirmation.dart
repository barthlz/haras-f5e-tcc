import 'package:flutter/material.dart';

import 'haras_logo.dart';

// Mesmo endereço em: signUp(emailRedirectTo), Supabase Redirect URLs e
// AndroidManifest.xml (intent-filter).
const emailConfirmationRedirectUrl = 'br.com.f5e.haras://email-confirmado';

bool isEmailConfirmationLink(Uri uri) =>
    uri.scheme == 'br.com.f5e.haras' && uri.host == 'email-confirmado';

enum EmailConfirmationStatus { verifying, confirmed, failed }

class EmailConfirmationScreen extends StatelessWidget {
  final EmailConfirmationStatus status;
  final VoidCallback onContinue;
  final VoidCallback onRetry;

  const EmailConfirmationScreen({
    super.key,
    required this.status,
    required this.onContinue,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final confirmed = status == EmailConfirmationStatus.confirmed;
    final verifying = status == EmailConfirmationStatus.verifying;
    return Scaffold(
      appBar: AppBar(title: const Text('Haras F5E')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const HarasLogo(size: 76),
                      const SizedBox(height: 15),
                      if (verifying)
                        const SizedBox(
                          width: 58,
                          height: 58,
                          child: CircularProgressIndicator(strokeWidth: 4),
                        )
                      else
                        Icon(
                          confirmed
                              ? Icons.mark_email_read_rounded
                              : Icons.error_outline,
                          color: confirmed
                              ? const Color(0xFF247A55)
                              : Colors.orange.shade800,
                          size: 72,
                        ),
                      const SizedBox(height: 20),
                      Text(
                        confirmed
                            ? 'E-mail confirmado!'
                            : verifying
                            ? 'Confirmando seu e-mail…'
                            : 'Não foi possível confirmar automaticamente',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        confirmed
                            ? 'Seu endereço de e-mail foi verificado com sucesso. '
                                  'Para entrar nas áreas do Haras F5E, sua conta '
                                  'ainda precisa da aprovação do administrador.'
                            : verifying
                            ? 'Estamos verificando o link com o Supabase.'
                            : 'O link pode estar expirado ou já ter sido usado. '
                                  'Volte ao login e tente entrar. Se seu e-mail '
                                  'estiver confirmado, o acesso seguirá normalmente.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      if (!verifying) ...[
                        if (!confirmed) ...[
                          OutlinedButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Verificar novamente'),
                          ),
                          const SizedBox(height: 10),
                        ],
                        FilledButton.icon(
                          onPressed: onContinue,
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(
                            confirmed
                                ? 'Continuar para o aplicativo'
                                : 'Ir para o aplicativo',
                          ),
                        ),
                      ],
                      if (verifying)
                        TextButton(
                          onPressed: onContinue,
                          child: const Text('Voltar ao aplicativo'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
