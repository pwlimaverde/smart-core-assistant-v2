# Smart Core Releases Server

Servidor Rust (Axum 0.8, `server/apps/releases_server`) que hospeda o instalador
Windows e o feed do Velopack.

## Rotas

| Rota | Acesso | O quê |
|---|---|---|
| `GET /health` | público | liveness |
| `GET /api/installers/{canal}` | público, 60/min/IP | `installers.json` do canal (versão, arquivo, sha256, tamanho, notas) — lido pelo control_plane |
| `GET /feed/{canal}/{arquivo}` | público, 120/min/IP | feed do Velopack (`releases.{canal}.json`, `*.nupkg`, `RELEASES-{canal}`, `assets.{canal}.json`) |
| `GET /download/{versao}/{arquivo}?t=` | ticket HMAC, 30/min/IP | `*Setup.exe`; ticket emitido pelo control_plane (`AdminService.GetWindowsDownloadLink`) |
| `POST /upload` | `Bearer RELEASES_UPLOAD_TOKEN`, 5/min/IP | publicação pelo CI (multipart `channel`, `version`, `notes`, `file`…) |

Nenhum outro arquivo é servido (não existe `ServeDir`). Nomes passam por allowlist.

## Layout em disco (`/opt/smartcore/releases-data` → `/data/releases`)

```
{canal}/installers.json
{canal}/installers/{versao}/SmartCoreTenant-{canal}-Setup.exe
{canal}/feed/releases.{canal}.json | *.nupkg | RELEASES-{canal} | assets.{canal}.json
```

## Subir no VPS

```bash
sudo mkdir -p /opt/smartcore/releases-data && sudo chown -R 10001 /opt/smartcore/releases-data
cp .env.example .env && chmod 600 .env   # preencher os dois segredos
docker compose --env-file .env up -d
```

O `RELEASES_DOWNLOAD_SECRET` precisa ser o mesmo no `.env` do control_plane.
A imagem é publicada pelo workflow `release-windows.yml`.
