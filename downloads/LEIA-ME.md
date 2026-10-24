# SmartLog 1.1.0 para Android ARM64

[Baixar ZIP com o APK atualizado](https://github.com/DeyvidJesus/Smartlog/raw/refs/heads/downloads/android-arm64/downloads/SmartLog-1.1.0-arm64.zip)

1. Baixe o ZIP e extraia `SmartLog-1.1.0-arm64.apk`.
2. Abra o APK em um aparelho Android ARM64 e autorize a instalação pelo navegador/gerenciador de arquivos, se solicitado.

APK compilado a partir do commit `e23c8a3967823a9d3402b6c4da317403c5bca874`.
Inclui comprovante com foto, assinatura e GPS, registro de ocorrências e
acompanhamento pelo cliente. A API configurada é
`https://smartlog-next-2026.netlify.app/api/v1`.

SHA-256 do APK extraído:
`5f38cc3c7df5b3350f623af48909f1b94dec4a5de8ae7268a67d7e2ef97a7f57`

Os novos recursos exigem a publicação conjunta da API (`f5411a3`) e do Web
(`cf0ff59`). Faça merge dos PRs da API e do app e, por último, do PR Web que
dispara o deploy. Antes desse deploy, os endpoints novos ainda não estão
disponíveis em produção.

O APK mantém a assinatura de debug existente no projeto. Para atualizar uma
instalação anterior, o certificado precisa ser compatível.
