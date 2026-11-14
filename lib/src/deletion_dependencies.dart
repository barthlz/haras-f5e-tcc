import 'package:supabase_flutter/supabase_flutter.dart';

/// Descreve o que o banco fará automaticamente ao excluir um registro.
/// Esta lista precisa continuar alinhada com supabase/04_exclusao_com_vinculos.sql.
class LinkedRecordRule {
  final String table;
  final String foreignKey;
  final String label;
  final String outcome;

  const LinkedRecordRule(this.table, this.foreignKey, this.label, this.outcome);
}

class LinkedRecordImpact {
  final LinkedRecordRule rule;
  final int count;

  const LinkedRecordImpact(this.rule, this.count);

  String get description => '$count ${rule.label}: ${rule.outcome}.';
}

/// Exclusão de cliente preserva dados financeiros e animais, removendo apenas
/// o vínculo. Exclusão de animal remove as fichas que dependem dele, mas NÃO
/// remove pagamentos: apenas o vínculo entre o animal e o pagamento.
const deletionRules = <String, List<LinkedRecordRule>>{
  'clients': [
    LinkedRecordRule(
      'stay_charges',
      'client_id',
      'mensalidade(s) de estadia',
      'serão preservadas no histórico, sem vínculo com o cliente',
    ),
    LinkedRecordRule(
      'payments',
      'client_id',
      'pagamento(s)',
      'serão preservados, com o cliente desvinculado',
    ),
    LinkedRecordRule(
      'animals',
      'owner_client_id',
      'animal(is)',
      'continuarão cadastrados, mas sem proprietário',
    ),
    LinkedRecordRule(
      'client_dependents',
      'client_id',
      'dependente(s)',
      'serão excluídos junto com o cliente',
    ),
  ],
  'animals': [
    LinkedRecordRule(
      'stay_charges',
      'animal_id',
      'mensalidade(s) de estadia',
      'serão preservadas no histórico, sem vínculo com o animal',
    ),
    LinkedRecordRule(
      'payment_animals',
      'animal_id',
      'vínculo(s) com pagamentos',
      'serão removidos, mas os pagamentos serão preservados',
    ),
    LinkedRecordRule(
      'lodgings',
      'animal_id',
      'ficha(s) de hospedagem',
      'serão excluídas',
    ),
    LinkedRecordRule(
      'training_sessions',
      'animal_id',
      'ficha(s) de treinamento',
      'serão excluídas',
    ),
    LinkedRecordRule(
      'breeding_records',
      'animal_id',
      'ficha(s) de reprodução',
      'serão excluídas',
    ),
    LinkedRecordRule(
      'embryo_transfers',
      'animal_id',
      'transferência(s) de embrião',
      'serão excluídas',
    ),
    LinkedRecordRule(
      'animal_exams',
      'animal_id',
      'exame(s)',
      'serão excluídos',
    ),
  ],
  'payments': [
    LinkedRecordRule(
      'payment_animals',
      'payment_id',
      'vínculo(s) com animais',
      'serão removidos; os animais continuarão cadastrados',
    ),
  ],
  'breeding_records': [
    LinkedRecordRule(
      'embryo_transfers',
      'breeding_record_id',
      'transferência(s) de embrião',
      'serão preservadas, mas sem referência à ficha de reprodução',
    ),
  ],
};

/// Falhar fechado: se não for possível calcular impactos, não exibir confirmação
/// de exclusão que possa deixar de avisar sobre registros afetados.
Future<List<LinkedRecordImpact>> loadDeletionImpacts(
  String table,
  String recordId,
) async {
  final rules = deletionRules[table] ?? const <LinkedRecordRule>[];
  final client = Supabase.instance.client;
  final impacts = await Future.wait(
    rules.map((rule) async {
      final count = await client
          .from(rule.table)
          .count(CountOption.exact)
          .eq(rule.foreignKey, recordId);
      return LinkedRecordImpact(rule, count);
    }),
  );
  return impacts.where((item) => item.count > 0).toList();
}
