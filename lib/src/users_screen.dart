import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _roles = ['administrador', 'gerente', 'financeiro', 'treinador', 'funcionario'];
const _statuses = ['pendente', 'ativo', 'bloqueado'];

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<Map<String, dynamic>>> _users;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _users = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final rows = await Supabase.instance.client.from('profiles')
        .select('id, full_name, email, role, status, created_at')
        .order('created_at', ascending: false);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> _manage(Map<String, dynamic> user) async {
    final ownId = Supabase.instance.client.auth.currentUser?.id;
    if (user['id'] == ownId) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
        'Por segurança, a própria conta do administrador não pode ser alterada por esta tela.'
      )));
      return;
    }
    String role = user['role'] as String;
    String status = user['status'] as String;
    bool saving = false;
    final done = await showDialog<bool>(context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('Liberar: ${user['full_name']}'),
          content: SizedBox(width: 400, child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              const Text('Defina a função e se este usuário está autorizado.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Função',
                    border: OutlineInputBorder()),
                items: [for (final item in _roles)
                  DropdownMenuItem(value: item, child: Text(item))],
                onChanged: saving ? null : (v) => setLocal(() => role = v ?? role),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Situação',
                    border: OutlineInputBorder()),
                items: [for (final item in _statuses)
                  DropdownMenuItem(value: item, child: Text(item))],
                onChanged: saving ? null : (v) => setLocal(() => status = v ?? status),
              ),
            ],
          )),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar')),
            FilledButton(onPressed: saving ? null : () async {
              setLocal(() => saving = true);
              try {
                final updated = await Supabase.instance.client.from('profiles')
                    .update({'role': role, 'status': status})
                    .eq('id', user['id']).select('id').single();
                if (updated['id'] == null) throw StateError('Atualização não autorizada');
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Falha ao salvar acesso: $e')));
                  setLocal(() => saving = false);
                }
              }
            }, child: Text(saving ? 'Salvando...' : 'Salvar permissão')),
          ],
        ),
      ));
    if (done == true && mounted) setState(_refresh);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _users,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Erro ao carregar usuários: ${snapshot.error}'),
              TextButton(onPressed: () => setState(_refresh),
                  child: const Text('Tentar novamente')),
            ]));
          }
          return const Center(child: CircularProgressIndicator());
        }
        final users = snapshot.requireData;
        return RefreshIndicator(onRefresh: () async {
          setState(_refresh);
          await _users;
        }, child: ListView(padding: const EdgeInsets.all(14), children: [
          Text('Contas e funções', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Usuários novos começam pendentes. Apenas um administrador libera acessos.'),
          const SizedBox(height: 14),
          for (final user in users)
            Card(child: ListTile(
              leading: Icon(user['status'] == 'ativo'
                  ? Icons.verified_user : user['status'] == 'bloqueado'
                  ? Icons.block : Icons.hourglass_empty),
              title: Text(user['full_name']?.toString() ?? 'Sem nome'),
              subtitle: Text('${user['email'] ?? ''}\nFunção: ${user['role']}  •  Situação: ${user['status']}'),
              trailing: const Icon(Icons.edit),
              onTap: () => _manage(user),
            )),
        ]));
      },
    );
  }
}
