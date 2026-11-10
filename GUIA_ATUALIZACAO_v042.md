# Haras F5E — v0.4.2 | Correção do saldo de mensalidades acumuladas

Esta versão parte da **v0.4.1** e corrige a dívida na aba **Recebimento de estadia**.

## Qual era o problema?

Na v0.4, o banco limitava as mensalidades ao **mês em que a v0.4 foi instalada**. Se dois animais custassem R$ 1.400 por mês, mudar a data de entrada de 30/10/2026 para 30/09/2026 não acrescentava setembro: continuavam R$ 2.800.

## Nova regra

- Se o animal tem **Entrada no haras**, o primeiro mês cobrado é **aquele mês**, inclusive quando a entrada aconteceu no dia 30.
- As mensalidades são geradas para **todos os meses até o mês atual**, respeitando a **Saída do haras**, se registrada.
- Se a entrada estiver **em branco**, continua valendo o mês de instalação da v0.4 (para não inventar uma data histórica).
- Uma competência por animal/mês. A sincronização repetida não duplica cobranças; meses anteriores já lançados não são recalculados automaticamente.
- Categorias F5E continuam com mensalidade **R$ 0,00**.
- A dívida corresponde à soma das mensalidades menos os pagamentos registrados para o período. Pagamentos com *Mês de referência* usam esse mês; sem referência, usam a data de pagamento.
- O saldo não muda ao alterar apenas **Data de pagamento** ou **Mês de pagamento** no formulário de recebimento. A origem das mensalidades é a **Entrada no haras** do cadastro do animal.

### Exemplo, sem pagamentos

| Entrada | Animais | Competências | Saldo |
| --- | ---: | --- | ---: |
| 30/10/2026 | 2 x R$ 1.400 | Outubro | R$ 2.800 |
| 30/09/2026 | 2 x R$ 1.400 | Setembro + Outubro | R$ 5.600 |
| 30/08/2026 | 2 x R$ 1.400 | Agosto + Setembro + Outubro | R$ 8.400 |

Ao abrir **Novo recebimento**, o app também mostrará os valores de cada mês (últimos seis meses, se houver muitos) para facilitar a conferência.

## Instalação SEM perder o banco

1. **Faça backup** do projeto Flutter e do banco Supabase; confira se o backup pode ser restaurado.
2. No Supabase → **SQL Editor**, rode primeiro `supabase/07_previa_cobrancas_retroativas.sql`. Essa é uma consulta **somente de leitura** e mostrará, por cliente/animal, quantos meses e qual valor **estimado** será acrescentado. Se mostrar anos de cobrança indevidos, corrija as datas de entrada e saída dos animais **antes de seguir**.
3. **Confira pagamentos históricos**, pois retroagir cobranças pode exigir conciliação de pagamentos já realizados. A prévia usa os serviços e preços atuais para estimar o passado; se os serviços/preços mudaram, valide o cálculo antes de usar financeiramente.
4. Execute **somente** `supabase/06_corrigir_mensalidades_acumuladas_v042.sql` no **mesmo banco**, após v0.4. Não execute `01_estrutura_e_permissoes.sql` novamente. A migração altera as funções; **não exclui clientes, animais ou pagamentos**.
5. Abra o código da v0.4.2 no VS Code e use as mesmas credenciais públicas do Supabase:

```powershell
flutter clean
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA
```

Para instalar no celular sem depender do computador, gere um APK com `flutter build apk --release` e os mesmos `--dart-define`.

6. Com o aplicativo atualizado, abra **Recebimento de estadia**: ao entrar nessa aba, a sincronização criará as **mensalidades antigas ainda não lançadas**. **Isso altera os saldos financeiros**, mas não apaga cadastros ou pagamentos.
7. Entre em **Novo recebimento**, selecione o cliente e veja o saldo e a seção **Mensalidades por mês**.

### Observações importantes

- Alterações posteriores na data de entrada para uma data **mais recente** não apagam automaticamente mensalidades passadas já registradas; revisar essa situação antes de efetuar cobranças.
- Se o proprietário ou os serviços de um animal mudaram no passado, as mensalidades não lançadas podem usar o proprietário e os preços/serviços **atuais**, pois o sistema anterior não armazenava um histórico de cada mudança. Confira essas situações manualmente.
- Não é necessário nem recomendável alterar diretamente `stay_billing_settings` para resolver o problema.
- A execução da migração **não** cria mensalidades retroativas imediatamente; elas serão geradas quando a aba for aberta ou quando a função de sincronização for chamada.
- O projeto e a sintaxe do SQL foram revisados, mas **não foi possível rodar o Flutter nem executar o SQL no seu Supabase** neste ambiente. Faça testes com dados fictícios e valide o saldo antes de usar para cobranças reais.
