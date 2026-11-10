# Atualização v0.4.3 — vencimento de estadia sempre dia 10

Rode **apenas** `supabase/08_vencimento_dia_10_v043.sql` após a v0.4.2. As mensalidades continuam acumulando normalmente; a nova coluna `stay_charges.due_date` traz o vencimento fixo no dia 10, inclusive para os registros já existentes. Consulte [GUIA_ATUALIZACAO_v043.md](GUIA_ATUALIZACAO_v043.md).

---

# Atualização v0.4.2 — saldo acumulado de estadia

**Importante:** esta versão inclui uma migração nova no Supabase. Rode **primeiro a prévia** `supabase/07_previa_cobrancas_retroativas.sql`, confira o impacto financeiro e só depois aplique `supabase/06_corrigir_mensalidades_acumuladas_v042.sql`.

Veja [GUIA_ATUALIZACAO_v042.md](GUIA_ATUALIZACAO_v042.md) para todos os passos. Mantém a logo, clientes, animais, pagamentos e funcionalidades da v0.4.1.

---

# Atualização v0.4.1

Espécies selecionáveis: Equino, Bovino e Suíno. Datas exibidas em DD/MM/AAAA; armazenamento no Supabase segue ISO (AAAA-MM-DD). Veja `GUIA_ATUALIZACAO_v041.md`.

# Haras F5E — aplicativo Android em Flutter + Supabase

**Versão 0.4.0 — código-fonte para Flutter Android (não é APK compilado).**

Este pacote foi preparado com base no arquivo `APP Haras F5E.xlsx` enviado na conversa. Contém a aplicação Flutter, esquema do banco de dados, cadastro com e-mail/senha, login, aprovação por administrador e permissões reais por função no PostgreSQL/Supabase (Row Level Security — RLS).

**Para atualizar um banco existente da v0.3, consulte `GUIA_ATUALIZACAO_v04.md` e execute apenas `supabase/05_recebimentos_valores_v04.sql` após backup.**

## O que já funciona no código

- Cadastro de conta com **nome + e-mail + senha**, login e logout.
- Conta nova fica **PENDENTE** e **não vê dados** até ser aprovada.
- O **administrador** aprova, bloqueia e define as funções dos usuários.
- A tela **Resumo** conta os registros que aquela função pode consultar.
- Telas de **Clientes, Animais, Despesas, Funcionários, Pagamentos, Hospedagem, Treinamento, Reprodução e Exames** com listagem, cadastro e edição (e exclusão para os perfis autorizados).
- Seleção do cliente ao cadastrar animal/pagamento e seleção de animal nas fichas.
- **Recebimento de estadia**: cliente, saldo automático, data, mês/ano, valor pago e observações.
- **Valores**: Hospedagem R$ 1.000, Reprodução R$ 1.200, Treinamento R$ 1.400; categorias F5E gratuitas, valor-base do animal R$ 1.400.
- Proteção das tabelas no Supabase, independentemente de esconder botões na interface.

**Funcionalidades preparadas no banco, mas ainda sem tela específica nesta primeira versão:** dependentes dos clientes (`client_dependents`), animais vinculados individualmente a cada pagamento (`payment_animals`), e fichas de receptoras de embrião (`embryo_transfers`). Também faltam importação de dados do Excel, cálculo automático de referência/vencimento, alertas de exames, filtros avançados, anexos, gráficos financeiros, backup operacional e paginação completa (listas mostram 200 registros).

> Não é um aplicativo de produção já validado: a compilação e os testes em emulador/celular dependem do ambiente Flutter no seu computador. Use dados de teste antes de cadastrar CPFs, dados de funcionários e informações financeiras reais.

## 1. Verificar o Flutter e Android Studio (Windows)

Abra o **terminal do VS Code (PowerShell)**:

```powershell
flutter --version
flutter doctor
flutter devices
```

Para este projeto, utilize uma versão recente do Flutter cujo Dart seja **3.9 ou superior**, exigido pela versão da biblioteca `supabase_flutter` utilizada. No Android Studio, configure um emulador Android ou conecte seu telefone Android com **depuração USB** habilitada.

## 2. Criar o aplicativo Flutter

Em uma pasta onde deseja criar o aplicativo:

```powershell
flutter create --platforms=android haras_f5e
cd haras_f5e
code .
```

**Descompacte os arquivos deste ZIP por cima da pasta `haras_f5e`**. Confirme a substituição de `pubspec.yaml` e da pasta `lib`. **Não apague** a pasta Android gerada pelo Flutter.

Para permitir a conexão à internet, edite:

`android/app/src/main/AndroidManifest.xml`

Logo após a abertura da tag `<manifest ...>`, inclua:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Depois execute:

