import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'date_br.dart';
import 'values_screen.dart';

// Relatorios sao SOMENTE leitura: os agregados e filtros sao calculados no
// Supabase, com verificacao de funcao/status nas RPCs (RLS do aplicativo).
const _months = <String>[
  'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
  'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez',
];
const _pageSize = 100;

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-01';
String _month(Object? v) {
  final d = DateTime.tryParse(v?.toString() ?? '');
  return d == null ? '—' : '${_months[d.month - 1]}/${d.year}';
}
String _number(Map<String, dynamic> row, String key) =>
    formatBrl((row[key] as num?) ?? 0);
num _amount(Map<String, dynamic> row, String key) =>
    (row[key] as num?) ?? 0;
List<Map<String, dynamic>> _rows(dynamic data) => (data as List)
    .map((r) => Map<String, dynamic>.from(r as Map)).toList();

Future<DateTime?> _selectMonth(BuildContext context, DateTime current) {
  var year = current.year;
  return showDialog<DateTime>(context: context, builder: (dialog) =>
      StatefulBuilder(builder: (ctx, change) => AlertDialog(
        title: const Text('Selecione mês e ano'),
        content: SizedBox(width: 340, child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(tooltip: 'Ano anterior', icon: const Icon(Icons.chevron_left),
                onPressed: year > 2000 ? () => change(() => year--) : null),
              Text('$year', style: Theme.of(ctx).textTheme.titleLarge),
              IconButton(tooltip: 'Ano seguinte', icon: const Icon(Icons.chevron_right),
                onPressed: year < 2100 ? () => change(() => year++) : null),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 7, runSpacing: 7, children: [
              for (var m = 1; m <= 12; m++)
                ChoiceChip(label: Text(_months[m - 1]),
                    selected: year == current.year && m == current.month,
                    onSelected: (_) => Navigator.pop(ctx, DateTime(year, m, 1))),
            ]),
          ],
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'))],
      )));
}

