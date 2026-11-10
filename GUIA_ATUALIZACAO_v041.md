# Haras F5E v0.4.1 — Espécies e datas brasileiras

## O que mudou

- **Animais → Espécie:** agora somente **Equino**, **Bovino** e **Suíno** aparecem para seleção.
- **Datas do aplicativo:** mostradas no formato **DD/MM/AAAA** (por exemplo, `14/10/2026`). Isso inclui listas, edição e calendário de pagamento na aba Recebimento de estadia.
- **Calendário:** idioma português brasileiro nos seletores de data do Android/Flutter.
- **Supabase:** as datas continuam sendo enviadas ao banco como `AAAA-MM-DD` (`2026-10-14`), que é o formato correto de armazenamento para campos do tipo `date`.
- **Espécies antigas:** o banco não é modificado. Um animal já cadastrado como Asinino, por exemplo, mantém esse valor até você escolher uma das três opções novas ao editá-lo. Isso evita perda involuntária de dados.

## Instalar a atualização

1. Faça uma cópia de segurança do projeto atual antes de substituí-lo.
2. Extraia o ZIP desta versão e abra a pasta `haras-f5e` no VS Code.
3. Execute:

   ```powershell
   flutter clean
   flutter pub get
   flutter run --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA
   ```

4. Para instalar em celular, gere o APK com `flutter build apk --release` e os mesmos `--dart-define` utilizados acima.
5. Confira o cadastro de animais, o histórico de clientes e a data dos recebimentos.

**Nenhum SQL adicional é necessário.** Esta atualização altera apenas o código do aplicativo; seus clientes, animais, pagamentos e demais registros existentes continuam no Supabase.

> Observação: não foram executados testes Flutter neste ambiente. Depois de usar `flutter pub get`, execute `flutter test` no VS Code para validar os testes automatizados.
