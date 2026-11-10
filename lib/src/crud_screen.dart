import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'modules.dart';
import '../core/utils/date_br.dart';
import 'deletion_dependencies.dart';
import 'values_screen.dart';

class CrudScreen extends StatefulWidget {
  final ModuleSpec module;
  final Permissions permissions;
  const CrudScreen({
    super.key,
    required this.module,
    required this.permissions,
  });

  @override
  State<CrudScreen> createState() => _CrudScreenState();
}

class _CrudScreenState extends State<CrudScreen> {
  late Future<List<Map<String, dynamic>>> _records;
  final Map<String, Map<String, String>> _referenceLabels = {};
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadReferenceLabels();
  }

  void _reload() {
    _records = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final result = await Supabase.instance.client
        .from(widget.module.table)
        .select()
        .order(widget.module.ordering, ascending: false)
        .limit(200);
    return result.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> _loadReferenceLabels() async {
    final specs = widget.module.fields.where(
      (f) => f.type == FieldType.reference && f.referenceTable != null,
    );
    for (final spec in specs) {
      final table = spec.referenceTable!;
      if (_referenceLabels.containsKey(table)) continue;
      try {
        final rows = await Supabase.instance.client
            .from(table)
            .select('id, name')
            .order('name')
            .limit(1000);
        if (!mounted) return;
        setState(
          () => _referenceLabels[table] = {
            for (final row in rows)
              row['id'].toString(): row['name'].toString(),
          },
        );
      } catch (_) {
        // Se a função não pode ler a tabela relacionada, não revelar os nomes.
      }
    }
  }

  String _describeValue(FormFieldSpec field, dynamic value) {
    if (value == null || value == '') return '—';
    switch (field.type) {
      case FieldType.boolean:
        return value == true ? 'Sim' : 'Não';
      case FieldType.reference:
        return _referenceLabels[field.referenceTable]?[value.toString()] ??
            'Não disponível';
      case FieldType.date:
        return formatDateBr(value);
      case FieldType.money:
        final number = double.tryParse(value.toString()) ?? 0;
        return 'R\$ ${number.toStringAsFixed(2).replaceAll('.', ',')}';
      default:
        return value.toString();
    }
  }

  String _titleFor(Map<String, dynamic> row) {
    final spec = widget.module.fields.firstWhere(
      (f) => f.key == widget.module.heading,
    );
    final heading = _describeValue(spec, row[widget.module.heading]);
    if (widget.module.id == 'pagamentos' && row['client_id'] == null) {
      final name = row['client_name_snapshot']?.toString();
      return name == null || name.isEmpty
          ? 'Cliente excluído (pagamento preservado)'
          : '$name (cliente excluído)';
    }
    if (widget.module.id == 'clientes') {
      final number = row['client_number']?.toString();
      if (number != null && number.isNotEmpty) return '#$number • $heading';
    }
    return heading;
  }

  Future<void> _openEditor([Map<String, dynamic>? existing]) async {
    final success = await showDialog<bool>(
      context: context,
      builder: (context) => RecordEditor(
        module: widget.module,
        existing: existing,
        referenceLabels: _referenceLabels,
        permissions: widget.permissions,
      ),
    );
    if (success == true && mounted) {
      setState(_reload);
      _loadReferenceLabels();
    }
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    if (_removing) return;
    setState(() => _removing = true);
    try {
      // O aviso é consultado ANTES da confirmação. Não excluir sem saber o
      // efeito sobre os vínculos, inclusive pagamentos e outras fichas.
      final impacts = await loadDeletionImpacts(
        widget.module.table,
        row['id'].toString(),
      );
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Você tem certeza que deseja excluir?'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Registro: "${_titleFor(row)}"'),
                  const SizedBox(height: 12),
                  if (impacts.isEmpty)
                    const Text('Nenhum registro vinculado foi encontrado.'),
                  if (impacts.isNotEmpty) ...[
                    const Text(
                      'A exclusão terá estes efeitos:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    for (final impact in impacts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text('• ${impact.description}'),
                      ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Essa ação é definitiva e não pode ser desfeita.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sim, excluir definitivamente'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final removed = await Supabase.instance.client
          .from(widget.module.table)
          .delete()
          .eq('id', row['id'])
          .select('id');
      if (removed.isEmpty) {
        throw StateError(
          'O banco não permitiu a exclusão. Confira suas permissões.',
        );
      }
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro excluído com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível concluir a exclusão: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = widget.permissions.allows(widget.module.id, 'create');
    final canEdit = widget.permissions.allows(widget.module.id, 'edit');
    final canDelete = widget.permissions.allows(widget.module.id, 'delete');
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _records,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Erro ao consultar ${widget.module.title}: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => setState(_reload),
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.requireData;
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _records;
            },
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${widget.module.title} (${items.length})',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      if (canCreate)
                        FilledButton.icon(
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.add),
                          label: const Text('Novo'),
                        ),
                    ],
                  ),
                ),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: Text('Nenhum registro encontrado.')),
                  ),
                for (final row in items)
                  Card(
                    child: ListTile(
                      title: Text(_titleFor(row)),
                      subtitle: Text(
                        widget.module.fields
                            .where((f) => f.key != widget.module.heading)
                            .take(3)
                            .map(
                              (f) =>
                                  '${f.label}: ${_describeValue(f, row[f.key])}',
                            )
                            .join('   •   '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: (canEdit || canDelete)
                          ? PopupMenuButton<String>(
                              onSelected: (choice) => choice == 'edit'
                                  ? _openEditor(row)
                                  : _remove(row),
                              itemBuilder: (context) => [
                                if (canEdit)
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Editar'),
                                  ),
                                if (canDelete)
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Excluir'),
                                  ),
                              ],
                            )
                          : null,
                      onTap: canEdit ? () => _openEditor(row) : null,
                    ),
                  ),
                if (items.length == 200)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      'Mostrando os 200 registros mais recentes. Paginação será incluída na próxima versão.',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              onPressed: () => _openEditor(),
              tooltip: 'Novo registro',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class RecordEditor extends StatefulWidget {
  final ModuleSpec module;
  final Map<String, dynamic>? existing;
  final Map<String, Map<String, String>> referenceLabels;
  final Permissions permissions;
  const RecordEditor({
    super.key,
    required this.module,
    this.existing,
    required this.referenceLabels,
    required this.permissions,
  });

  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _flags = {};
  final Map<String, String?> _references = {};
  final Map<String, List<Map<String, dynamic>>> _referenceOptions = {};
  bool _saving = false;
  Map<String, num>? _rates;

  @override
  void initState() {
    super.initState();
    if (widget.module.id == 'animais' &&
        widget.permissions.allows('valores', 'view')) {
      _loadRates();
    }
    for (final field in widget.module.fields) {
      final previous = widget.existing?[field.key];
      if (field.type == FieldType.boolean) {
        _flags[field.key] =
            previous == true || (previous == null && (field.key == 'active'));
      } else if (field.type == FieldType.reference ||
          field.type == FieldType.selection) {
        _references[field.key] =
            previous?.toString() ??
            (field.key == 'billing_category' ? 'Padrão' : null);
      } else {
        _controllers[field.key] = TextEditingController(
          text: previous == null
              ? (field.key == 'base_monthly_amount' ? '1400,00' : '')
              : field.type == FieldType.date
              ? formatDateBr(previous)
              : previous.toString(),
        );
      }
    }
    _loadOptions();
  }

  Future<void> _loadRates() async {
    try {
      final rows = await Supabase.instance.client
          .from('stay_prices')
          .select('service,amount');
      if (!mounted) return;
      setState(
        () => _rates = {
          for (final r in rows) r['service'].toString(): r['amount'] as num,
        },
      );
    } catch (_) {
      // Manter o formulario utilizavel se a leitura da tabela falhar.
    }
  }

  Future<void> _loadOptions() async {
    final tables = widget.module.fields
        .where((f) => f.type == FieldType.reference && f.referenceTable != null)
        .map((f) => f.referenceTable!)
        .toSet();
    for (final table in tables) {
      try {
        final rows = await Supabase.instance.client
            .from(table)
            .select('id, name')
            .order('name')
            .limit(1000);
        if (!mounted) return;
        setState(
          () => _referenceOptions[table] = rows
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao buscar opções de $table: $e')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(String key) async {
    final controller = _controllers[key]!;
    final current =
        DateTime.tryParse(dateBrToIso(controller.text) ?? '') ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      controller.text =
          '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year.toString().padLeft(4, '0')}';
    }
  }

  String? _validateText(String? value, FormFieldSpec field) {
    if (field.required && (value == null || value.trim().isEmpty)) {
      return 'Preenchimento obrigatório';
    }
    if (value == null || value.trim().isEmpty) return null;
    if (field.type == FieldType.digits && !validClientNumber(value.trim())) {
      return 'Use apenas números (ex.: 001 ou 25)';
    }
    if (field.type == FieldType.money &&
        (_parseMoney(value) == null ||
            !_parseMoney(value)!.isFinite ||
            _parseMoney(value)! < 0)) {
      return 'Informe um valor válido, não negativo';
    }
    if (field.type == FieldType.date && dateBrToIso(value) == null) {
      return 'Informe uma data válida (DD/MM/AAAA)';
    }
    if (field.type == FieldType.number && int.tryParse(value) == null) {
      return 'Informe um número inteiro';
    }
    return null;
  }

  double? _parseMoney(String raw) {
    final clean = raw.replaceAll('R\$', '').replaceAll(' ', '');
    final adjusted = clean.contains(',')
        ? clean.replaceAll('.', '').replaceAll(',', '.')
        : clean;
    return double.tryParse(adjusted);
  }

  Widget _field(FormFieldSpec field) {
    final priceLocked =
        widget.module.id == 'animais' &&
        (field.key == 'billing_category' ||
            field.key == 'base_monthly_amount') &&
        !widget.permissions.allows('valores', 'edit');
    if (priceLocked) {
      return ListTile(
        title: Text(field.label),
        subtitle: Text(
          field.key == 'billing_category'
              ? (_references[field.key] ?? 'Padrão')
              : formatBrl(
                  parseBrl(_controllers[field.key]?.text ?? '') ?? 1400,
                ),
        ),
        trailing: const Icon(Icons.lock_outline),
      );
    }
    if (field.type == FieldType.boolean) {
      return SwitchListTile(
        title: Text(field.label),
        value: _flags[field.key] ?? false,
        onChanged: (v) => setState(() => _flags[field.key] = v),
      );
    }
    if (field.type == FieldType.reference ||
        field.type == FieldType.selection) {
      final choices = field.type == FieldType.selection
          ? field.choices.map((e) => {'id': e, 'name': e}).toList()
          : (_referenceOptions[field.referenceTable] ?? []);
      final selection = _references[field.key];
      final historicalPaymentWithoutClient =
          widget.module.id == 'pagamentos' &&
          widget.existing != null &&
          field.key == 'client_id' &&
          widget.existing!['client_id'] == null;
      final requiredSelection =
          field.required && !historicalPaymentWithoutClient;
      final validValue = choices.any((r) => r['id'].toString() == selection)
          ? selection
          : null;
      // Animais cadastrados com espécies antigas não devem perder esse valor
      // quando o usuário editar qualquer outro campo do animal.
      final hasLegacySpecies =
          field.key == 'species' &&
          widget.existing != null &&
          selection != null &&
          selection.isNotEmpty &&
          validValue == null;
      return DropdownButtonFormField<String>(
        key: ValueKey('${field.key}-$validValue'),
        initialValue: validValue,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: field.label,
          helperText: hasLegacySpecies
              ? 'Espécie antiga: $selection. Escolha uma das 3 opções para substituir.'
              : null,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
        items: [
          if (!requiredSelection)
            DropdownMenuItem<String>(
              value: null,
              child: Text(
                historicalPaymentWithoutClient
                    ? 'Cliente excluído (manter histórico)'
                    : 'Não informar',
              ),
            ),
          ...choices.map(
            (r) => DropdownMenuItem<String>(
              value: r['id'].toString(),
              child: Text(
                r['name'].toString(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        validator: (v) => requiredSelection && (v == null || v.isEmpty)
            ? 'Selecione uma opção'
            : null,
        onChanged: (value) => setState(() => _references[field.key] = value),
      );
    }
    return TextFormField(
      controller: _controllers[field.key],
      onChanged: field.key == 'base_monthly_amount'
          ? (_) => setState(() {})
          : null,
      readOnly: field.type == FieldType.date,
      onTap: field.type == FieldType.date ? () => _pickDate(field.key) : null,
      keyboardType: field.type == FieldType.digits
          ? TextInputType.number
          : field.type == FieldType.money || field.type == FieldType.number
          ? const TextInputType.numberWithOptions(decimal: true)
          : (field.type == FieldType.date
                ? TextInputType.datetime
                : TextInputType.text),
      inputFormatters: field.type == FieldType.digits
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      maxLines: field.key == 'note' || field.key == 'address' ? 2 : 1,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.type == FieldType.date ? 'DD/MM/AAAA' : null,
        border: const OutlineInputBorder(),
        suffixIcon: field.type == FieldType.date
            ? const Icon(Icons.calendar_month)
            : null,
      ),
      validator: (v) => _validateText(v, field),
    );
  }

  Widget _animalChargePreview() {
    final rates = _rates;
    if (rates == null) return const SizedBox.shrink();
    final category = _references['billing_category'] ?? 'Padrão';
    final flags = <String, String>{
      'lodging_enabled': 'hospedagem',
      'breeding_enabled': 'reproducao',
      'training_enabled': 'treinamento',
    };
    final selected = flags.entries
        .where((e) => _flags[e.key] == true)
        .map((e) => e.value)
        .toList();
    final base =
        parseBrl(_controllers['base_monthly_amount']?.text ?? '1400') ?? 1400;
    final amount = category != 'Padrão'
        ? 0.0
        : selected.isEmpty
        ? base
        : selected.fold<double>(
            0,
            (sum, name) => sum + (rates[name] ?? 0).toDouble(),
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mensalidade estimada do animal',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              formatBrl(amount),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              category != 'Padrão'
                  ? 'Categoria F5E: sem cobrança'
                  : selected.isEmpty
                  ? 'Valor padrão, sem serviços marcados'
                  : 'Soma dos serviços: ${selected.join(', ')}',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final data = <String, dynamic>{};
      for (final field in widget.module.fields) {
        // Uma espécie legada, agora fora das três opções, permanece intacta
        // até que o usuário escolha explicitamente Equino, Bovino ou Suíno.
        if (widget.module.id == 'animais' &&
            widget.existing != null &&
            field.key == 'species' &&
            _references['species'] == widget.existing!['species'] &&
            !field.choices.contains(_references['species'])) {
          continue;
        }
        if (widget.module.id == 'animais' &&
            widget.existing != null &&
            !widget.permissions.allows('valores', 'edit') &&
            (field.key == 'billing_category' ||
                field.key == 'base_monthly_amount')) {
          continue;
        }
        if (field.type == FieldType.boolean) {
          data[field.key] = _flags[field.key] ?? false;
        } else if (field.type == FieldType.reference ||
            field.type == FieldType.selection) {
          data[field.key] = _references[field.key];
        } else {
          final raw = _controllers[field.key]!.text.trim();
          data[field.key] = raw.isEmpty
              ? null
              : field.type == FieldType.money
              ? _parseMoney(raw)
              : field.type == FieldType.number
              ? int.parse(raw)
              : field.type == FieldType.date
              ? dateBrToIso(raw)
              : raw;
        }
      }
      final client = Supabase.instance.client;
      if (widget.existing == null) {
        await client
            .from(widget.module.table)
            .insert(data)
            .select('id')
            .single();
      } else {
        await client
            .from(widget.module.table)
            .update(data)
            .eq('id', widget.existing!['id'])
            .select('id')
            .single();
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${widget.existing == null ? 'Novo' : 'Editar'} • ${widget.module.title}',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in widget.module.fields) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _field(field),
                  ),
                ],
                if (widget.module.id == 'animais') _animalChargePreview(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }
}
