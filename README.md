> Publicação atual: https://smartlog-next-2026.netlify.app — configuração e ensaio no [guia Netlify](../SmartLogAPI/docs/NETLIFY.md). Os procedimentos Google/Cloud Run abaixo são alternativas históricas.

> Integração de 23/10/2026: status e chat usam a API compartilhada com o painel. Provedor padrão da IA: Gemini Flash-Lite. O Firestore original do app foi preservado. Guia completo no workspace: ../SmartLogAPI/docs/INTEGRACAO.md.

# SmartLog

> **Projeto em equipe — fork de [LucasSilva2005/Smartlog](https://github.com/LucasSilva2005/Smartlog).**
> O núcleo do app Flutter (autenticação, painel do administrador, telas do motorista, leitura de QR Code, rastreamento e mapas) é trabalho de **Lucas da Silva**. Abaixo está o que eu desenvolvi.

### Minha contribuição (Deyvid Gondim)

- **Camada de IA (Assistente Logístico)** — Cloudflare Worker em [`smartlog-ai/`](smartlog-ai/) que recebe a pergunta do app, **verifica o Firebase ID Token (JWT) via WebCrypto** contra as chaves públicas do Google, lê o Firestore com a credencial do próprio usuário e responde com o Gemini. A identidade, o perfil e a empresa vêm só do token verificado, nunca do corpo da requisição.
- **Seleção de contexto e relevância** — normalização dos schemas de `entregas` gravados por caminhos diferentes do app, contexto recortado por perfil (admin, motorista, cliente) e seleção das entregas guiada pela pergunta (códigos `ENT-…`, nomes, regiões), com teto de itens para controlar custo de tokens ([`contexto.js`](smartlog-ai/src/contexto.js), [`relevancia.js`](smartlog-ai/src/relevancia.js)).
- **Cloud Functions** — a mesma lógica portada para uma Firebase Function HTTP (`chat`, `southamerica-east1`) com Admin SDK e chave Gemini no Secret Manager, disponível como alternativa à API compartilhada ([`functions/`](functions/)).
- **Regras de segurança do Firestore** — isolamento multi-tenant por `empresaId` e permissões por perfil em [`firestore.rules`](firestore.rules).
- **No app Flutter** — tela do chat assistente ([`chat_assistente.dart`](lib/screens/chat_assistente.dart)), `ChatController`/`ChatService` e o painel do cliente ([`cliente.dart`](lib/screens/cliente.dart)).
- **Testes da camada de IA** — 36 testes unitários de normalização, contexto e relevância, mais 4 testes de endpoint no runtime do Worker.

---

## O que é

SmartLog é um app Android de gestão logística **multiempresa**. Cada empresa (tenant) tem três perfis:

| Perfil | O que faz no app |
|---|---|
| **Administrador** | Painel com indicadores da operação; cadastro de entregas, rotas, motoristas e clientes; geração de rota por região; mapa com a posição do motorista em movimento; perfil da empresa. |
| **Motorista** | Rota do dia e lista de entregas, atualização de status pela API (Pendente → Em Rota → Entregue), mapa das paradas, histórico e perfil com foto. |
| **Cliente** | Acompanhamento das próprias entregas em tempo real: status, endereço e motorista responsável. |

Existe também uma tela de rastreio ([`rastreamento.dart`](lib/screens/rastreamento.dart)) que mostra no mapa a localização atual do motorista de uma rota; ela ainda não está ligada à navegação do app.

Os três perfis têm acesso ao **Assistente Logístico**, um chat com IA que responde perguntas sobre a operação ("quais entregas estão atrasadas?", "qual o status da ENT-A8F3?") usando só os dados que aquele usuário pode ver.

## Arquitetura

```mermaid
flowchart LR
    App["App Flutter<br/>(admin, motorista, cliente)"]
    Auth["Firebase Auth"]
    FS[("Cloud Firestore<br/>+ firestore.rules")]
    API["API Spring Boot<br/>/api/v1/chat"]
    Web["Painel Angular"]
    Fn["Cloud Function alternativa<br/>(functions/)"]
    CW["Cloudflare Worker<br/>(smartlog-ai/)"]
    AI["Gemini<br/>gemini-3.1-flash-lite"]

    App -- "login" --> Auth
    App -- "leitura e escrita em tempo real" --> FS
    App -- "status e chat + ID Token" --> API
    Web -- "operação e chat + ID Token" --> API
    API -- "Admin SDK, filtro por empresaId" --> FS
    API --> AI
    App -. "chat alternativo" .-> Fn
    App -. "POST /chat + ID Token<br/>(backend alternativo)" .-> CW
    Fn -- "Admin SDK, filtro por empresaId" --> FS
    CW -- "REST com o token do usuário<br/>(as rules continuam valendo)" --> FS
    Fn --> AI
    CW --> AI
```

Fluxo do assistente: o app envia a pergunta com o ID Token no header `Authorization` → o backend valida o token e lê o cadastro do usuário (`usuarios/{uid}`) → monta o contexto só com os dados da empresa e do perfil dele → seleciona as entregas relevantes para a pergunta → chama o Gemini com um prompt que proíbe inventar dados → devolve a resposta ao app.

O app usa por padrão /api/v1/chat na API compartilhada. A Function e o Worker são alternativas explícitas. API_BASE_URL configura o servidor no build; CHAT_BASE_URL seleciona outra URL de chat. A pasta worker/ contém o protótipo antigo, substituído por smartlog-ai/.

## Stack

- **App:** Flutter / Dart, Provider, Material 3, `google_maps_flutter`, `geolocator`, `mobile_scanner` (QR Code), `image_picker`
- **Firebase:** Authentication, Cloud Firestore, Storage, Cloud Functions v2 (Node 24, `firebase-admin`, `openai`)
- **IA:** Cloudflare Workers (Wrangler, WebCrypto para JWT, Firestore REST) + Gemini Developer API
- **Testes:** Vitest, `@cloudflare/vitest-pool-workers`, `flutter_test`

## Estrutura

```
lib/                 App Flutter
  controllers/       AuthController, DashboardController, ChatController
  screens/           login, cadastro, dashboard_admin, motorista, cliente,
                     rastreamento, chat_assistente
  services/          auth, chat, maps (ViaCEP), routing
functions/           Cloud Function "chat" (alternativa ao chat da API)
smartlog-ai/         Cloudflare Worker do assistente (JWT + Firestore REST)
worker/              Protótipo antigo do Worker
firestore.rules      Regras de segurança do Firestore
test/                Testes do app Flutter
```

## Como rodar

### App Flutter

Pré-requisitos: Flutter SDK (Dart ≥ 3.3) e um emulador ou aparelho Android. O projeto Firebase (`smartlog-b9b37`) já está configurado em `android/app/google-services.json` e `lib/firebase_options.dart`.

```bash
flutter pub get
flutter run
```

Para testar o fluxo completo: cadastre-se como **Administrador** (isso cria a empresa), cadastre um motorista e um cliente no painel, crie entregas/rotas e entre com as outras contas.

### Cloud Functions

```bash
cd functions
npm install
firebase functions:secrets:set GEMINI_API_KEY   # chave fica no Secret Manager
npm run serve                                     # emulador local
npm run deploy                                    # publica a função "chat"
```

As regras do Firestore são publicadas com `firebase deploy --only firestore:rules`.

### Assistente no Cloudflare Worker (`smartlog-ai/`)

```bash
cd smartlog-ai
npm ci
cp .dev.vars.example .dev.vars   # preencha GEMINI_API_KEY (arquivo ignorado pelo git)
npm run dev                      # wrangler dev
```

Em produção a chave vai como secret: `npx wrangler secret put GEMINI_API_KEY` e depois `npm run deploy`.

## Testes

```bash
# Camada de IA (smartlog-ai/)
cd smartlog-ai
npx vitest run          # 36 testes de função pura (Node): normalização, contexto, relevância
npm run test:workers    # 4 testes de endpoint no runtime do Worker (404, 405, 204 CORS, 401 sem token)

# App Flutter (raiz)
flutter test
```

## Observações

- O pacote Dart ainda se chama `smartlife` e o `applicationId` Android é `com.example.smartlife`, herança do projeto que serviu de base. O ID precisa continuar igual ao registrado no Firebase (`google-services.json`), por isso não foi renomeado.
- O CORS dos backends do assistente está aberto durante o MVP. A proteção real é o Bearer token.


## Validação de 23/10/2026

Passaram 8 testes Flutter, 6 do adaptador Gemini, 36 de contexto/relevância e 4 de endpoint Worker. O APK ARM64 está em build/app/outputs/flutter-apk/app-release.apk, com a assinatura de demonstração já configurada. A instalação, o GPS físico e o comportamento em segundo plano dependem de ensaio no tablet.

A chave Gemini fica no servidor. Publique a API e as regras novas antes de validar o APK no hosting padrão. Consulte o guia integrado para emuladores, publicação e limites de verificação.