class _Overview {
  final List<Map<String, dynamic>> clients;
  final List<Map<String, dynamic>> payments;
  final Map<String, dynamic> stats;
  const _Overview(this.clients, this.payments, this.stats);
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _from;
  late DateTime _to;
  late DateTime _appliedFrom;
  late DateTime _appliedTo;
  late Future<_Overview> _future;
  String _search = '';
  final _extraPayments = <Map<String, dynamic>>[];
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, 1);
    _from = DateTime(now.year, now.month - 1, 1);
    _appliedFrom = _from;
    _appliedTo = _to;
    _future = _fetch();
  }

  Future<_Overview> _fetch() async {
    final db = Supabase.instance.client;
    // Calcula competencias ainda pendentes com a regra do mes de entrada isento.
    await db.rpc('haras_sync_stay_charges');
    final params = {'p_start': _iso(_appliedFrom), 'p_end': _iso(_appliedTo)};
    // Pagina os clientes para nao perder registros caso ultrapassem o limite
    // padrao de linhas do PostgREST (frequentemente 1000).
    final clients = <Map<String, dynamic>>[];
    const clientPageSize = 500;
    for (var offset = 0; ; offset += clientPageSize) {
      final page = _rows(await db.rpc('haras_report_clients', params: params)
          .range(offset, offset + clientPageSize - 1));
      clients.addAll(page);
      if (page.length < clientPageSize) break;
    }
    final stats = _rows(await db.rpc('haras_report_payment_stats', params: params));
    final payments = _rows(await db.rpc('haras_report_payments', params: {
      ...params, 'p_limit': _pageSize, 'p_offset': 0,
    }));
    return _Overview(clients, payments, stats.isNotEmpty ? stats.first : {});
  }

  void _refresh() {
    _extraPayments.clear();
    _hasMore = true;
    _loadingMore = false;
    setState(() => _future = _fetch());
  }

  void _apply() {
    if (_from.isAfter(_to)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('O mês inicial não pode ser posterior ao mês final.')));
      return;
    }
    _appliedFrom = _from;
    _appliedTo = _to;
    _refresh();
  }

  Future<void> _loadMore(int currentCount) async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _rows(await Supabase.instance.client.rpc('haras_report_payments',
        params: {
          'p_start': _iso(_appliedFrom), 'p_end': _iso(_appliedTo),
          'p_limit': _pageSize, 'p_offset': currentCount,
        }));
      if (!mounted) return;
      setState(() {
        _extraPayments.addAll(next);
        _hasMore = next.length == _pageSize;
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar mais pagamentos: $error')));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Overview>(
    future: _future,
    builder: (context, snapshot) {
      return RefreshIndicator(
        onRefresh: () async { _refresh(); await _future; },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Relatórios', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          const Text('Consulte quem pagou em um intervalo de meses e abra um '
              'cliente para conferir animais, cobranças e pagamentos.'),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(icon: const Icon(Icons.calendar_month),
                label: Text('De: ${_month(_iso(_from))}'),
                onPressed: () async {
                  final d = await _selectMonth(context, _from);
                  if (d != null && mounted) setState(() => _from = d);
                }),
              OutlinedButton.icon(icon: const Icon(Icons.event),
                label: Text('Até: ${_month(_iso(_to))}'),
                onPressed: () async {
                  final d = await _selectMonth(context, _to);
                  if (d != null && mounted) setState(() => _to = d);
                }),
              FilledButton.icon(icon: const Icon(Icons.search),
                label: const Text('Consultar'), onPressed: _apply),
            ]),
          const SizedBox(height: 10),
          Text('Período consultado: ${_month(_iso(_appliedFrom))} até '
              '${_month(_iso(_appliedTo))}',
              style: Theme.of(context).textTheme.bodySmall),
          const Divider(height: 26),
          if (snapshot.hasError) ...[
            Text('Não foi possível carregar os relatórios: ${snapshot.error}',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: _refresh,
                icon: const Icon(Icons.refresh), label: const Text('Tentar novamente')),
          ] else if (!snapshot.hasData) ...[
            const Padding(padding: EdgeInsets.all(28), child:
                Center(child: CircularProgressIndicator())),
          ] else ...[
            _reportBody(snapshot.requireData),
          ],
        ]),
      );
    },
  );

  Widget _reportBody(_Overview data) {
    final stats = data.stats;
    final paidRecords = [...data.payments, ..._extraPayments];
    final clients = data.clients.where((r) {
      final term = _search.trim().toLowerCase();
      return term.isEmpty ||
          (r['client_name']?.toString().toLowerCase().contains(term) ?? false) ||
          (r['client_number']?.toString().toLowerCase().contains(term) ?? false);
    }).toList();
    final canLoadMore = data.payments.length == _pageSize && _hasMore;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        _metric('Total recebido no período', _number(stats, 'paid_amount')),
        _metric('Pagamentos registrados', '${stats['payment_count'] ?? 0}'),
        _metric('Clientes que pagaram', '${stats['payer_count'] ?? 0}'),
      ]),
      const SizedBox(height: 8),
      const Text('Os recebimentos acima incluem pagamentos gerais e de estadia, '
          'inclusive os de clientes excluídos.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 22),
      Text('Consulta por cliente', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      TextField(decoration: const InputDecoration(
          labelText: 'Buscar cliente por nome ou número',
          prefixIcon: Icon(Icons.person_search), border: OutlineInputBorder()),
          onChanged: (v) => setState(() => _search = v)),
      const SizedBox(height: 8),
      if (clients.isEmpty) const Padding(padding: EdgeInsets.all(16),
          child: Text('Nenhum cliente encontrado.')),
      for (final client in clients)
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text('${client['client_name'] ?? 'Cliente'}'
              '${client['client_number'] == null ? '' : '  •  Nº ${client['client_number']}'}'),
          subtitle: Text('${client['animal_count'] ?? 0} animais  •  '
              'Pago no período: ${_number(client, 'period_paid')}'
              '\nSaldo devedor: ${formatBrl(_amount(client,'balance') > 0 ? _amount(client,'balance') : 0)}'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _ClientReportScreen(client: client,
                  start: _appliedFrom, end: _appliedTo))),
        )),
      const SizedBox(height: 22),
      Text('Quem pagou no período', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 5),
      const Text('Filtrado pela data em que o pagamento foi recebido.'),
      const SizedBox(height: 8),
      if (paidRecords.isEmpty) const Padding(padding: EdgeInsets.all(18),
          child: Text('Nenhum pagamento neste período.')),
      for (final payment in paidRecords) _paymentTile(payment),
      if (canLoadMore)
        OutlinedButton.icon(onPressed: _loadingMore ? null :
            () => _loadMore(paidRecords.length),
            icon: const Icon(Icons.expand_more),
            label: Text(_loadingMore ? 'Carregando...' : 'Mostrar mais pagamentos')),
    ]);
  }
}

