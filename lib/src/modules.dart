/// Os identificadores dos módulos devem ser iguais aos do SQL (RLS).
enum FieldType {
  text,
  date,
  money,
  number,
  boolean,
  reference,
  selection,
  digits,
}

class FormFieldSpec {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final String? referenceTable;
  final List<String> choices;

  const FormFieldSpec(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.referenceTable,
    this.choices = const [],
  });
}

class ModuleSpec {
  final String id;
  final String title;
  final String table;
  final String ordering;
  final String heading;
  final List<FormFieldSpec> fields;

  const ModuleSpec(
    this.id,
    this.title,
    this.table,
    this.ordering,
    this.heading,
    this.fields,
  );
}

const modules = <ModuleSpec>[
  ModuleSpec('clientes', 'Clientes', 'clients', 'created_at', 'name', [
    FormFieldSpec('name', 'Nome completo', required: true),
    FormFieldSpec('client_number', 'Número do cliente', type: FieldType.digits),
    FormFieldSpec('birth_date', 'Data de nascimento', type: FieldType.date),
    FormFieldSpec('cpf', 'CPF'),
    FormFieldSpec('address', 'Endereço'),
  ]),
  ModuleSpec('animais', 'Animais', 'animals', 'created_at', 'name', [
    FormFieldSpec('name', 'Nome do animal', required: true),
    FormFieldSpec(
      'species',
      'Espécie',
      type: FieldType.selection,
      choices: ['Equino', 'Bovino', 'Suíno'],
    ),
    FormFieldSpec(
      'sex',
      'Sexo',
      type: FieldType.selection,
      choices: ['Macho', 'Fêmea'],
    ),
    FormFieldSpec('birth_date', 'Nascimento', type: FieldType.date),
    FormFieldSpec(
      'owner_client_id',
      'Proprietário',
      type: FieldType.reference,
      referenceTable: 'clients',
    ),
    FormFieldSpec('arrival_date', 'Entrada no haras', type: FieldType.date),
    FormFieldSpec(
      'training_enabled',
      'Em treinamento',
      type: FieldType.boolean,
    ),
    FormFieldSpec('breeding_enabled', 'Em reprodução', type: FieldType.boolean),
    FormFieldSpec('lodging_enabled', 'Em hospedagem', type: FieldType.boolean),
    FormFieldSpec(
      'billing_category',
      'Categoria de cobrança',
      type: FieldType.selection,
      choices: [
        'Padrão',
        'F5E Treinamento',
        'F5E Hospedagem',
        'F5E Reprodução',
      ],
      required: true,
    ),
    FormFieldSpec(
      'base_monthly_amount',
      'Valor padrão por animal (R\$)',
      type: FieldType.money,
      required: true,
    ),
    FormFieldSpec('departure_date', 'Saída do haras', type: FieldType.date),
  ]),
  ModuleSpec(
    'despesas',
    'Despesas',
    'expenses',
    'expense_date',
    'description',
    [
      FormFieldSpec(
        'expense_date',
        'Data',
        type: FieldType.date,
        required: true,
      ),
      FormFieldSpec('category', 'Categoria', required: true),
      FormFieldSpec('description', 'Descrição', required: true),
      FormFieldSpec(
        'amount',
        'Valor (R\$)',
        type: FieldType.money,
        required: true,
      ),
      FormFieldSpec('paid', 'Pago', type: FieldType.boolean),
      FormFieldSpec('note', 'Observações'),
    ],
  ),
  ModuleSpec(
    'funcionarios',
    'Funcionários',
    'employees',
    'created_at',
    'name',
    [
      FormFieldSpec('name', 'Nome completo', required: true),
      FormFieldSpec('job_title', 'Função / cargo', required: true),
      FormFieldSpec('hire_date', 'Admissão', type: FieldType.date),
      FormFieldSpec('phone', 'Telefone'),
      FormFieldSpec('active', 'Ativo', type: FieldType.boolean),
    ],
  ),
  ModuleSpec(
    'pagamentos',
    'Pagamentos',
    'payments',
    'payment_date',
    'client_id',
    [
      FormFieldSpec(
        'client_id',
        'Cliente',
        type: FieldType.reference,
        referenceTable: 'clients',
        required: true,
      ),
      FormFieldSpec(
        'payment_date',
        'Data de pagamento',
        type: FieldType.date,
        required: true,
      ),
      FormFieldSpec(
        'reference_month',
        'Mês de referência (escolha dia 01)',
        type: FieldType.date,
      ),
      FormFieldSpec('due_date', 'Data de vencimento', type: FieldType.date),
      FormFieldSpec(
        'amount',
        'Valor pago (R\$)',
        type: FieldType.money,
        required: true,
      ),
      FormFieldSpec('note', 'Observações'),
    ],
  ),
  ModuleSpec(
    'hospedagem',
    'Hospedagem',
    'lodgings',
    'created_at',
    'animal_id',
    [
      FormFieldSpec(
        'animal_id',
        'Animal',
        type: FieldType.reference,
        referenceTable: 'animals',
        required: true,
      ),
      FormFieldSpec('diet', 'Dieta'),
      FormFieldSpec('location', 'Baia / local'),
      FormFieldSpec('start_date', 'Início', type: FieldType.date),
      FormFieldSpec('end_date', 'Fim', type: FieldType.date),
    ],
  ),
  ModuleSpec(
    'treinamento',
    'Treinamento',
    'training_sessions',
    'created_at',
    'animal_id',
    [
      FormFieldSpec(
        'animal_id',
        'Animal',
        type: FieldType.reference,
        referenceTable: 'animals',
        required: true,
      ),
      FormFieldSpec('training_type', 'Tipo de treinamento', required: true),
      FormFieldSpec(
        'training_days',
        'Dias de treinamento',
        type: FieldType.number,
      ),
      FormFieldSpec('diet', 'Dieta'),
      FormFieldSpec('start_date', 'Início', type: FieldType.date),
      FormFieldSpec('end_date', 'Fim', type: FieldType.date),
    ],
  ),
  ModuleSpec(
    'reproducao',
    'Reprodução',
    'breeding_records',
    'created_at',
    'animal_id',
    [
      FormFieldSpec(
        'animal_id',
        'Animal',
        type: FieldType.reference,
        referenceTable: 'animals',
        required: true,
      ),
      FormFieldSpec('season', 'Estação'),
      FormFieldSpec('cover_date', 'Data da cobertura', type: FieldType.date),
      FormFieldSpec('stallion', 'Garanhão'),
      FormFieldSpec(
        'pregnancy_confirmed',
        'Gestação confirmada',
        type: FieldType.boolean,
      ),
      FormFieldSpec('te_result', 'Resultado TE / lavado'),
      FormFieldSpec('foaling_date', 'Data do parto', type: FieldType.date),
      FormFieldSpec('foal_sex', 'Sexo do potro'),
    ],
  ),
  ModuleSpec('exames', 'Exames', 'animal_exams', 'created_at', 'animal_id', [
    FormFieldSpec(
      'animal_id',
      'Animal',
      type: FieldType.reference,
      referenceTable: 'animals',
      required: true,
    ),
    FormFieldSpec('exam_name', 'Exame', required: true),
    FormFieldSpec('sample_date', 'Data da coleta', type: FieldType.date),
    FormFieldSpec('expires_on', 'Vencimento', type: FieldType.date),
  ]),
];

class Permissions {
  final Map<String, Map<String, bool>> _values;
  Permissions(this._values);

  factory Permissions.fromRows(List<dynamic> rows) {
    final result = <String, Map<String, bool>>{};
    for (final item in rows) {
      final row = Map<String, dynamic>.from(item as Map);
      final name = row['module'] as String;
      result[name] = {
        'view': row['can_view'] == true,
        'create': row['can_create'] == true,
        'edit': row['can_edit'] == true,
        'delete': row['can_delete'] == true,
      };
    }
    return Permissions(result);
  }

  bool allows(String module, String operation) =>
      _values[module]?[operation] == true;
}

class ProfileState {
  final String fullName;
  final String role;
  final String status;
  final Permissions permissions;

  const ProfileState({
    required this.fullName,
    required this.role,
    required this.status,
    required this.permissions,
  });
}

/// Número do cliente é um código, não uma quantidade: mantém zeros à esquerda.
bool validClientNumber(String value) => RegExp(r'^[0-9]+$').hasMatch(value);
