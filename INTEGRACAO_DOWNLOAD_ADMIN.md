# 🔧 INTEGRAÇÃO: Botão de Download no Django Admin DEV

**Objetivo:** Adicionar botão/link funcional para download de `SmartCoreTenant-0.1.0-beta-Setup.exe` no painel admin DEV.

**Local de Acesso:** `https://dev.smartcoreassistant.com.br/v2/admin/...`

---

## 📋 INFORMAÇÕES ESSENCIAIS

| Item | Valor |
|------|-------|
| **URL de Download** | `https://releases.smartcoreassistant.com.br/download/0.1.0-beta/SmartCoreTenant-0.1.0-beta-Setup.exe` |
| **Versão** | 0.1.0-beta |
| **Channel** | beta |
| **Status** | Desenvolvimento/Testes Internos |
| **Acesso** | Apenas admin/devs (autenticado) |

---

## ✅ OPÇÃO RECOMENDADA: Mais Rápida (5 min)

### Adicionar Link no Menu Admin

1. Abra o arquivo Django admin (`admin.py` ou `urls.py`)

2. Adicione esta view:

```python
from django.contrib.admin.views.decorators import staff_member_required
from django.shortcuts import redirect

@staff_member_required
def download_smartcore_setup(request):
    return redirect('https://releases.smartcoreassistant.com.br/download/0.1.0-beta/SmartCoreTenant-0.1.0-beta-Setup.exe')
```

3. Registre no `urls.py`:

```python
urlpatterns = [
    # ... outros paths
    path('admin/download-smartcore/', download_smartcore_setup, name='download_smartcore'),
]
```

4. Acesso:
```
https://dev.smartcoreassistant.com.br/admin/download-smartcore/
```

---

## ✨ OPÇÃO PROFISSIONAL: Com Visual (15 min)

### Criar Página Customizada com Branding

1. Crie `templates/admin/download_smartcore.html`:

```html
{% extends 'admin/base_site.html' %}
{% load static %}

{% block title %}Baixar Smart Core Tenant - Admin{% endblock %}

{% block content %}
<div style="max-width: 600px; margin: 50px auto; font-family: Segoe UI, sans-serif;">
    
    <!-- Card com Gradiente Azul -->
    <div style="background: linear-gradient(135deg, #0066CC 0%, #003D7A 100%); 
                color: white; padding: 40px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,102,204,0.3);">
        
        <!-- Header -->
        <div style="text-align: center; margin-bottom: 30px;">
            <h1 style="margin: 0 0 10px 0; font-size: 28px; font-weight: bold;">
                Smart Core Tenant
            </h1>
            <p style="margin: 0; font-size: 13px; opacity: 0.9;">Versão {{ version }}</p>
        </div>
        
        <!-- Badge do Canal -->
        <div style="background: rgba(255,255,255,0.15); padding: 15px; 
                    margin: 20px 0; border-radius: 8px; text-align: center;">
            <p style="margin: 0; font-size: 20px; font-weight: bold;">
                🔧 {{ channel|upper }}
            </p>
            <p style="margin: 5px 0 0 0; font-size: 11px; opacity: 0.85;">
                Apenas para desenvolvimento/testes internos
            </p>
        </div>
        
        <!-- Release Notes -->
        <div style="margin: 25px 0;">
            <h3 style="margin: 0 0 12px 0; font-size: 14px; text-transform: uppercase; 
                       letter-spacing: 0.5px;">Release Notes</h3>
            <ul style="margin: 0; padding-left: 20px; font-size: 13px; line-height: 1.6;">
                {% for note in notes %}
                <li>{{ note }}</li>
                {% endfor %}
            </ul>
        </div>
        
        <!-- Botões de Ação -->
        <div style="margin-top: 30px; text-align: center;">
            <a href="{{ download_url }}" 
               download="SmartCoreTenant-0.1.0-beta-Setup.exe"
               style="background: white; color: #0066CC; padding: 14px 35px;
                      text-decoration: none; border-radius: 8px; font-weight: bold;
                      display: inline-block; margin: 10px 5px; font-size: 14px;
                      transition: all 0.3s ease; cursor: pointer;
                      box-shadow: 0 2px 8px rgba(0,0,0,0.2);">
                ⬇ Baixar Setup.exe
            </a>
            
            <a href="{% url 'admin:index' %}" 
               style="background: rgba(255,255,255,0.2); color: white; padding: 14px 35px;
                      text-decoration: none; border-radius: 8px; font-weight: 600;
                      display: inline-block; margin: 10px 5px; font-size: 14px;
                      transition: all 0.3s ease; cursor: pointer;">
                ← Voltar ao Admin
            </a>
        </div>
        
        <!-- Footer -->
        <div style="margin-top: 25px; padding-top: 20px; border-top: 1px solid rgba(255,255,255,0.2);
                    text-align: center; font-size: 11px; opacity: 0.8;">
            <p style="margin: 0;">
                Publicado: {{ release_date }}<br>
                SHA256: {{ sha256|slice:":16" }}...
            </p>
        </div>
        
    </div>
    
    <!-- Dica de Uso -->
    <div style="margin-top: 30px; padding: 15px; background: #f0f0f0; 
                border-left: 4px solid #0066CC; border-radius: 4px; font-size: 12px;">
        <strong>💡 Dica:</strong> Copie o link abaixo para compartilhar com outros devs:
        <div style="background: white; padding: 8px; margin-top: 8px; border-radius: 3px;
                    font-family: monospace; word-break: break-all; color: #666;">
            {{ download_url }}
        </div>
    </div>
    
</div>
{% endblock %}
```

