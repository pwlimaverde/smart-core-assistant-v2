# Systemd Service Units — Smart Core Assistant v2

Copiar os arquivos `.service` e `.target` para `/etc/systemd/system/` no servidor:

```bash
cp infra/systemd/*.service /etc/systemd/system/
cp infra/systemd/*.target  /etc/systemd/system/
systemctl daemon-reload
systemctl enable smartcore-prod.target
systemctl enable smartcore-dev.target
```

## Nomenclatura

```
smartcore-{env}-{servico}.service
smartcore-{env}.target
```

Onde `{env}` = `prod` ou `dev`.

## Ordem de boot garantida pelo target

```
data_redis → data_postgres → data_storage
                           → control_plane
                           → messaging_gateway
                           → worker
                           → runtime_api (último)
```

## Comandos úteis

```bash
# Iniciar todos os serviços de um ambiente
systemctl start smartcore-prod.target
systemctl start smartcore-dev.target

# Ver logs em tempo real de um serviço
journalctl -u smartcore-prod-runtime_api -f

# Status de todos os serviços smartcore
systemctl list-units 'smartcore-*'

# Rollback manual: alterar symlink e reiniciar
ln -sfn /opt/smartcore/prod/releases/v1.0.0 /opt/smartcore/prod/releases/current
systemctl restart smartcore-prod.target
```
