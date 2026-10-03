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
2. empacota com `vpk pack --channel <canal> --noPortable --skipVeloAppCheck`;
3. publica artefato + GitHub Release (`SmartCoreTenant-<canal>-Setup.exe`, `.sha256`,
   `*.nupkg`, `releases.<canal>.json`, `assets.<canal>.json`, `RELEASES-<canal>`);
4. envia tudo ao `releases_server` (`POST /upload`), se o secret
   `RELEASES_UPLOAD_TOKEN` existir e o servidor responder.

Para gerar à mão (zip, sem instalador): `infra/build-windows.ps1`.

## Pendências conhecidas

- **Auto-update dentro do app:** o app ainda não chama o SDK do Velopack
  (`--skipVeloAppCheck`). O feed já é publicado em
  `https://releases.smartcoreassistant.com.br/feed/<canal>/`.
- **Assinatura de código (D5):** fora da beta; o SmartScreen avisa na instalação.
