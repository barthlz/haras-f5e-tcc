import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'modules.dart';

String formatBrl(num value) {
  final absValue = value.abs().toStringAsFixed(2).split('.');
  final whole = absValue.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => '.',
  );
  return '${value < 0 ? '-' : ''}R\$ $whole,${absValue.last}';
}

double? parseBrl(String raw) {
  final clean = raw.replaceAll('R\$', '').replaceAll(' ', '');
  final adjusted = clean.contains(',')
      ? clean.replaceAll('.', '').replaceAll(',', '.') : clean;
  return double.tryParse(adjusted);
}

class ValuesScreen extends StatefulWidget {
  final Permissions permissions;
  const ValuesScreen({super.key, required this.permissions});

  @override
  State<ValuesScreen> createState() => _ValuesScreenState();
}

class _ValuesScreenState extends State<ValuesScreen> {
  late Future<List<Map<String, dynamic>>> _prices;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _prices = Supabase.instance.client.from('stay_prices')
        .select('service,amount').order('service')
        .then((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    if (!widget.permissions.allows('valores', 'edit')) return;
    final value = TextEditingController(text: item['amount'].toString().replaceAll('.', ','));
    final key = GlobalKey<FormState>();
    final service = item['service'].toString();
    final edited = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Valor de $service'),
      content: Form(key: key, child: TextFormField(
        controller: value,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Valor mensal (R\$)',
          border: OutlineInputBorder()),
        validator: (s) {
          final amount = parseBrl(s ?? '');
          return amount == null || !amount.isFinite || amount < 0
              ? 'Informe um valor válido, igual ou maior que zero.' : null;
        },
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          if (key.currentState!.validate()) Navigator.pop(ctx, parseBrl(value.text));
        }, child: const Text('Salvar')),
      ],
    ));
    // O TextEditingController é descartado depois do fechamento da janela.
    if (edited == null || !mounted) return;
    try {
      await Supabase.instance.client.from('stay_prices').update({'amount': edited})
          .eq('service', service).select('service').single();
      if (!mounted) return;
      setState(_refresh);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Valor atualizado. Cobranças do mês atual foram recalculadas.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar valor: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = {'hospedagem': 'Hospedagem',
      'reproducao': 'Reprodução', 'treinamento': 'Treinamento'};
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _prices,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            Text('Erro ao carregar valores: ${snapshot.error}', textAlign: TextAlign.center),
            TextButton(onPressed: () => setState(_refresh), child: const Text('Tentar novamente')),
          ],
        ));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return RefreshIndicator(
          onRefresh: () async { setState(_refresh); await _prices; },
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('Tabela mensal de valores', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Ao marcar serviços no animal, o sistema soma os valores selecionados. '
              'Se nenhum serviço estiver marcado, vale o padrão de R\$ 1.400,00 por animal. '
              'O padrão não é somado novamente quando há serviços.'),
            const SizedBox(height: 12),
            for (final item in snapshot.requireData)
              Card(child: ListTile(
                title: Text(labels[item['service']] ?? item['service'].toString()),
                subtitle: Text(formatBrl((item['amount'] as num))),
                trailing: widget.permissions.allows('valores','edit')
                    ? const Icon(Icons.edit_outlined) : null,
                onTap: widget.permissions.allows('valores','edit') ? () => _edit(item) : null,
              )),
            const SizedBox(height: 16),
            Text('Categorias F5E sem custo', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final category in ['F5E Treinamento', 'F5E Hospedagem', 'F5E Reprodução'])
              ListTile(leading: const Icon(Icons.check_circle_outline),
                title: Text(category), trailing: const Text('R\$ 0,00')),
            const SizedBox(height: 8),
            const Text('Selecione a categoria F5E no cadastro do animal para que sua '
                'mensalidade seja gratuita, mesmo que tenha serviços marcados. '
                'A categoria e o valor-base só podem ser alterados por gerente ou administrador.'),
          ]),
        );
      },
    );
  }
}
