import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'crud_screen.dart';
import 'haras_logo.dart';
import 'modules.dart';
import 'reports_screen.dart';
import 'stay_receipts_screen.dart';
import 'values_screen.dart';
import 'users_screen.dart';

class HomeScreen extends StatefulWidget {
  final ProfileState profile;
  final VoidCallback onRefreshPermissions;

  const HomeScreen({super.key, required this.profile,
    required this.onRefreshPermissions});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late String _current;

  @override
  void initState() {
    super.initState();
    _current = widget.profile.permissions.allows('resumo', 'view')
        ? 'resumo'
        : modules.firstWhere((m) => widget.profile.permissions.allows(m.id, 'view'),
            orElse: () => modules.first).id;
  }

  void _choose(String id) {
    Navigator.of(context).pop();
    setState(() => _current = id);
  }

  IconData _icon(String id) => switch (id) {
    'resumo' => Icons.dashboard,
    'clientes' => Icons.people,
    'animais' => Icons.pets,
    'despesas' => Icons.payments,
    'funcionarios' => Icons.badge,
    'pagamentos' => Icons.account_balance_wallet,
    'recebimentos_estadia' => Icons.receipt_long,
    'valores' => Icons.price_change,
    'relatorios' => Icons.assessment,
    'hospedagem' => Icons.home_work,
    'treinamento' => Icons.sports,
    'reproducao' => Icons.female,
    'exames' => Icons.medical_information,
    _ => Icons.folder,
  };

  @override
  Widget build(BuildContext context) {
    final allowed = modules.where(
      (m) => widget.profile.permissions.allows(m.id, 'view'),
    ).toList();
    final admin = widget.profile.role == 'administrador';
    final module = allowed.where((m) => m.id == _current).firstOrNull;
    final title = _current == 'resumo' ? 'Resumo'
        : _current == 'recebimentos_estadia' ? 'Recebimento de estadia'
        : _current == 'valores' ? 'Valores'
        : _current == 'relatorios' ? 'Relatórios'
        : _current == 'usuarios' ? 'Acessos'
        : module?.title ?? 'Haras F5E';

    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const HarasLogo(size: 34),
          const SizedBox(width: 10),
          Flexible(child: Text('F5E  |  $title', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(tooltip: 'Atualizar acesso', icon: const Icon(Icons.refresh),
              onPressed: widget.onRefreshPermissions),
          IconButton(tooltip: 'Sair', icon: const Icon(Icons.logout),
              onPressed: () => Supabase.instance.client.auth.signOut()),
        ],
      ),
      drawer: Drawer(child: SafeArea(child: ListView(children: [
        UserAccountsDrawerHeader(
          accountName: Text(widget.profile.fullName),
          accountEmail: Text('Função: ${widget.profile.role}'),
          currentAccountPicture: const CircleAvatar(
            backgroundColor: Colors.white,
            child: HarasLogo(size: 50),
          ),
          decoration: const BoxDecoration(color: Color(0xFF214E42)),
        ),
        if (widget.profile.permissions.allows('resumo', 'view'))
          ListTile(leading: Icon(_icon('resumo')), title: const Text('Resumo'),
              selected: _current == 'resumo', onTap: () => _choose('resumo')),
        for (final m in allowed)
          ListTile(leading: Icon(_icon(m.id)), title: Text(m.title),
              selected: _current == m.id, onTap: () => _choose(m.id)),
        if (widget.profile.permissions.allows('recebimentos_estadia', 'view'))
          ListTile(leading: Icon(_icon('recebimentos_estadia')),
              title: const Text('Recebimento de estadia'),
              selected: _current == 'recebimentos_estadia',
              onTap: () => _choose('recebimentos_estadia')),
        if (widget.profile.permissions.allows('relatorios', 'view'))
          ListTile(leading: Icon(_icon('relatorios')),
              title: const Text('Relatórios'),
              selected: _current == 'relatorios',
              onTap: () => _choose('relatorios')),
        if (widget.profile.permissions.allows('valores', 'view'))
          ListTile(leading: Icon(_icon('valores')),
              title: const Text('Valores'),
              selected: _current == 'valores',
              onTap: () => _choose('valores')),
        if (admin) ...[
          const Divider(),
          ListTile(leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Aprovar usuários / funções'),
              selected: _current == 'usuarios', onTap: () => _choose('usuarios')),
        ],
        const Divider(),
        ListTile(leading: const Icon(Icons.refresh), title: const Text('Atualizar permissões'),
            onTap: () { Navigator.pop(context); widget.onRefreshPermissions(); }),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Sair'),
            onTap: () => Supabase.instance.client.auth.signOut()),
      ]))),
      body: switch (_current) {
        'resumo' when widget.profile.permissions.allows('resumo', 'view')
            => SummaryScreen(permissions: widget.profile.permissions),
        'usuarios' when admin => const UsersScreen(),
        'recebimentos_estadia' when widget.profile.permissions.allows('recebimentos_estadia','view')
            => StayReceiptsScreen(permissions: widget.profile.permissions),
        'valores' when widget.profile.permissions.allows('valores','view')
            => ValuesScreen(permissions: widget.profile.permissions),
        'relatorios' when widget.profile.permissions.allows('relatorios','view')
            => const ReportsScreen(),
        _ when module != null => CrudScreen(key: ValueKey(_current),
            module: module, permissions: widget.profile.permissions),
        _ => const Center(child: Text('Nenhum módulo autorizado.')),
      },
    );
  }
}

class SummaryScreen extends StatefulWidget {
  final Permissions permissions;
  const SummaryScreen({super.key, required this.permissions});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late Future<Map<String, int>> _counts;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _counts = _fetchCounts();
  }

  Future<Map<String, int>> _fetchCounts() async {
    final supabase = Supabase.instance.client;
    final result = <String, int>{};
    for (final m in modules) {
      if (!widget.permissions.allows(m.id, 'view')) continue;
      final response = await supabase.from(m.table)
          .select('id').count(CountOption.exact);
      result[m.id] = response.count;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _counts,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Não foi possível montar o resumo: ${snapshot.error}'),
              TextButton(onPressed: () => setState(_reload),
                  child: const Text('Tentar novamente')),
            ]));
          }
          return const Center(child: CircularProgressIndicator());
        }
        final counts = snapshot.requireData;
        return RefreshIndicator(
          onRefresh: () async { setState(_reload); await _counts; },
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text('Visão geral do Haras F5E',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 5),
            const Text('As informações exibidas respeitam sua função e suas permissões.'),
            const SizedBox(height: 20),
            if (counts.isEmpty) const Text('Nenhum indicador liberado para seu perfil.'),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final m in modules.where((m) => counts.containsKey(m.id)))
                SizedBox(width: 165, height: 125, child: Card(child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.title, style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    Text('${counts[m.id]}',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: const Color(0xFF214E42), fontWeight: FontWeight.bold)),
                    const Text('Registros', style: TextStyle(fontSize: 12)),
                  ]),
                ))),
            ]),
            const SizedBox(height: 18),
            OutlinedButton.icon(onPressed: () => setState(_reload),
                icon: const Icon(Icons.refresh), label: const Text('Atualizar resumo')),
          ]),
        );
      },
    );
  }
}