```powershell
flutter pub get
flutter test test/widget_test.dart
```

## 3. Criar um NOVO projeto no Supabase

Crie um projeto novo, por exemplo `haras-f5e`. **Não execute o SQL no projeto `team-penning-f5e`** nem em outro banco com tabelas em uso. Em **SQL Editor > New query**, cole o conteúdo de:

`supabase/01_estrutura_e_permissoes.sql`

Execute o script. Ele cria tabelas, funções de autenticação, as permissões e RLS. A planilha original **não tem cadastros preenchidos**: este pacote cria a estrutura, mas não importa pessoas/animais reais.

Em **Authentication > Providers > Email**, confira se o login por e-mail está habilitado. O Supabase normalmente solicita confirmação por e-mail. Se estiver ligada, confirme o e-mail para fazer login. **Não desabilite a confirmação por e-mail em produção.**

## 4. Inserir URL e chave pública (sem senha secreta)

No Supabase, abra **Project Settings / API Keys** ou **Connect**. Copie:

- **Project URL** (exemplo: `https://SEU-PROJETO.supabase.co`)
- **Publishable key** (exemplo: `sb_publishable_...`)

**Use apenas a publishable key no aplicativo. Nunca cole `service_role`, `secret key` ou senha do banco.**

Execute no terminal, substituindo pelos seus valores:

```powershell
flutter run --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_SUA_CHAVE
```

Se houver múltiplos dispositivos, o Flutter mostrará a escolha; use `flutter devices` e, se necessário, passe `-d ID_DO_DISPOSITIVO`.

## 5. Criar a primeira conta de administrador

1. Abra o aplicativo e toque em **Criar meu cadastro**.
2. Cadastre **seu próprio e-mail**, nome e senha forte.
3. Confirme o e-mail, se o Supabase solicitar.
4. No **SQL Editor** do Supabase, abra `supabase/02_promover_primeiro_administrador.sql`.
5. **Substitua o e-mail de exemplo pelo mesmo e-mail cadastrado** e execute.
6. Volte ao aplicativo, entre novamente (ou use **Verificar aprovação**).
7. No menu lateral haverá **Aprovar usuários / funções**.

Para os próximos usuários, eles mesmos se cadastram, você os aprova na tela de acessos e define a função. Eles só terão acesso ao que a função permite. Funcionários cadastrados em **Funcionários** não são automaticamente usuários do aplicativo — são registros distintos.

## 6. Permissões iniciais

| Função | Resumo | Clientes | Despesas | Funcionários | Animais | Pagamentos | Manejo (hosp./treino/repr./exames) | Aprovar contas |
|---|---|---|---|---|---|---|---|---|
| Administrador | Ver | Completo | Completo | Completo | Completo | Completo | Completo | Sim |
| Gerente | Ver | Completo | Completo | Completo | Completo | Completo | Completo | Não |
| Financeiro | Ver | Criar/editar | Criar/editar | — | Ver | Criar/editar | — | Não |
| Treinador | Ver | Ver | — | — | Criar/editar | — | Criar/editar | Não |
| Funcionário | Ver | — | — | — | Ver | — | Ver hospedagem, treino e exames | Não |

O controle tem quatro operações por módulo: **ver, criar, editar e excluir**. O SQL define a matriz e o aplicativo lê as permissões na função `my_haras_permissions()`. **Somente administrador e gerente podem excluir**, pela matriz inicial. Um administrador também pode alterar as regras do banco posteriormente. O resumo nunca deve ser usado para contornar a regra: ele conta só os módulos acessíveis.

## 7. Correspondência com a planilha

| Aba da planilha | Tabela Supabase |
|---|---|
| Cadastro Cliente | `clients`, `client_dependents` |
| Cadastro Animal | `animals` |
| lançar Acerto | `payments`, `payment_animals` |
| Ficha hospedagem | `lodgings` |
| Ficha animal treinamento | `training_sessions` |
| Ficha anima reprodução | `breeding_records`, `embryo_transfers` |
| Ficha Exame | `animal_exams` |
| Despesas (nova) | `expenses` |
| Funcionários (nova) | `employees` |
| Controle de acesso (novo) | `profiles`, `role_permissions` |

A coluna `reference_month` aceita uma data (escolha dia **01** do mês desejado); após definirmos a regra de cobranças, ela poderá ser convertida em um campo mês/ano mais amigável e preenchido automaticamente.

## 8. Roteiro de teste

