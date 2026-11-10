# Haras F5E — v0.2, atualizada a partir do `haras-f5e.rar` enviado

Este pacote **usa como base a pasta Flutter que você enviou**. Não foi refeito como um projeto independente: mantivemos a estrutura de pastas, o `applicationId` Android `com.example.haras_f5e`, o código de Resumo, Funcionários, Despesas, Clientes, Animais e dos demais módulos, além do banco já utilizado.

## Novidades desta versão

- **Logo F5E original**: a imagem presente nos seus `mipmap-*` foi preservada; agora também aparece na tela de login, no cabeçalho e no menu lateral. Foram adicionados ícones adaptáveis para Android 8+ e ícone temático para Android 13+. O nome exibido do aplicativo no Android foi alterado para **Haras F5E**.
- **Confirmação do e-mail**: depois de um cadastro que requer confirmação, surge a tela "Verifique seu e-mail". Ao tocar no e-mail, um link pode abrir o aplicativo e mostrar **E-mail confirmado!** após o Supabase verificar a conta. A liberação por administrador continua obrigatória.
- **Animais → Espécie**: Equino, Bovino, Asinino, Muar, Ovino, Caprino, Suíno ou Outro.
- **Clientes → Número do cliente**: código opcional, sem números repetidos, que aceita zeros à esquerda (por exemplo, `0007`).

## Etapa 1 — Backup

Faça uma cópia da pasta que está funcionando no seu computador. Se já cadastrou clientes/animais reais, faça também um backup do banco no Supabase. Não apague os dados.

## Etapa 2 — Atualização no Supabase (sem apagar dados)

No **mesmo projeto Supabase** que você já utiliza, vá a **SQL Editor → New query**, cole o conteúdo de `supabase/03_atualizacao_v02.sql` e clique em **Run**. Esse SQL:

- Adiciona a coluna de texto `public.clients.client_number`.
- Adiciona a coluna de texto `public.animals.species`.
- Valida o formato numérico e a exclusividade do número do cliente.

**Importante:** no banco existente, **NÃO** execute novamente o arquivo `supabase/01_estrutura_e_permissoes.sql`, nem o script que promove administrador. O SQL `03` é incremental e mantém os cadastros atuais, mesmo que já tenha sido executado anteriormente.

## Etapa 3 — Abrir o projeto atualizado

1. Extraia o ZIP e abra a pasta `haras-f5e` no VS Code, ou copie os arquivos atualizados para o projeto que está usando, preservando o seu `.git` e demais ajustes locais.
2. Não copie `.dart_tool`, `build` ou `android/.gradle` da pasta antiga. Esses são caches, e foram intencionalmente excluídos do pacote.
3. Caso utilize configurações específicas de Android/SDK em `android/local.properties`, mantenha o arquivo **local da sua máquina**. O Flutter normalmente também o regenera.
4. Abra o terminal integrado do VS Code na pasta onde está `pubspec.yaml` e execute:

   ```powershell
   flutter clean
   flutter pub get
   flutter test
   ```

5. Use o **mesmo Supabase** de antes. Inicie com seu comando habitual, por exemplo:

   ```powershell
   flutter run --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_SUA_CHAVE
   ```

   Substitua os exemplos pelos dados do seu projeto. **Não use uma chave `service_role` ou secret no Android**.

### Se o ícone antigo continuar no Android

O ícone está definido em `android/app/src/main/res/mipmap-*/ic_launcher.png` (legado), `mipmap-anydpi-v26/ic_launcher.xml` (adaptativo) e na propriedade `android:icon` do `AndroidManifest.xml`. Todos foram conferidos. Porém, o Android pode guardar em cache o ícone de um aplicativo instalado.

- Pare a execução atual, rode `flutter clean` e depois `flutter run` para recompilar (somente **hot reload não atualiza os ícones nativos**).
- Se ainda aparecer a imagem antiga, desinstale o app **do celular/emulador** e rode `flutter run` de novo. Remova e adicione novamente um atalho antigo da tela inicial, se necessário.
- Isso não apaga o banco Supabase, mas a desinstalação limpa os dados locais e a sessão do dispositivo. Faça login novamente.
- O arquivo `assets/icon/haras_f5e_app.png` é a versão da logo exibida nas telas Flutter; `mipmap` é um recurso **nativo do Android**, não é automaticamente carregado pelo `Image.asset`.

## Etapa 4 — Ativar o retorno da confirmação de e-mail

No painel Supabase → **Authentication → URL Configuration → Redirect URLs**, adicione **exatamente**:

```text
br.com.f5e.haras://email-confirmado
```

No Supabase → Authentication → Providers → Email, deixe a confirmação de e-mail ativada se desejar esse fluxo. O aplicativo já possui `emailRedirectTo` no cadastro e `intent-filter` no `android/app/src/main/AndroidManifest.xml`; você **não precisa editar esses arquivos** se estiver usando o ZIP novo. O app deve ser recompilado para que o filtro funcione no Android.

A confirmação do e-mail **não autoriza automaticamente** o acesso ao sistema. O usuário continua pendente até que o administrador aprove sua conta e selecione sua função.

## Etapa 5 — Testar

1. Em **Clientes**, cadastre `0007`, confirme que aparece na lista e reabra o registro. Outro cliente com `0007` deve ser recusado (número único).
2. Em **Animais**, selecione a espécie `Equino` e salve.
3. Verifique a logo F5E no **login**, na **barra superior** e no **menu lateral**.
4. Crie um **cadastro novo** com outro e-mail, receba o link e abra-o no **mesmo Android** com o app instalado. Confirme a tela **E-mail confirmado!** e, após continuar, a tela de aprovação pendente (se o admin ainda não liberou).

Se links antigos ainda abrirem o navegador, use um e-mail novo: o link gerado antes da configuração pode apontar para outro endereço. Confirme que o Supabase tem a Redirect URL idêntica e que o link foi aberto no Android que tem o app atualizado.

## Arquivos que merecem atenção

- `lib/src/haras_logo.dart` — novo componente visual com sua marca.
- `assets/icon/haras_f5e_app.png` — logo exibida dentro do Flutter.
- `android/app/src/main/AndroidManifest.xml` — ícone, nome, permissão de internet e abertura do e-mail.
- `android/app/src/main/res/mipmap-*` — ícones originais preservados e arquivos adaptáveis adicionados.
- `lib/src/auth_screen.dart`, `lib/src/app.dart`, `lib/src/email_confirmation.dart` — confirmação de e-mail.
- `lib/src/modules.dart`, `lib/src/crud_screen.dart` — número do cliente e espécie dos animais.
- `supabase/03_atualizacao_v02.sql` — alteração incremental no banco.

## Limite de verificação

Foi realizada inspeção estrutural dos arquivos, recursos e configurações. **Este ambiente não possui Flutter/Android SDK para compilar e instalar o APK**; por isso a compilação, os testes Flutter e o retorno real de e-mail deverão ser verificados no seu computador e no painel Supabase.
