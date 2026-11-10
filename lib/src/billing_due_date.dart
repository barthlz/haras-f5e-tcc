/// Dia fixo para o vencimento da mensalidade de estadia.
/// O mes de referencia e salvo no banco com dia 01, mas o vencimento e dia 10.
DateTime stayChargeDueDate(DateTime referenceMonth) =>
    DateTime(referenceMonth.year, referenceMonth.month, 10);