Widget _metric(String title, String value) => SizedBox(width: 175,
  child: Card(child: Padding(padding: const EdgeInsets.all(13),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 7),
      Text(value, style: const TextStyle(fontSize: 17,
          fontWeight: FontWeight.bold)),
    ]),
  )),
);

Widget _paymentTile(Map<String, dynamic> p) {
  final isStay = p['payment_kind'] == 'estadia';
  final note = p['note']?.toString().trim() ?? '';
  final linkedAnimals = p['animal_names']?.toString().trim() ?? '';
  final number = p['client_number']?.toString();
  return Card(child: ListTile(
    title: Text('${p['client_name'] ?? 'Cliente'}'
        '${number == null || number.isEmpty ? '' : ' • Nº $number'}'),
    subtitle: Text('Recebido: ${formatDateBr(p['payment_date'])}  •  '
        '${isStay ? 'Estadia' : 'Pagamento geral'}'
        '\nReferência: ${p['reference_month'] == null ? 'Não informada' : _month(p['reference_month'])}'
        '${linkedAnimals.isEmpty ? '' : '\nAnimais vinculados: $linkedAnimals'}'
        '${note.isEmpty ? '' : '\nObservações: $note'}'),
    isThreeLine: true,
    trailing: Text(_number(p, 'amount'),
        style: const TextStyle(fontWeight: FontWeight.bold)),
  ));
}

class _ClientReportData {
  final List<Map<String, dynamic>> animals;
  final List<Map<String, dynamic>> charges;
  final List<Map<String, dynamic>> payments;
  const _ClientReportData(this.animals, this.charges, this.payments);
}

class _ClientReportScreen extends StatefulWidget {
  final Map<String, dynamic> client;
  final DateTime start;
  final DateTime end;
  const _ClientReportScreen({required this.client, required this.start,
      required this.end});

  @override
  State<_ClientReportScreen> createState() => _ClientReportScreenState();
}

class _ClientReportScreenState extends State<_ClientReportScreen> {
  late Future<_ClientReportData> _future;
  final _extraPayments = <Map<String, dynamic>>[];
  bool _hasMore = true;
  bool _loadingMore = false;
  @override
  void initState() { super.initState(); _future = _fetch(); }

  Future<_ClientReportData> _fetch() async {
    final db = Supabase.instance.client;
    final id = widget.client['client_id'].toString();
    final animals = await db.from('animals')
        .select('id,name,species,arrival_date,departure_date,billing_category,training_enabled,lodging_enabled,breeding_enabled')
        .eq('owner_client_id', id).order('name');
    final charges = _rows(await db.rpc('haras_report_charges', params: {
      'p_client': id, 'p_start': _iso(widget.start), 'p_end': _iso(widget.end),
    }));
    final payments = _rows(await db.rpc('haras_report_payments', params: {
      'p_client': id, 'p_start': _iso(widget.start), 'p_end': _iso(widget.end),
      'p_limit': _pageSize, 'p_offset': 0,
    }));
    return _ClientReportData(_rows(animals), charges, payments);
  }

