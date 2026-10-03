# windows_downloads

Tela "Instalador Windows" do painel do superusuário (`/admin/windows-downloads`).

Fluxo: `AdminService.GetWindowsDownloadLink` (runtime_api, guarda de
superusuário) → RPC interno `IssueReleaseDownloadTicket` (control_plane, assina
o ticket HMAC e audita `release_download_link_issued`) → URL
`https://releases.../download/{versao}/{arquivo}?t=<ticket>` (vale 5 min),
aberta numa aba nova.

Erros (gRPC → `WindowsDownloadsError`):

| Status | Erro |
|---|---|
| UNAUTHENTICATED | `WindowsDownloadsSessaoExpirada` |
| PERMISSION_DENIED | `WindowsDownloadsAcessoNegado` |
| INVALID_ARGUMENT | `WindowsDownloadsCanalInvalido` |
| FAILED_PRECONDITION | `WindowsDownloadsNaoConfigurado` (sem `RELEASES_DOWNLOAD_SECRET`) |
| NOT_FOUND | `WindowsDownloadsSemRelease` |
| UNAVAILABLE / RESOURCE_EXHAUSTED | `WindowsDownloadsIndisponivel` |
| demais | `WindowsDownloadsInesperado` |

O link só é gerado no clique: cada pedido vira uma linha de auditoria.
