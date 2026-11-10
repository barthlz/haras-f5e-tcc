import 'package:flutter_test/flutter_test.dart';
import 'package:haras_f5e/src/modules.dart';
import 'package:haras_f5e/src/date_br.dart';
import 'package:haras_f5e/src/billing_due_date.dart';

void main() {
  test('As permissões ausentes negam acesso', () {
    final perms = Permissions.fromRows([
      {'module': 'clientes', 'can_view': true, 'can_create': false,
        'can_edit': false, 'can_delete': false},
    ]);
    expect(perms.allows('clientes', 'view'), isTrue);
    expect(perms.allows('clientes', 'create'), isFalse);
    expect(perms.allows('despesas', 'view'), isFalse);
  });

  test('Os nove formulários principais estão registrados', () {
    expect(modules.map((module) => module.id), containsAll([
      'clientes', 'animais', 'despesas', 'funcionarios', 'pagamentos',
      'hospedagem', 'treinamento', 'reproducao', 'exames',
    ]));
  });

  test('O cliente tem número em texto, com zeros à esquerda', () {
    final clientes = modules.firstWhere((m) => m.id == 'clientes');
    expect(clientes.fields.any((f) => f.key == 'client_number' &&
        f.type == FieldType.digits), isTrue);
    expect(validClientNumber('00025'), isTrue);
    expect(validClientNumber('25A'), isFalse);
  });

  test('Animal possui seletor de espécies', () {
    final animais = modules.firstWhere((m) => m.id == 'animais');
    final especie = animais.fields.firstWhere((f) => f.key == 'species');
    expect(especie.type, FieldType.selection);
    expect(especie.choices, ['Equino', 'Bovino', 'Suíno']);
  });

  test('Datas brasileiras são mostradas sem alterar o formato do banco', () {
    expect(formatDateBr('2026-10-14'), '14/10/2026');
    expect(formatDateBr('2026-10-14T00:00:00'), '14/10/2026');
    expect(formatDateBr(null), '—');
    expect(dateBrToIso('14/10/2026'), '2026-10-14');
    expect(dateBrToIso('2026-10-14'), '2026-10-14');
    expect(dateBrToIso('31/02/2026'), isNull);
  });

  test('Animal tem valor-base e categorias F5E sem custo', () {
    final animais = modules.firstWhere((m) => m.id == 'animais');
    final base = animais.fields.firstWhere((f) => f.key == 'base_monthly_amount');
    final categoria = animais.fields.firstWhere((f) => f.key == 'billing_category');
    expect(base.type, FieldType.money);
    expect(base.required, isTrue);
    expect(categoria.type, FieldType.selection);
    expect(categoria.choices, containsAll([
      'Padrão','F5E Treinamento','F5E Hospedagem','F5E Reprodução',
    ]));
  });
  test('Mensalidades vencem sempre no dia 10, mesmo quando entrada foi dia 30', () {
    expect(formatDateBr(stayChargeDueDate(DateTime(2026, 9, 30))),
        '10/09/2026');
    expect(formatDateBr(stayChargeDueDate(DateTime(2026, 10, 1))),
        '10/10/2026');
    expect(formatDateBr(stayChargeDueDate(DateTime(2026, 12, 30))),
        '10/12/2026');
  });

}