1. Execute `flutter doctor` e resolva os problemas apontados.
2. Rode o SQL no banco **novo** sem erros.
3. Cadastre a primeira conta e confirme que fica **pendente**, sem acesso às tabelas.
4. Promova essa conta com o segundo SQL e pressione **Verificar aprovação**.
5. Cadastre um cliente teste; depois um animal desse cliente.
6. Cadastre uma despesa, um funcionário teste e um pagamento.
7. Crie um segundo usuário **financeiro**: ele deve ver clientes, animais, despesas e pagamentos, mas **não** Funcionários ou Treinamento.
8. Crie um usuário **treinador**: ele deve ver Animais/Treinamento/Exames, mas **não** Despesas/Pagamentos.
9. Coloque um usuário como **bloqueado** e verifique que suas consultas e edições são negadas **no banco**, mesmo se o aplicativo estiver aberto.
10. Faça logout e login novamente, e confirme que os dados continuam salvos.

## Organização do código

```text
haras_f5e/
├── lib/main.dart                # Inicia o Supabase
├── lib/src/app.dart             # Roteamento por autenticação e perfil
├── lib/src/auth_screen.dart     # Cadastro, login e senha
├── lib/src/home_screen.dart     # Menu por função e Resumo
├── lib/src/crud_screen.dart     # Formulários reutilizáveis e listagens
├── lib/src/users_screen.dart    # Aprovação e troca de função (admin)
├── lib/src/modules.dart         # Campos e descrição de cada tela
├── supabase/*.sql               # Banco e primeiro administrador
└── pubspec.yaml                 # Dependências
```

### Observações de segurança

- Senhas são tratadas pelo Supabase Auth, **não** gravadas na tabela Funcionários.
- O perfil começa **pendente** mesmo que o usuário tente informar uma função durante o cadastro.
- As políticas RLS são a verdadeira proteção dos dados. O menu apenas reflete as permissões.
- O aplicativo usa a **publishable key**, que é pública. **Nunca** utilize uma chave secreta no cliente.
- Ao compartilhar o código, **não** inclua credenciais de conexão do seu projeto, fotos de documentos, dados reais de CPF ou cadastros de clientes.
- Para ambiente real, avalie conformidade com LGPD, backup, auditoria de alterações e política de aprovação de colaboradores.

---

## Atualização v0.2 — base do projeto enviado

Esta cópia foi atualizada a partir do arquivo `haras-f5e.rar` enviado. Ela traz:

- Logo original do Haras F5E no login, menu e cabeçalho, com ícones Android legados e adaptáveis.
- Retorno da confirmação de e-mail pelo Supabase ao Android.
- Número único e opcional do cliente (`client_number`) e espécie do animal (`species`).

Para atualizar **sem perder seus dados**, leia primeiro [`GUIA_ATUALIZACAO_v02.md`](GUIA_ATUALIZACAO_v02.md), execute somente [`supabase/03_atualizacao_v02.sql`](supabase/03_atualizacao_v02.sql) em um projeto Supabase existente, cadastre `br.com.f5e.haras://email-confirmado` nas Redirect URLs, rode `flutter clean` e `flutter pub get` e reinstale o Android se o launcher ainda mostrar o ícone antigo.

---

## Atualização v0.3 — exclusão com vínculos e confirmação

Mantém todas as alterações da v0.2 (logo F5E, confirmação de e-mail, espécies e número do cliente) e inclui um aviso antes da exclusão, mostrando quais dados serão apagados e quais serão preservados. Clientes podem ser excluídos mesmo com pagamentos vinculados, **sem apagar o histórico de pagamentos**. Animais podem ser excluídos com fichas relacionadas; essas fichas são excluídas após confirmação.

**Leia [`GUIA_ATUALIZACAO_v03.md`](GUIA_ATUALIZACAO_v03.md) e execute o SQL incremental `supabase/04_exclusao_com_vinculos.sql` no banco existente.** Faça backup antes da migração e teste com dados fictícios. As regras de permissão de administrador/gerente/funcionário foram mantidas. A exclusão é irreversível.


## Atualização v0.4.4 — entrada sem cobrança

A partir da v0.4.4, o mês de entrada do animal é isento e **o primeiro vencimento é dia 10 do mês seguinte**. Execute **somente** `supabase/09_primeiro_mes_sem_cobranca_v044.sql` depois de consultar a prévia `supabase/10_previa_primeiro_mes_v044.sql`, e leia [GUIA_ATUALIZACAO_v044.md](GUIA_ATUALIZACAO_v044.md). Mensalidades anteriores do próprio mês de entrada serão zeradas com trilha de auditoria; pagamentos existentes permanecerão salvos.


## Versão 0.4.5 — Relatórios

A aba **Relatórios** permite filtrar pagamentos entre meses, consultar clientes, animais, totais pagos, saldo devido e cobranças por animal/serviço. Para ativar, execute `supabase/11_relatorios_v045.sql` após as migrações até a v0.4.4. Consulte `GUIA_ATUALIZACAO_v045.md`.
