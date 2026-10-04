# Gerar app_icon.ico

O arquivo `app_icon.ico` deve ser gerado a partir de `assets/logo_mark.png`.

## Opção 1: ImageMagick (recomendado)

Instale ImageMagick (https://imagemagick.org/script/download.php#windows) e execute:

```bash
magick convert infra/branding/assets/logo_mark.png \
  -define icon:auto-resize=256,128,64,48,32,24,16 \
  clients/apps/smart-core-tenant/windows/runner/resources/app_icon.ico
```

## Opção 2: Python + Pillow

```bash
pip install Pillow
python -c "
from PIL import Image
img = Image.open('infra/branding/assets/logo_mark.png')
if img.mode != 'RGB':
    img = img.convert('RGB')
img.save('clients/apps/smart-core-tenant/windows/runner/resources/app_icon.ico', 'ICO',
         sizes=[(16,16), (24,24), (32,32), (48,48), (64,64), (128,128), (256,256)])
print('ICO gerado com sucesso!')
"
```

## Opção 3: Conversor Online

Use um conversor online como:
- https://convertio.co/png-ico/
- https://icoconvert.com/

1. Upload de `assets/logo_mark.png`
2. Tamanhos: 16, 24, 32, 48, 64, 128, 256 px (múltiplas resoluções em um ICO)
3. Download do `app_icon.ico`
4. Salve em `clients/apps/smart-core-tenant/windows/runner/resources/app_icon.ico`

## D1 Status

- [x] Script de geração documentado
- [ ] ICO gerado (rodar um dos passos acima)