2. Crie a view em `views.py`:

```python
from django.shortcuts import render
from django.contrib.admin.views.decorators import staff_member_required

@staff_member_required
def download_smartcore(request):
    context = {
        'version': '0.1.0-beta',
        'channel': 'beta',
        'download_url': 'https://releases.smartcoreassistant.com.br/download/0.1.0-beta/SmartCoreTenant-0.1.0-beta-Setup.exe',
        'release_date': '2026-10-03',
        'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        'notes': [
            '✅ Primeira versão beta do Smart Core Tenant',
            '✅ Integração com Velopack para auto-updates',
            '✅ Branding profissional com identidade visual Smart Core',
            '✅ Suporte a Windows 10+',
            '⚠️ Status: Em desenvolvimento - não use em produção',
        ]
    }
    return render(request, 'admin/download_smartcore.html', context)
```

3. Registre no `urls.py`:

```python
from .views import download_smartcore

urlpatterns = [
    path('admin/download-smartcore-beta/', download_smartcore, name='download_smartcore_beta'),
]
```

4. Acesso:
```
https://dev.smartcoreassistant.com.br/admin/download-smartcore-beta/
```

---

## 🔗 LINKS ÚTEIS

| Recurso | URL |
|---------|-----|
| **Download Direto** | https://releases.smartcoreassistant.com.br/download/0.1.0-beta/SmartCoreTenant-0.1.0-beta-Setup.exe |
| **API de Releases** | https://releases.smartcoreassistant.com.br/api/releases?channel=beta |
| **Branding Guide** | `/infra/branding/BRANDING_GUIDE.md` |
| **Setup Documentation** | `/infra/windows/README.md` |

---

## 📋 CHECKLIST DE IMPLEMENTAÇÃO

- [ ] Arquivo view criado em `admin.py` ou `views.py`
- [ ] URL registrada em `urls.py`
- [ ] Template HTML criado (se usar opção profissional)
- [ ] Testado em: `dev.smartcoreassistant.com.br/admin/download-smartcore-beta/`
- [ ] Link de download baixando corretamente
- [ ] Arquivo recebido: `SmartCoreTenant-0.1.0-beta-Setup.exe`

---

## 🧪 TESTES

1. **Acessar como admin:**
```
https://dev.smartcoreassistant.com.br/admin/download-smartcore-beta/
```

2. **Clicar em "Baixar Setup.exe"**

3. **Verificar:**
   - Arquivo inicia o download
   - Nome: `SmartCoreTenant-0.1.0-beta-Setup.exe`
   - Tamanho: ~76 bytes (placeholder) → ~50-80 MB (real, após NSIS)

---

## 🚀 PRÓXIMAS FASES

Após integração:

1. **CI/CD Workflow** — Compilar NSIS automaticamente
2. **Servidor Releases** — Deploy do Axum server
3. **Velopack Integration** — Auto-updates no cliente
4. **Landing Page** — Ativar botão para produção

---

**Última atualização:** 2026-10-03  
**Responsável:** Claude Code  
**Status:** Pronto para implementação

