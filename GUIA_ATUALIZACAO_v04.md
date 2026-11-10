# Haras F5E — Atualização v0.4 (Recebimento de estadia e Valores)

Esta atualização parte da **v0.3** que você já estava utilizando. Inclui as abas **Recebimento de estadia** e **Valores**, mantém a logo F5E e não apaga clientes, animais, funcionários ou pagamentos existentes ao instalar a migração SQL.

## 1. Antes de atualizar

1. Faça uma cópia da pasta atual do projeto Flutter.
2. Faça um **backup do banco Supabase** e confira que pode restaurá-lo.
3. No Supabase do **Haras F5E** (não no Team Penning), confirme que já executou as migrações anteriores: `01`, `03` e `04` (v0.3). A SQL nova depende das tabelas e colunas dessas versões.
4. Na aba **SQL Editor**, execute **somente** `supabase/05_recebimentos_valores_v04.sql`, incluído neste ZIP. **Não rode a SQL `01` novamente** em seu banco utilizado.
5. Aguarde o aviso de execução concluída. Se houver erro, a SQL usa transação: a migração é revertida, e você deve corrigir o erro antes de seguir.
6. Substitua o código Flutter usando a pasta `haras-f5e` deste ZIP. Se você alterou arquivos locais depois da v0.3, compare antes de sobrescrever.

## 2. Rodar no Windows

Abra a pasta do projeto atualizado no VS Code e execute:

```powershell
flutter clean
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA
```

Use as mesmas credenciais públicas (`sb_publishable_...`) que você já utiliza. Nunca use a chave secreta `service_role` no aplicativo.

Para gerar o APK (não precisa deixar o computador ligado depois da instalação):

```powershell
flutter build apk --release --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA
```

Arquivo gerado: `build\app\outputs\flutter-apk\app-release.apk`.

**Se as novas abas não aparecerem:** saia e entre novamente no aplicativo, ou toque em **Atualizar permissões**. Administrador e gerente podem visualizar/editar tarifas; financeiro pode consultá-las e registrar recebimentos. Outros perfis seguem bloqueados pela política do banco.

## 3. Aba Valores

| Serviço | Tarifa mensal inicial |
|---|---:|
| Hospedagem | R$ 1.000,00 |
| Reprodução | R$ 1.200,00 |
| Treinamento | R$ 1.400,00 |

Os preços podem ser editados pelo administrador/gerente, e a alteração recalcula **somente o mês atual**. Meses anteriores lançados no livro de cobrança são preservados.

**Para cada animal:**

- Valor padrão `R$ 1.400,00` por mês se nenhum serviço estiver marcado.
- Se um ou mais serviços estiverem marcados, **somente os serviços marcados são somados**; o valor padrão não é duplicado.
- Exemplo: hospedagem + treinamento = **R$ 2.400,00/mês**.
- Exemplo: só hospedagem = **R$ 1.000,00/mês**.
- Se a categoria do animal for **F5E Treinamento**, **F5E Hospedagem** ou **F5E Reprodução**, a cobrança mensal desse animal é **R$ 0,00**, ainda que tenha serviços marcados.
- A categoria especial e o valor-base do animal só podem ser alterados pelo administrador/gerente. Marcação de serviços segue a permissão da ficha do animal.

A cobrança só é gerada para animais associados a um **Cliente** e dentro do período da entrada/saída do haras, quando essas datas foram informadas.

## 4. Aba Recebimento de estadia

Ao tocar em **Novo recebimento**, o formulário aparece nesta ordem:

1. **Cliente** (escolha no cadastro).
2. **Quanto está devendo** — saldo automático, exibido logo abaixo. Se houver crédito, ele será mostrado separadamente.
3. **Data de pagamento** — dia, mês e ano.
4. **Mês de pagamento** — seletor somente de **mês e ano** (salvo internamente como dia 1).
5. **Valor pago (R$)** — aceita `1.400,00` ou `1400.00`.
6. **Observações** — opcional.

O recebimento fica guardado na **mesma tabela `payments`** que já possui seu histórico de pagamentos, identificado como `estadia`. Assim não há dois registros financeiros para o mesmo recebimento. Você pode consultar o recebimento também pela aba Pagamentos, mas só a nova aba tem os campos e o cálculo guiado do saldo.

**Saldo = mensalidades devidas desde o mês de ativação da v0.4 − pagamentos registrados a partir desse mês**. São considerados os pagamentos da aba antiga e os novos recebimentos de estadia para evitar duplicidade de baixa. Saldo negativo indica crédito. O cálculo soma todos os meses vencidos ou correntes, não apenas o mês escolhido no formulário.

### Proteção de dados existentes

- A SQL **não apaga** linhas de clientes, animais, pagamentos ou outras tabelas existentes.
- Os valores dos serviços só são inseridos se ainda não existirem: executar o SQL novamente não redefine as tarifas que você já editou.
- O primeiro mês de cobrança automática será o mês em que a migração for executada. Isso evita registrar dívidas automaticamente para meses históricos sem saber quais já foram acertados.
- O cliente só começa a dever pelos animais com proprietário atribuído, respeitando data de entrada/saída quando preenchida.
- Se um animal ou cliente for excluído depois, as mensalidades históricas permanecem como registro financeiro, embora sem o vínculo com o cadastro excluído.
- Antes de aceitar cobrança de um animal que já esteja no haras há meses, confira as datas de entrada e saída. Para meses anteriores à v0.4, será necessário fazer uma conciliação manual à parte se desejar trazê-los ao saldo.

### Limitação atual importante

As mensalidades de meses já fechados não são recalculadas quando uma tarifa ou serviço muda. Se um mês passou sem que o aplicativo registrasse a mensalidade, a próxima sincronização usará os preços vigentes quando fizer o lançamento desse mês. Evite alterar tarifas antes de abrir a aba Recebimento após a virada de mês, para manter a consistência das competências. A alteração de proprietário no meio de um mês não faz rateio proporcional: a cobrança inteira fica com o proprietário atual desse mês.

## 5. Teste sugerido com dados fictícios

1. Cadastre um cliente de teste.
2. Cadastre um animal para esse cliente, **sem serviço marcado**: aparecerá mensalidade de **R$ 1.400,00**.
3. Na aba **Recebimento de estadia**, selecione esse cliente e confira R$ 1.400,00 de saldo (se só existir esse animal e nenhum pagamento registrado a partir do início).
4. Lance um recebimento de **R$ 400,00** e confirme que o saldo passa para **R$ 1.000,00**.
5. Mude o animal para **F5E Treinamento**; o valor do mês atual será **R$ 0,00**. O recebimento de R$ 400,00 fica preservado e aparecerá como crédito, se não houver outras cobranças.
6. Teste com **Hospedagem + Reprodução**: mensalidade **R$ 2.200,00**.
7. Depois exclua somente seus cadastros fictícios de teste, tendo ciência de que as mensalidades financeiras históricas são preservadas por segurança.

## 6. Validação

O projeto e o SQL foram preparados com base no pacote v0.3 da conversa e verificados estruturalmente. **Não foi possível compilar o Flutter nem executar a migração em seu banco Supabase daqui**. Faça backup e valide no seu Android com registros de teste antes de usar com informações financeiras reais.
