# Haras F5E v0.3 — exclusão de registros com vínculos

Base utilizada: **Haras F5E v0.2 atualizada a partir do seu `haras-f5e.rar`**. Inclui a logo, cadastro de cliente com número, espécie dos animais e a confirmação de e-mail existentes na v0.2.

## 1. O que muda

Você poderá excluir clientes e animais mesmo quando houver registros relacionados, desde que sua função tenha autorização para **excluir**. O botão mostra antes uma mensagem clara: **“Você tem certeza que deseja excluir?”**, o nome do cadastro, a quantidade de vínculos e os efeitos da ação. Há opções **Cancelar** e **Sim, excluir definitivamente**.

| Exclusão solicitada | O que acontece com os relacionados |
|---|---|
| Cliente | **Pagamentos são preservados** (com nome do cliente salvo no histórico) e ficam sem vínculo; animais são preservados e ficam sem proprietário; dependentes do cliente são excluídos. |
| Animal | Pagamentos são preservados; ligações do animal a pagamentos são removidas. Fichas de hospedagem, treinamento, reprodução, transferências de embrião e exames do animal são excluídas. |
| Pagamento | O pagamento e suas ligações aos animais são excluídos; animais são preservados. |
| Ficha de reprodução | A ficha é excluída; registros de transferência de embrião que apontavam para a ficha permanecem, mas perdem essa referência. |
| Funcionário, despesa, hospedagem, treinamento, exame etc. | O registro escolhido é excluído após a confirmação. As permissões do sistema continuam valendo. |

**ATENÇÃO:** Exclusões definitivas não são reversíveis. A exclusão de um animal também apaga fichas históricas relacionadas. Faça backup antes de testar com cadastros reais. O nome do cliente permanece no histórico de pagamentos, caso existam pagamentos; portanto, isso não equivale à remoção integral de dados pessoais.

## 2. Fazer backup

Antes de aplicar alterações no Supabase, faça uma cópia do seu banco de dados ou exporte os cadastros relevantes (clientes, animais, pagamentos, hospedagem, treinamento, reprodução e exames). Guarde também uma cópia da pasta atual do projeto Flutter. Se você ainda não tiver uma estratégia de backup, teste primeiro em um projeto Supabase de teste.

## 3. Atualizar o Supabase (obrigatório)

1. Acesse seu projeto **Haras F5E** no Supabase.
2. Abra **SQL Editor → New query**.
3. Copie todo o conteúdo do arquivo `supabase/04_exclusao_com_vinculos.sql`.
4. Execute **somente esse SQL de atualização** no banco existente.
5. Confirme que a execução terminou sem erros.

Este SQL cria a coluna `payments.client_name_snapshot` (histórico do nome), altera o vínculo `payments.client_id` para **ON DELETE SET NULL** e configura as demais chaves estrangeiras relacionadas. **Ele não apaga registros ao ser executado**. A alteração é transacional.

Não execute `01_estrutura_e_permissoes.sql` novamente no banco em uso. Se você nunca aplicou a v0.2, execute antes `03_atualizacao_v02.sql`.

## 4. Atualizar Flutter

Abra o ZIP v0.3, entre na pasta `haras-f5e` e copie os arquivos atualizados para sua pasta local do projeto. Para não perder alterações feitas depois da v0.2, compare os arquivos antes de substituir. Os arquivos principais desta versão são:

- `lib/src/crud_screen.dart`: nova confirmação de exclusão e exibição do pagamento com cliente excluído;
- `lib/src/deletion_dependencies.dart`: consulta de vínculos antes da exclusão;
- `pubspec.yaml`: número de versão `0.3.0+3`;
- `supabase/04_exclusao_com_vinculos.sql`: atualização necessária no Supabase.

No terminal PowerShell do VS Code:

```powershell
flutter clean
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_SUA_CHAVE_PUBLICA
```

Para gerar um APK após os testes:

```powershell
flutter build apk --release --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_SUA_CHAVE_PUBLICA
```

Arquivo gerado: `build/app/outputs/flutter-apk/app-release.apk`.

Use a **chave publicável** do Supabase, nunca a `service_role` ou uma chave secreta. O computador não precisa ficar ligado após instalar o APK.

## 5. Testar, usando dados fictícios

1. Com conta de administrador, crie um cliente de teste e vincule um animal e um pagamento.
2. Toque em **Excluir** no cliente; confira se a caixa informa que o pagamento e o animal serão preservados.
3. Toque em **Cancelar** e confira que nada foi alterado.
4. Abra novamente e toque em **Sim, excluir definitivamente**.
5. Confira que o cliente saiu da lista; que o animal permaneceu sem proprietário; e que o pagamento permaneceu na lista, identificado pelo nome histórico do cliente.
6. Crie um segundo animal de teste com uma ficha de hospedagem, treinamento ou exame. Exclua o animal e confira o aviso de que as fichas relacionadas serão apagadas.
7. Teste também excluir uma despesa sem vínculos: deve aparecer o mesmo pedido de confirmação.
8. Verifique com um perfil sem permissão para excluir: o botão Excluir não deve aparecer, e o Supabase continua negando tentativas não autorizadas.

Se surgir erro de chave estrangeira (`23503`), provavelmente o SQL 04 não foi aplicado no mesmo projeto Supabase usado pelo aplicativo; verifique a URL, sem enviar senhas ou chaves secretas.

## 6. Limites do pacote

O código e o SQL foram preparados e inspecionados estruturalmente, mas **não foi possível executar Flutter nem conectar ao seu banco Supabase neste ambiente**. Faça os testes em um projeto de testes antes de usar em produção. O aviso exibe contagens obtidas antes da confirmação; outra pessoa pode modificar vínculos entre essa consulta e o clique. As regras finais são sempre garantidas pelas chaves estrangeiras do banco.
