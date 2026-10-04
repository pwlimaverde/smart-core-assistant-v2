# Instalador Windows (Velopack)

O instalador do Smart Core Tenant é o `Setup.exe` gerado pelo **Velopack**
(`vpk pack`). O NSIS foi abandonado (decisão D1 do plano
`windows-releases-v01-beta`): um instalador NSIS não monta o layout que o
`Update.exe` do Velopack espera, então os dois juntos quebravam o auto-update.

## Como sai uma versão

Tudo pelo workflow `.github/workflows/release-windows.yml`:

```bash
git tag win-v0.2.0-beta.2 && git push origin win-v0.2.0-beta.2   # canal beta (build DEV)
git tag win-v1.0.0        && git push origin win-v1.0.0          # canal stable (build PROD)
```

Ou `workflow_dispatch` informando a versão.

O workflow:

1. compila o app (`flutter build windows`, entrypoint `main_dev`/`main_prod`) e
   confere os endereços dentro do `app.so`;
2. empacota e assina com `vpk pack --channel <canal> --noPortable --skipVeloAppCheck --signParams …`;
   verifica as assinaturas e roda o teste ponta a ponta de auto-update;
3. publica artefato + GitHub Release (`SmartCoreTenant-<canal>-Setup.exe`, `.sha256`,
   `*.nupkg`, `releases.<canal>.json`, `assets.<canal>.json`, `RELEASES-<canal>`);
4. envia tudo ao `releases_server` (`POST /upload`), se o secret
   `RELEASES_UPLOAD_TOKEN` existir e o servidor responder.

Para gerar à mão (zip, sem instalador): `infra/build-windows.ps1`.

## Assinatura de código (D5)

O `vpk pack --signParams` chama o `signtool` em cada binário (exe, dlls,
`Update.exe`) antes de empacotar e no `Setup.exe`, com SHA-256 e carimbo de
tempo (`timestamp.digicert.com`). O certificado vem dos secrets do repositório:

| Secret | Conteúdo |
|---|---|
| `SIGNTOOL_CERT` | PFX em base64 (`base64 -w0 smartcore-dev.pfx`) |
| `SIGNTOOL_PASSWORD` | senha do PFX |

Sem os secrets o job gera um certificado efêmero e avisa — nunca sai binário
sem assinatura. O passo "Verifica assinatura Authenticode" exige status
`Valid`, o thumbprint esperado e o carimbo no `Setup.exe` e nos binários do
`.nupkg`.

**Hoje o certificado é auto-assinado de desenvolvimento** (`smartcore-dev.crt`
nesta pasta, só a parte pública; thumbprint
`0E64E4F1EB9A1C473C8BF7A5F12205DA1D788085`, validade até 2036). Ele prova
integridade e autoria para quem confia nele, mas **não tira o aviso do
SmartScreen nem a desconfiança do Defender** em máquinas de terceiros: isso
exige certificado emitido por CA pública (OV/EV, ou Azure Trusted Signing) e
reputação acumulada. Para trocar, basta substituir os dois secrets — o
workflow não muda.

Máquina de teste interna que deve reconhecer a assinatura:

```powershell
# PowerShell como administrador
Import-Certificate -FilePath smartcore-dev.crt -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath smartcore-dev.crt -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

Gerar outro certificado de desenvolvimento (a chave nunca entra no repositório):

```bash
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650   -keyout smartcore-dev.key -out smartcore-dev.crt   -subj "/CN=Smart Core Assistant (DEV)/O=Smart Core/C=BR"   -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=codeSigning"
openssl pkcs12 -export -out smartcore-dev.pfx -inkey smartcore-dev.key -in smartcore-dev.crt
base64 -w0 smartcore-dev.pfx | gh secret set SIGNTOOL_CERT
gh secret set SIGNTOOL_PASSWORD   # cola a senha do PFX
```

Sem `extendedKeyUsage=codeSigning` o certificado é recusado pelo workflow.

## Auto-update (D6)

O app chama o Velopack na subida (`lib/platform/auto_update*.dart` +
`UpdateChecker`), pela cópia vendorizada do `velopack_flutter` em
`clients/plugins/velopack_flutter` (o pacote do pub.dev fixa um
`flutter_rust_bridge` que conflita com o `local_engine_ffi` e quebra o build Web
— motivos no `pubspec.yaml` dele).

- Feed: `https://releases.smartcoreassistant.com.br/feed/<canal>` (vem por
  `--dart-define=SMARTCORE_UPDATE_FEED_URL`; o canal é o da instalação).
- Política: havendo versão nova, baixa, aplica e reinicia sem perguntar. Falha
  de rede ou feed fica no log e a próxima subida tenta de novo.
- Fora da instalação do Velopack (`flutter run`, zip do `build-windows.ps1`) a
  checagem é desligada; na Web o pacote nem entra no bundle.
- `SMARTCORE_UPDATE_FEED_URL` como variável de ambiente troca o feed em tempo
  de execução — é o que o teste ponta a ponta do workflow usa.

O workflow prova o ciclo antes de publicar: instala `0.0.1-e2e.1`, serve um
feed local com `0.0.1-e2e.2` e espera o app se atualizar sozinho.

Ensaio sem publicar: `git push origin HEAD:ci/release-windows-<algo>` roda build,
assinatura e o teste de auto-update com versão descartável, sem Release nem
upload.
