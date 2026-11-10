import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'modules.dart';
import 'date_br.dart';
import 'billing_due_date.dart';
import 'values_screen.dart';

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _monthLabel(DateTime date) =>
    '${_months[date.month - 1]}/${date.year}';
const _months = <String>['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
  'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];

String _stayDueDateLabel(Object? referenceMonth) {
  final month = DateTime.tryParse(referenceMonth?.toString() ?? '');
  return month == null ? '—' : formatDateBr(_isoDate(stayChargeDueDate(month)));
}

Future<DateTime?> _pickMonth(BuildContext context, DateTime initial) async {
  int year = initial.year;
  return showDialog<DateTime>(context: context, builder: (dialog) =>
    StatefulBuilder(builder: (ctx, update) => AlertDialog(
      title: const Text('Escolha o mês de pagamento'),
      content: SizedBox(width: 350, child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(onPressed: year > 2000 ? () => update(() => year--) : null,
              icon: const Icon(Icons.chevron_left), tooltip: 'Ano anterior'),
            Text('$year', style: Theme.of(ctx).textTheme.titleLarge),
            IconButton(onPressed: year < 2100 ? () => update(() => year++) : null,
              icon: const Icon(Icons.chevron_right), tooltip: 'Próximo ano'),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 7, runSpacing: 7, children: [
            for (int m = 1; m <= 12; m++)
              ChoiceChip(label: Text(_months[m - 1]),
                selected: initial.year == year && initial.month == m,
                onSelected: (_) => Navigator.pop(ctx, DateTime(year, m, 1))),
          ]),
        ],
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancelar'))],
    )),
  );
}

class _ReceiptData {
  final List<Map<String, dynamic>> clients;
  final List<Map<String, dynamic>> receipts;
  final DateTime start;
  const _ReceiptData(this.clients, this.receipts, this.start);
}

class StayReceiptsScreen extends StatefulWidget {
  final Permissions permissions;
  const StayReceiptsScreen({super.key, required this.permissions});
  @override
  State<StayReceiptsScreen> createState() => _StayReceiptsScreenState();
}

class _StayReceiptsScreenState extends State<StayReceiptsScreen> {
  late Future<_ReceiptData> _records;
  bool _deleting = false;

  @override
  void initState() { super.initState(); _reload(); }
  void _reload() { _records = _load(); }

  Future<_ReceiptData> _load() async {
    final db = Supabase.instance.client;
    // Gera as competências ainda pendentes. Não modifica meses já fechados.
    await db.rpc('haras_sync_stay_charges');
    final clients = await db.from('clients').select('id,name,client_number')
        .order('name').limit(1500);
    final payments = await db.from('payments')
        .select('id,client_id,client_name_snapshot,payment_date,reference_month,amount,note')
        .eq('payment_kind','estadia').order('payment_date',ascending:false).limit(200);
    final settings = await db.from('stay_billing_settings')
        .select('billing_start_month').eq('singleton',true).single();
    return _ReceiptData(
      clients.map((r) => Map<String,dynamic>.from(r)).toList(),
      payments.map((r) => Map<String,dynamic>.from(r)).toList(),
      DateTime.parse(settings['billing_start_month'].toString()),
    );
  }

