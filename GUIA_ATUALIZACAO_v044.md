# Haras F5E v0.4.4 — primeiro mês de estadia sem cobrança

Esta atualização parte da **v0.4.3**. **Não é necessário criar outro projeto Supabase nem executar os scripts de criação inicial novamente.**

## Nova regra de cobrança

- O **mês de entrada do animal é isento**, independentemente de ter entrado nos dias 1, 10, 14, 30 ou 31.
- A primeira mensalidade é lançada **no mês calendário seguinte**, com vencimento no **dia 10** desse mês.
- Depois disso, a mensalidade se repete mês a mês enquanto o animal continuar hospedado, considerando a data de saída já cadastrada.
- Em caso de animais sem **Entrada no haras** informada, o sistema usa o mês de criação do cadastro, mas nunca retroage antes da configuração inicial de faturamento (`stay_billing_settings.billing_start_month`). **Para corrigir o início real**, preencha a data de entrada do animal.
- Serviços (hospedagem, reprodução, treinamento), valores em reais, categorias F5E com valor zero e lógica de pagamentos continuam iguais.

Exemplo com um animal padrão de **R$ 1.400,00**, entrada em **14/09/2026**:

| Mês de referência | Vencimento | Nova cobrança |
|---|---|---:|
| 09/2026 | Isento | R$ 0,00 |
| 10/2026 | 10/10/2026 | R$ 1.400,00 |
| 11/2026 | 10/11/2026 | R$ 1.400,00 |
| 12/2026 | 10/12/2026 | R$ 1.400,00 |

A competência (`reference_month`) continua armazenada internamente no formato ISO com dia `01`, e `stay_charges.due_date` continua no dia **10**. Isso evita duplicação e mantém as tabelas compatíveis.

## Passo a passo recomendado

1. **Faça backup do Supabase e uma cópia da pasta Flutter atual.** Trata-se de uma correção que muda saldos já calculados.
2. Entre no **Supabase → SQL Editor** do seu projeto atual.
3. Execute primeiro `supabase/10_previa_primeiro_mes_v044.sql` (ou o arquivo `Haras_F5E_v044_Previa_Saldos.sql` fornecido separadamente). Ele é **somente leitura** e lista os valores que serão retirados do saldo dos clientes.
4. Confirme se as datas de **Entrada no haras** dos animais estão corretas. Se um animal ficou hospedado antes do cadastro, informe sua data de entrada verdadeira no aplicativo **antes** de executar a atualização, se necessário. Execute a prévia novamente.
5. Quando os ajustes previstos estiverem corretos, execute **somente** `supabase/09_primeiro_mes_sem_cobranca_v044.sql` (ou `Haras_F5E_v044_Correcao_Supabase.sql`).
6. Abra o projeto Flutter v0.4.4 no VS Code e execute:

   ```powershell
   flutter clean
   flutter pub get
   flutter run --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA
   ```

7. Para instalar no celular, gere novamente o APK com `flutter build apk --release` e os mesmos dois `--dart-define` acima.
8. Em **Recebimento de estadia**, abra **Novo recebimento** e selecione um cliente para conferir **Cobrado**, **Pago**, o saldo e as mensalidades por mês. Use clientes de teste primeiro.

**Não reexecute os SQLs das versões anteriores nem substitua seu banco por um novo.**

## O que acontece com as mensalidades já geradas no mês de entrada?

A migração ajusta apenas as mensalidades de entrada dos animais ainda existentes no banco e identificáveis por data de entrada ou data de cadastro. Para segurança:

- Salva uma cópia do **valor e da descrição originais** em `public.stay_start_month_adjustments` (tabela restrita, consultável pelo administrador do banco no SQL Editor).
- **Zera** a cobrança lançada no mês de entrada (`stay_charges.amount = 0`). Não exclui a linha, permitindo rastrear a correção.
- **Não apaga nem modifica os pagamentos (`public.payments`)**. Um pagamento já registrado pelo primeiro mês poderá gerar crédito para o cliente, pois a cobrança associada deixou de existir. Confirme esse crédito antes de fazer novos acertos.
- Não modifica outras mensalidades passadas nem os preços registrados nelas.
- **Animais que já foram excluídos** e cujas mensalidades ficaram desvinculadas não podem ser ajustados automaticamente, pois não há mais a data de entrada para conferir. Revise esses casos manualmente se necessário.

### Consultas para conferir após atualizar

```sql
-- Valores originais das mensalidades isentadas:
select reference_month, animal_name_snapshot, original_amount, adjusted_at
from public.stay_start_month_adjustments
order by adjusted_at desc;

-- Não deve retornar mensalidades POSITIVAS para o mês de entrada
-- de animais ainda cadastrados:
select sc.reference_month, sc.animal_name_snapshot, sc.amount
from public.stay_charges sc
join public.animals a on a.id = sc.animal_id
join public.stay_billing_settings settings on settings.singleton = true
where sc.amount > 0
  and sc.reference_month = coalesce(
    date_trunc('month', a.arrival_date)::date,
    greatest(settings.billing_start_month,
      date_trunc('month', a.created_at at time zone 'America/Sao_Paulo')::date)
  );
```

## Validação

A revisão dos arquivos, a consistência dos cenários de cálculo e a integridade do ZIP foram verificadas. **Não foi possível compilar/executar o Flutter nem conectar ao Supabase deste projeto a partir deste ambiente**. Faça um teste com dados fictícios e confirme a prévia antes de aplicar o SQL em produção.
