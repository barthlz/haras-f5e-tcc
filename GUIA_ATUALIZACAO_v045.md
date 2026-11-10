# Haras F5E — v0.4.5: nova aba Relatórios

Esta atualização foi preparada sobre o projeto **v0.4.4**, preservando os ícones, logo, arquivos Android, abas e a regra **mês de entrada isento / vencimento dia 10**. Não inclui os SQLs pontuais de Fernando G., porque devem ser aplicados separadamente e apenas após diagnóstico.

## O que faz

- Nova entrada **Relatórios** no menu lateral.
- Filtro de **mês inicial** e **mês final**, incluindo ambos.
- Lista de clientes ativos por nome ou número, com animais atuais, pagamento no período e saldo.
- Lista de **quem pagou no período** (por data real de pagamento) com valor, mês de referência, tipo (geral/estadia), observações e animais vinculados explicitamente ao pagamento.
- Ao tocar no cliente, mostra **quantos animais estão atualmente em seu nome**, nomes e entradas; **total cobrado, total já pago, pagamentos abatidos no saldo, dívida ou crédito**, o que foi cobrado no período (por animal/serviço) e o que foi recebido no mesmo período.
- Permissão de **somente consulta** para administrador, gerente e financeiro. Treinador e funcionário não recebem acesso a relatórios financeiros.
- A lista de pagamentos é paginada, com botão **Mostrar mais pagamentos**. A lista de clientes também é carregada em páginas.

**Importante sobre o saldo:** segue o cálculo já existente na aba **Recebimento de estadia**: cobrança registrada menos os pagamentos elegíveis para abatimento, conforme o mês de referência (ou a data, caso não informado). O total histórico pago inclui pagamentos antigos que podem não ter sido considerados no saldo. Por isso o relatório mostra os dois valores separadamente.

**Importante sobre “o que pagou”:** o cadastro de recebimento de estadia informa cliente, mês, valor e observação, mas não distribui pagamentos automaticamente entre animais ou serviços. O relatório apresenta separadamente **serviços cobrados** e **pagamentos recebidos**, indicando os animais somente se houver vínculo explícito no pagamento. Não presume quitação de um serviço individual.

## Instalação

1. **Faça backup** do projeto e do Supabase antes de qualquer atualização.
2. As migrações anteriores **até a v0.4.4** precisam estar aplicadas no seu banco. Não execute novamente o SQL de criação inicial (`01_estrutura_e_permissoes.sql`).
3. No **Supabase → SQL Editor**, execute **somente** `supabase/11_relatorios_v045.sql` do ZIP (ou o arquivo SQL avulso fornecido). A migração cria funções e permissões de leitura, não exclui clientes, animais, pagamentos ou mensalidades.
4. Extraia o ZIP em uma pasta nova e abra `haras-f5e` no VS Code. Preserve configurações que você tenha alterado depois da v0.4.4, caso existam.
5. Execute:

   ```powershell
   flutter clean
   flutter pub get
   flutter test
   flutter run --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA
   ```

6. Para gerar o APK instalável:

   ```powershell
   flutter build apk --release --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA
   ```

   O APK estará em `build/app/outputs/flutter-apk/app-release.apk`.
7. Saia e entre novamente no aplicativo ou toque em **Atualizar acesso** para carregar a permissão da nova aba.

## Como testar (sem modificar dados)

1. Entre como administrador e abra **Relatórios**.
2. Escolha, por exemplo, **setembro/2026 até novembro/2026**, e toque em **Consultar**.
3. Confira se os pagamentos aparecem pela **data em que foram recebidos**, independentemente do mês de referência.
4. Busque um cliente, como **Joares**, por nome; toque no resultado.
5. Confira os animais vinculados, o total pago, a dívida/crédito e as cobranças discriminadas por animal e mês.
6. Compare o saldo ao mostrado em **Recebimento de estadia** após abrir essa aba para sincronizar as mensalidades.
7. Teste uma conta com função treinador: a aba **Relatórios** não deverá aparecer.

## Cuidados

- O relatório **não altera** pagamentos nem cadastros. Na primeira abertura ele solicita a sincronização normal de mensalidades já usada pela tela de recebimentos; isso pode gerar cobranças de meses ainda não registrados conforme a regra vigente. Por isso é recomendável conferir o saldo antes e depois.
- Se os dados do cliente tiverem sido excluídos, pagamentos ainda aparecem na lista de **Quem pagou no período** pelo nome histórico, mas não existe ficha de cliente ativo para abrir.
- O relatório não confirma automaticamente uma baixa por animal. Se precisar disso no futuro, será necessário criar um controle de alocação dos recebimentos.
- Uma diferença entre total histórico pago e pagamentos abatidos no saldo pode ocorrer quando existem recebimentos antigos de antes do início do faturamento da estadia.
- Caso tenha feito mudanças no código após a v0.4.4, compare os arquivos antes de substituir seu projeto inteiro.

**Validação:** arquivos e estrutura conferidos. Não foi possível rodar Flutter nem consultar seu projeto Supabase neste ambiente; valide o SQL em um ambiente de testes e confira os saldos antes de usar o relatório em decisões financeiras.
