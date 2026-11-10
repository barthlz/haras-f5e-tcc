# Haras F5E v0.4.3 — vencimento das mensalidades no dia 10

Esta versão parte da **v0.4.2**. O vencimento de todas as mensalidades da aba **Recebimento de estadia** passa a ser **dia 10 de cada mês**, em formato brasileiro (DD/MM/AAAA).

## Exemplo

| Competência | Vencimento da cobrança |
|---|---|
| Setembro/2026 | 10/09/2026 |
| Outubro/2026 | 10/10/2026 |
| Novembro/2026 | 10/11/2026 |

A **competência** continua armazenada no banco como `2026-10-01`, pois é apenas a chave do mês para evitar mensalidades duplicadas. O **vencimento** é `2026-10-10`, armazenado na nova coluna calculada `public.stay_charges.due_date` e exibido como **10/10/2026**.

> A data de entrada do animal e a data em que o cliente efetivamente pagou **não são alteradas**. O dia 10 é o vencimento fixo da mensalidade; ele não significa que o pagamento aconteceu nesse dia. A mensalidade do mês de entrada continua existindo mesmo se a entrada foi depois do dia 10, pois esta atualização **não muda a regra de competência** nem os valores da v0.4.2.

## Como atualizar, sem apagar informações

1. Faça **backup** do projeto e do Supabase. Use o mesmo projeto em que já aplicou a v0.4.2.
2. Entre no **Supabase → SQL Editor** e execute **apenas** o arquivo `supabase/08_vencimento_dia_10_v043.sql`. **Não reexecute** os scripts de criação inicial ou as versões anteriores.
3. Verifique no SQL Editor:

```sql
select reference_month, due_date, amount
from public.stay_charges
order by reference_month desc
limit 20;
```

O campo `due_date` deve mostrar sempre o dia `10`. Essa coluna é calculada pelo PostgreSQL e já funciona nos registros antigos; não é necessário gerar as cobranças novamente.

4. Abra o projeto v0.4.3 no VS Code e execute:

```powershell
flutter clean
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA
```

Para instalar no celular, gere novamente o APK com `flutter build apk --release` e os **mesmos** `--dart-define`.

5. No app, abra **Recebimento de estadia → Novo recebimento** e selecione um cliente. Em **Mensalidades por mês**, aparecerá o vencimento `10/MM/AAAA` de cada competência. Novos recebimentos salvos também passam a gravar o vencimento do mês escolhido no campo `payments.due_date`.

## O que muda e o que é preservado

- **Muda:** a data de vencimento das mensalidades de estadia, fixa no dia **10**.
- **Não muda:** valores (R$), somatórios e parcelas anteriores, clientes, animais, espécies, logo, categorias F5E, lançamentos de pagamentos, datas reais de entrada/saída e datas efetivas de pagamento.
- A atualização do SQL **não apaga nem atualiza pagamentos históricos**. Não cria novas mensalidades e não altera o saldo por si só.
- O aplicativo pode gerar a competência do mês atual antes do seu vencimento, como já fazia na v0.4.2. **Dia 10 é a data de vencimento**, não um agendamento de execução automática do banco nem uma notificação ao cliente.
- Caso a entrada do animal ocorra após o dia 10, a regra da v0.4.2 continua cobrando a competência desse mês com vencimento dia 10. Se você quiser que o **primeiro vencimento** seja no dia 10 do mês seguinte, isso precisa de outra regra de cobrança.

**Validação:** o pacote foi revisado e inclui teste de conversão da data, mas não foi possível compilar o Flutter ou executar o SQL no seu projeto Supabase por aqui. Teste primeiro com um cliente de exemplo.