  Future<void> _editor(_ReceiptData data, [Map<String, dynamic>? existing]) async {
    final saved = await showDialog<bool>(context: context,
      builder: (ctx) => _StayReceiptEditor(clients: data.clients, existing: existing,
        billingStart: data.start));
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _delete(Map<String,dynamic> row) async {
    if (_deleting) return;
    final agreed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Você tem certeza que deseja excluir?'),
      content: const Text('Este recebimento será excluído definitivamente. '
          'O saldo devido pelo cliente aumentará pelo valor excluído.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx,true),
          child: const Text('Sim, excluir')),
      ],
    ));
    if (agreed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final result = await Supabase.instance.client.from('payments').delete()
          .eq('id',row['id']).eq('payment_kind','estadia').select('id');
      if (result.isEmpty) throw StateError('Sem permissão para excluir este recebimento.');
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir: $e')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_ReceiptData>(
    future: _records,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Padding(
        padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Erro ao carregar recebimentos: ${snapshot.error}',textAlign:TextAlign.center),
          TextButton(onPressed: () => setState(_reload), child: const Text('Tentar novamente')),
        ])));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final data = snapshot.requireData;
      final clientsById = {for (final c in data.clients) c['id'].toString():c['name'].toString()};
      final canCreate = widget.permissions.allows('recebimentos_estadia','create');
      final canEdit = widget.permissions.allows('recebimentos_estadia','edit');
      final canDelete = widget.permissions.allows('recebimentos_estadia','delete');
      return Scaffold(
        body: RefreshIndicator(onRefresh: () async {setState(_reload); await _records;},
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('Recebimento de estadia', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text('O mês de entrada do animal é isento. A primeira mensalidade '
              'é cobrada somente no mês seguinte, com vencimento no dia 10. '
              'Depois, o saldo acumula as mensalidades de cada mês e desconta os pagamentos. '
              'Quando não há data de entrada, utiliza-se o mês do cadastro '
              '(nunca antes do início do faturamento do sistema).'),
            const SizedBox(height: 14),
            if (canCreate) FilledButton.icon(
              icon: const Icon(Icons.add), label: const Text('Novo recebimento'),
              onPressed: () => _editor(data)),
            const SizedBox(height: 16),
            Text('Recebimentos registrados',style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (data.receipts.isEmpty) const Padding(padding: EdgeInsets.all(24),
              child: Center(child: Text('Nenhum recebimento de estadia registrado.'))),
            for (final receipt in data.receipts)
              Card(child: ListTile(
                title: Text(clientsById[receipt['client_id']?.toString()] ??
                  receipt['client_name_snapshot']?.toString() ?? 'Cliente excluído'),
                subtitle: Text('Pagamento: ${formatDateBr(receipt['payment_date'])}  •  Mês: '
                  '${receipt['reference_month'] == null ? '—' : _monthLabel(DateTime.parse(receipt['reference_month'].toString()))}'
                  '\nVencimento da mensalidade: ${_stayDueDateLabel(receipt['reference_month'])}'
                  '${(receipt['note']?.toString().isNotEmpty ?? false) ? '\n${receipt['note']}' : ''}'),
                isThreeLine: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(formatBrl((receipt['amount'] as num))),
                  if (canEdit || canDelete) PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? _editor(data,receipt) : _delete(receipt),
                    itemBuilder: (_) => [
                      if (canEdit) const PopupMenuItem(value:'edit',child: Text('Editar')),
                      if (canDelete) const PopupMenuItem(value:'delete',child: Text('Excluir')),
                    ],
                  ),
                ]),
              )),
          ])),
        floatingActionButton: canCreate ? FloatingActionButton(
          tooltip:'Novo recebimento',onPressed: () => _editor(data),
          child: const Icon(Icons.add)) : null,
      );
    },
  );
}

class _StayReceiptEditor extends StatefulWidget {
  final List<Map<String,dynamic>> clients;
  final Map<String,dynamic>? existing;
  final DateTime billingStart;
  const _StayReceiptEditor({required this.clients, required this.existing,
    required this.billingStart});

  @override
  State<_StayReceiptEditor> createState() => _StayReceiptEditorState();
}

