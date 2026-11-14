import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_screen.dart';
import 'email_confirmation.dart';
import 'home_screen.dart';
import 'modules.dart';

class HarasApp extends StatefulWidget {
  const HarasApp({super.key});

  @override
  State<HarasApp> createState() => _HarasAppState();
}

class _HarasAppState extends State<HarasApp> {
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  String? _lastConfirmationLink;
  bool _showEmailConfirmation = false;
  bool _checkingEmail = false;
  EmailConfirmationStatus _emailStatus = EmailConfirmationStatus.verifying;

  @override
  void initState() {
    super.initState();
    // O Supabase Flutter valida os tokens do deep link automaticamente.
    // Este observador só decide se deve MOSTRAR a tela de confirmação.
    final appLinks = AppLinks();
    _linkSubscription = appLinks.uriLinkStream.listen(
      _handleLink,
      onError: (Object error) {
        // Não confundir falha de leitura de links com confirmação de e-mail.
      },
    );
    appLinks
        .getInitialLink()
        .then((uri) {
          if (uri != null) _handleLink(uri);
        })
        .catchError((Object error) {
          // O app continua permitindo login mesmo sem receber o link inicial.
        });
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (state) {
        if (_showEmailConfirmation && state.event == AuthChangeEvent.signedIn) {
          _checkConfirmedEmail();
        }
      },
      onError: (Object error) {
        if (_showEmailConfirmation && mounted) {
          setState(() => _emailStatus = EmailConfirmationStatus.failed);
        }
      },
    );
  }

  void _handleLink(Uri uri) {
    if (!mounted || !isEmailConfirmationLink(uri)) return;
    // getInitialLink e uriLinkStream podem entregar o mesmo URL.
    if (_lastConfirmationLink == uri.toString()) return;
    _lastConfirmationLink = uri.toString();
    final error =
        uri.queryParameters['error'] ??
        uri.queryParameters['error_code'] ??
        (uri.fragment.contains('error=') ? uri.fragment : null);
    final hasToken =
        uri.queryParameters.containsKey('code') ||
        uri.queryParameters.containsKey('access_token') ||
        uri.fragment.contains('access_token=');
    setState(() {
      _showEmailConfirmation = true;
      _emailStatus = error != null || !hasToken
          ? EmailConfirmationStatus.failed
          : EmailConfirmationStatus.verifying;
    });
    if (error == null && hasToken) {
      // O SDK pode já ter trocado o código ao iniciar o app a partir do link.
      _checkConfirmedEmail();
      // Link inválido ou sessão não formada: dar uma saída visível ao usuário.
      Future<void>.delayed(const Duration(seconds: 12), () {
        if (mounted &&
            _showEmailConfirmation &&
            _emailStatus == EmailConfirmationStatus.verifying) {
          setState(() => _emailStatus = EmailConfirmationStatus.failed);
        }
      });
    }
  }

  Future<void> _checkConfirmedEmail() async {
    if (!_showEmailConfirmation || _checkingEmail || !mounted) return;
    final auth = Supabase.instance.client.auth;
    // Não declarar sucesso até que o Supabase tenha uma sessão válida.
    if (auth.currentSession == null) return;
    _checkingEmail = true;
    try {
      final response = await auth.getUser();
      if (!mounted || !_showEmailConfirmation) return;
      setState(
        () => _emailStatus = response.user?.emailConfirmedAt != null
            ? EmailConfirmationStatus.confirmed
            : EmailConfirmationStatus.failed,
      );
    } catch (_) {
      if (mounted && _showEmailConfirmation) {
        setState(() => _emailStatus = EmailConfirmationStatus.failed);
      }
    } finally {
      _checkingEmail = false;
    }
  }

  void _retryConfirmation() {
    setState(() => _emailStatus = EmailConfirmationStatus.verifying);
    _checkConfirmedEmail();
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (mounted &&
          _showEmailConfirmation &&
          _emailStatus == EmailConfirmationStatus.verifying) {
        setState(() => _emailStatus = EmailConfirmationStatus.failed);
      }
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Haras F5E',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF214E42)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7F3),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF214E42),
          foregroundColor: Colors.white,
        ),
      ),
      home: _showEmailConfirmation
          ? EmailConfirmationScreen(
              status: _emailStatus,
              onContinue: () => setState(() => _showEmailConfirmation = false),
              onRetry: _retryConfirmation,
            )
          : StreamBuilder<AuthState>(
              stream: Supabase.instance.client.auth.onAuthStateChange,
              builder: (context, snapshot) {
                final session = Supabase.instance.client.auth.currentSession;
                if (session == null) return const AuthScreen();
                return ProfileGate(key: ValueKey(session.user.id));
              },
            ),
    );
  }
}

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key});

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late Future<ProfileState> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _fetchProfile();
  }

  void _reload() {
    setState(() {
      _profileFuture = _fetchProfile();
    });
  }

  Future<ProfileState> _fetchProfile() async {
    final supabase = Supabase.instance.client;
    final id = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('profiles')
        .select('full_name, role, status')
        .eq('id', id)
        .single();
    final status = row['status'] as String;
    final role = row['role'] as String;
    final permissionsRows = status == 'ativo'
        ? await supabase.rpc('my_haras_permissions') as List<dynamic>
        : <dynamic>[];
    return ProfileState(
      fullName: row['full_name'] as String? ?? '',
      role: role,
      status: status,
      permissions: Permissions.fromRows(permissionsRows),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileState>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Não foi possível consultar seu acesso.'),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Tentar novamente'),
                    ),
                    TextButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      child: const Text('Sair'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final profile = snapshot.requireData;
        if (profile.status != 'ativo') {
          return Scaffold(
            appBar: AppBar(title: const Text('Haras F5E')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      profile.status == 'bloqueado'
                          ? Icons.block
                          : Icons.hourglass_top,
                      size: 56,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      profile.status == 'bloqueado'
                          ? 'Acesso bloqueado'
                          : 'Cadastro aguardando aprovação',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Um administrador precisa liberar sua conta e definir sua função.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Verificar aprovação'),
                    ),
                    TextButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      child: const Text('Sair'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return HomeScreen(profile: profile, onRefreshPermissions: _reload);
      },
    );
  }
}