  Future<void> _loadMore(int count) async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _rows(await Supabase.instance.client.rpc('haras_report_payments',
        params: {
          'p_client': widget.client['client_id'].toString(),
          'p_start': _iso(widget.start), 'p_end': _iso(widget.end),
          'p_limit': _pageSize, 'p_offset': count,
        }));
      if (!mounted) return;
      setState(() {
        _extraPayments.addAll(next);
        _hasMore = next.length == _pageSize;
      });
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao buscar pagamentos: $error')));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Relatório do cliente')),
    body: FutureBuilder<_ClientReportData>(future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Erro ao carregar o cliente: ${snapshot.error}'),
            TextButton(onPressed: () => setState(() => _future = _fetch()),
                child: const Text('Tentar novamente')),
          ])));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.requireData;
        final c = widget.client;
        final balance = _amount(c,'balance');
        final payments = [...data.payments, ..._extraPayments];
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('${c['client_name'] ?? 'Cliente'}',
              style: Theme.of(context).textTheme.headlineSmall),
          if (c['client_number'] != null)
            Text('Cliente Nº ${c['client_number']}'),
          Text('Período: ${_month(_iso(widget.start))} a ${_month(_iso(widget.end))}'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _metric('Animais no nome', '${c['animal_count'] ?? 0}'),
            _metric('Total cobrado', _number(c,'total_charged')),
            _metric('Já pago (histórico)', _number(c,'total_paid_history')),
            _metric('Saldo devedor', formatBrl(balance > 0 ? balance : 0)),
            if (balance < 0) _metric('Crédito do cliente', formatBrl(-balance)),
          ]),
          const SizedBox(height: 8),
          Text('Pagamentos considerados no saldo: ${_number(c,'total_paid_credited')}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _metric('Cobrado no período', _number(c,'period_charged')),
            _metric('Pago no período', _number(c,'period_paid')),
          ]),
          const SizedBox(height: 22),
          Text('Animais vinculados (${data.animals.length})',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (data.animals.isEmpty) const Text('Este cliente não possui animais vinculados atualmente.'),
          for (final a in data.animals)
            Card(child: ListTile(
              leading: const Icon(Icons.pets),
              title: Text(a['name']?.toString() ?? 'Animal'),
              subtitle: Text('${a['species'] ?? 'Espécie não informada'}  •  '
                '${a['billing_category'] ?? 'Padrão'}'
                '\nEntrada: ${formatDateBr(a['arrival_date'])}'
                '${a['departure_date'] == null ? '' : '  •  Saída: ${formatDateBr(a['departure_date'])}'}'),
              isThreeLine: true,
            )),
          const SizedBox(height: 22),
          Text('O que foi cobrado no período',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('Serviços e valores mensais por animal. O mês de entrada é isento.'),
          if (data.charges.isEmpty) const Padding(padding: EdgeInsets.all(12),
              child: Text('Nenhuma mensalidade registrada neste período.')),
          for (final charge in data.charges)
            Card(child: ListTile(
              title: Text('${charge['animal_name']}  •  ${_month(charge['reference_month'])}'),
              subtitle: Text('${charge['description'] ?? 'Mensalidade'}'
                  '\nVencimento: ${formatDateBr(charge['due_date'])}'),
              isThreeLine: true,
              trailing: Text(_number(charge,'amount'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            )),
          const SizedBox(height: 22),
          Text('O que foi pago no período',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (payments.isEmpty) const Padding(padding: EdgeInsets.all(12),
              child: Text('Não há pagamentos registrados neste período.')),
          for (final p in payments) _paymentTile(p),
          if (data.payments.length == _pageSize && _hasMore)
            OutlinedButton.icon(onPressed: _loadingMore ? null :
              () => _loadMore(payments.length), icon: const Icon(Icons.expand_more),
              label: Text(_loadingMore ? 'Carregando...' : 'Mostrar mais pagamentos')),
          const SizedBox(height: 14),
          const Text('Importante: o relatório mostra os serviços cobrados e os '
              'recebimentos lançados. Um pagamento de estadia não é atribuído '
              'automaticamente a um animal específico; apenas vínculos '
              'registrados aparecem como “animais vinculados”. '
              'O saldo segue a regra financeira já usada na aba de recebimentos.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 18),
        ]);
      },
    ),
  );
}