class _StayReceiptEditorState extends State<_StayReceiptEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _paidAmount;
  late final TextEditingController _notes;
  String? _clientId;
  late DateTime _date;
  late DateTime _month;
  bool _saving = false;
  bool _loadingBalance = false;
  num? _amountOwed;
  num? _totalCharged;
  num? _totalPaid;
  String? _balanceError;
  List<Map<String,dynamic>> _monthlyCharges = [];
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    final old = widget.existing;
    _clientId = old?['client_id']?.toString();
    _date = DateTime.tryParse(old?['payment_date']?.toString() ?? '') ?? DateTime.now();
    _month = DateTime.tryParse(old?['reference_month']?.toString() ?? '') ?? DateTime(_date.year,_date.month,1);
    _paidAmount = TextEditingController(text: old?['amount']?.toString().replaceAll('.',',') ?? '');
    _notes = TextEditingController(text: old?['note']?.toString() ?? '');
    if (_clientId != null) _fetchBalance();
  }

  Future<void> _fetchBalance() async {
    final id = _clientId;
    final request = ++_requestSerial;
    if (id == null) {
      setState(() { _amountOwed = null; _balanceError = null; _loadingBalance = false; _monthlyCharges = []; });
      return;
    }
    setState(() { _loadingBalance = true; _balanceError = null; _monthlyCharges = []; });
    try {
      final db = Supabase.instance.client;
      final rows = await db.rpc('haras_client_stay_balance',
        params: {'p_client': id});
      final monthlyRows = await db.rpc('haras_client_stay_monthly_summary',
        params: {'p_client': id});
      if (!mounted || request != _requestSerial) return;
      final result = Map<String,dynamic>.from((rows as List).first as Map);
      // Meses com total zero (inclusive o mes inicial isento) nao aparecem
      // como vencimentos devidos no detalhamento financeiro.
      final months = (monthlyRows as List)
          .map((r) => Map<String,dynamic>.from(r as Map))
          .where((r) => ((r['total_charged'] as num?) ?? 0) > 0)
          .toList();
      setState(() {
        _totalCharged = result['total_charged'] as num;
        _totalPaid = result['total_paid'] as num;
        _amountOwed = result['balance'] as num;
        _monthlyCharges = months;
        _loadingBalance = false;
      });
    } catch (e) {
      if (!mounted || request != _requestSerial) return;
      setState(() { _balanceError = e.toString(); _loadingBalance = false; _amountOwed = null; _monthlyCharges = []; });
    }
  }

  @override
  void dispose() { _paidAmount.dispose(); _notes.dispose(); super.dispose(); }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(context:context,initialDate:_date,
      firstDate:DateTime(2000),lastDate:DateTime(2100));
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving || _loadingBalance || _balanceError != null) return;
    setState(() => _saving=true);
    try {
      final payload = <String,dynamic>{
        'client_id':_clientId,
        'payment_date':_isoDate(_date),
        'reference_month':_isoDate(_month),
        'due_date':_isoDate(stayChargeDueDate(_month)),
        'amount':parseBrl(_paidAmount.text),
        'note': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'payment_kind':'estadia',
      };
      final db=Supabase.instance.client;
      if (widget.existing == null) {
        await db.from('payments').insert(payload).select('id').single();
      } else {
        await db.from('payments').update(payload).eq('id',widget.existing!['id'])
            .eq('payment_kind','estadia').select('id').single();
      }
      if (mounted) Navigator.pop(context,true);
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Não foi possível salvar o recebimento: $e')));
    } finally {
      if (mounted) setState(() => _saving=false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nameAvailable=widget.clients.any((r)=>r['id'].toString()==_clientId);
    return AlertDialog(
      title: Text(widget.existing == null ? 'Novo recebimento de estadia' : 'Editar recebimento de estadia'),
      content: SizedBox(width: 540, child: SingleChildScrollView(child: Form(key:_form,
        child: Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(_clientId),
              initialValue: nameAvailable ? _clientId : null,
              isExpanded:true,
              decoration:const InputDecoration(labelText:'Cliente',border:OutlineInputBorder()),
              items: [for(final c in widget.clients) DropdownMenuItem(
                value:c['id'].toString(),
                child:Text('${c['client_number'] == null ? '' : '#${c['client_number']} • '}${c['name']}',
                  overflow:TextOverflow.ellipsis))],
              validator:(v)=>v == null ? 'Selecione o cliente' : null,
              onChanged:(v){setState(()=>_clientId=v);_fetchBalance();},
            ),
            const SizedBox(height:12),
            Card(child: Padding(padding:const EdgeInsets.all(14),child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                const Text('Quanto este cliente está devendo',
                  style:TextStyle(fontWeight:FontWeight.w600)),
                const SizedBox(height:6),
                if (_clientId == null) const Text('Selecione o cliente acima'),
                if (_loadingBalance) const LinearProgressIndicator(),
                if (_balanceError != null) Text('Erro ao calcular saldo: $_balanceError',
                  style:TextStyle(color:Theme.of(context).colorScheme.error)),
                if (!_loadingBalance && _amountOwed != null) ...[
                  Text(formatBrl((_amountOwed! > 0 ? _amountOwed! : 0)),
                    style:Theme.of(context).textTheme.headlineSmall),
                  if (_amountOwed! < 0) Text('Crédito disponível: ${formatBrl(-_amountOwed!)}'),
                  Text('Cobrado: ${formatBrl(_totalCharged ?? 0)}  •  '
                    'Pago: ${formatBrl(_totalPaid ?? 0)}',
                    style:Theme.of(context).textTheme.bodySmall),
                  if (_monthlyCharges.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Mensalidades por mês (vencimento dia 10)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                    for (final row in _monthlyCharges.take(6))
                      Text('${_monthLabel(DateTime.parse(row['reference_month'].toString()))} '
                        '• Vence ${_stayDueDateLabel(row['reference_month'])}: '
                        '${formatBrl(row['total_charged'] as num)}'),
                    if (_monthlyCharges.length > 6)
                      Text('E mais ${_monthlyCharges.length - 6} mês(es) anterior(es).',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ]))),
            const SizedBox(height:4),
            const Text('A data e o mês do pagamento não criam cobranças; '
              'elas são geradas pela data de entrada do animal.',
              style: TextStyle(fontSize: 12)),
            const SizedBox(height:12),
            OutlinedButton.icon(onPressed:_chooseDate,
              icon:const Icon(Icons.calendar_today),
              label:Text('Data de pagamento: ${formatDateBr(_isoDate(_date))}')),
            const SizedBox(height:12),
            OutlinedButton.icon(onPressed:() async {
              final selected=await _pickMonth(context,_month);
              if(selected!=null && mounted) setState(()=>_month=selected);
            },icon:const Icon(Icons.calendar_month),
              label:Text('Mês de pagamento: ${_monthLabel(_month)}')),
            const SizedBox(height:12),
            TextFormField(controller:_paidAmount,
              keyboardType:const TextInputType.numberWithOptions(decimal:true),
              decoration:const InputDecoration(labelText:'Valor pago (R\$)',
                border:OutlineInputBorder()),
              validator:(s){final amount=parseBrl(s??'');
                return amount == null || !amount.isFinite || amount <= 0
                  ? 'Informe um valor maior que zero' : null;
              }),
            const SizedBox(height:12),
            TextFormField(controller:_notes,maxLines:3,
              decoration:const InputDecoration(labelText:'Observações',border:OutlineInputBorder())),
          ],
        )))),
      actions: [
        TextButton(onPressed:_saving ? null : ()=>Navigator.pop(context,false),
          child:const Text('Cancelar')),
        FilledButton(onPressed:_saving || _loadingBalance || _balanceError != null ? null : _save,
          child:Text(_saving ? 'Salvando...' : 'Salvar recebimento')),
      ],
    );
  }
}
