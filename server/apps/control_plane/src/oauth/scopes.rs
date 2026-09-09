//! Catálogo canônico de escopos (doc 09 §3) na forma que a tela de
//! consentimento precisa: rótulo em linguagem de negócio e ordem estável.
//!
//! O catálogo existe em três lugares no sistema — aqui, no `derivar_escopos` do
//! login e no `scopes.py` do `mcp_server`. Os três precisam concordar, e o teste
//! `catalogo_cobre_todos_os_escopos_do_doc_09` abaixo é a trava: se alguém
//! acrescentar um escopo ao doc sem acrescentá-lo aqui, o consentimento nunca o
//! ofereceria e o usuário não teria como conceder algo que já possui.

/// Um escopo como o usuário o vê na tela de consentimento.
pub struct EscopoDescrito {
    pub escopo: &'static str,
    /// O que ele libera, em português comum. É isto que a pessoa lê antes de
    /// aprovar — `atendimentos:write` não diz nada a quem não escreveu o sistema.
    pub rotulo: &'static str,
    /// `true` quando a concessão permite alterar o mundo (escrever, enviar,
    /// remover). A tela destaca estes.
    pub escrita: bool,
}

/// Ordem canônica: leitura antes de escrita, e o administrativo por último. A
/// ordem é fixa porque a tela não pode reordenar entre uma visita e outra — e
/// porque `tools/list` no `mcp_server` também depende de ordem determinística.
pub const CATALOGO: &[EscopoDescrito] = &[
    EscopoDescrito {
        escopo: "atendimentos:read",
        rotulo: "Ver atendimentos e mensagens",
        escrita: false,
    },
    EscopoDescrito {
        escopo: "atendimentos:write",
        rotulo: "Criar e mover atendimentos, e enviar mensagens a clientes",
        escrita: true,
    },
    EscopoDescrito {
        escopo: "clientes:read",
        rotulo: "Ver contatos e clientes",
        escrita: false,
    },
    EscopoDescrito {
        escopo: "clientes:write",
        rotulo: "Criar e editar contatos e clientes",
        escrita: true,
    },
    EscopoDescrito {
        escopo: "operacional:read",
        rotulo: "Ver departamentos e atendentes",
        escrita: false,
    },
    EscopoDescrito {
        escopo: "operacional:admin",
        rotulo: "Gerenciar departamentos, atendentes e conexões de WhatsApp",
        escrita: true,
    },
    EscopoDescrito {
        escopo: "kanban:admin",
        rotulo: "Acesso a todos os fluxos do Kanban, sem restrição por fluxo",
        escrita: true,
    },
    EscopoDescrito {
        escopo: "treinamento:read",
        rotulo: "Ver a base de conhecimento do assistente",
        escrita: false,
    },
    EscopoDescrito {
        escopo: "treinamento:write",
        rotulo: "Criar e editar treinamentos e documentos do assistente",
        escrita: true,
    },
    EscopoDescrito {
        escopo: "financeiro:read",
        rotulo: "Ver assinatura e lançamentos financeiros",
        escrita: false,
    },
    EscopoDescrito {
        escopo: "financeiro:write",
        rotulo: "Registrar lançamentos financeiros",
        escrita: true,
    },
    EscopoDescrito {
        escopo: "configuracoes:read",
        rotulo: "Ver as configurações do negócio",
        escrita: false,
    },
    EscopoDescrito {
        escopo: "configuracoes:write",
        rotulo: "Alterar configurações, prompts e integrações",
        escrita: true,
    },
    EscopoDescrito {
        escopo: "tenant:admin",
        rotulo: "Administrar tudo no negócio (inclui todos os itens acima)",
        escrita: true,
    },
];

/// Todos os escopos do catálogo, na ordem canônica.
pub fn todos() -> Vec<&'static str> {
    CATALOGO.iter().map(|e| e.escopo).collect()
}

pub fn descricao(escopo: &str) -> Option<&'static EscopoDescrito> {
    CATALOGO.iter().find(|e| e.escopo == escopo)
}

/// Expande os escopos efetivos de um usuário para o que ele pode **oferecer** no
/// consentimento.
///
/// Duas regras do doc 09 vivem aqui: `tenant:admin` implica todos os demais, e o
/// coringa `*` do superusuário implica tudo. Sem esta expansão, um `admin` — que
/// carrega só `tenant:admin` no JWT — veria uma tela de consentimento com um
/// único item e não conseguiria conceder leitura de atendimentos a um agente.
pub fn escopos_ofertaveis(escopos_do_usuario: &[String]) -> Vec<&'static str> {
    let tem_tudo = escopos_do_usuario
        .iter()
        .any(|s| s == "*" || s == "tenant:admin");
    if tem_tudo {
        return todos();
    }
    CATALOGO
        .iter()
        .filter(|e| escopos_do_usuario.iter().any(|s| s == e.escopo))
        .map(|e| e.escopo)
        .collect()
}

/// Interseção usada em **toda** emissão de access token: o que o grant concedeu
/// ∩ o que o usuário ainda tem hoje.
///
/// É o que faz um rebaixamento no painel encolher o agente na renovação seguinte
/// sem que ninguém precise mexer no grant. A ordem de saída é a do catálogo,
/// nunca a de entrada — `tools/list` do `mcp_server` depende disso.
pub fn interseccionar(concedidos: &[String], atuais_do_usuario: &[String]) -> Vec<String> {
    let ofertaveis = escopos_ofertaveis(atuais_do_usuario);
    CATALOGO
        .iter()
        .map(|e| e.escopo)
        .filter(|escopo| {
            ofertaveis.contains(escopo) && concedidos.iter().any(|c| c == escopo)
        })
        .map(str::to_string)
        .collect()
}

/// Filtra uma lista pedida pelo cliente, descartando o que não existe no
/// catálogo. Escopo desconhecido é ignorado em silêncio (conforme OAuth 2.1: o
/// AS pode conceder menos do que foi pedido), nunca propagado.
pub fn apenas_conhecidos(pedidos: &[String]) -> Vec<String> {
    CATALOGO
        .iter()
        .map(|e| e.escopo)
        .filter(|escopo| pedidos.iter().any(|p| p == escopo))
        .map(str::to_string)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(itens: &[&str]) -> Vec<String> {
        itens.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn catalogo_cobre_os_14_escopos_do_doc_09() {
        // O doc 09 §3 lista 14 escopos. Se este número mudar, ou o doc mudou e o
        // catálogo ficou para trás, ou alguém acrescentou escopo sem documentar.
        assert_eq!(CATALOGO.len(), 14);
    }

    #[test]
    fn catalogo_nao_tem_escopo_repetido() {
        let mut vistos = std::collections::HashSet::new();
        for e in CATALOGO {
            assert!(vistos.insert(e.escopo), "escopo duplicado: {}", e.escopo);
        }
    }

    #[test]
    fn tenant_admin_oferta_o_catalogo_inteiro() {
        assert_eq!(escopos_ofertaveis(&v(&["tenant:admin"])), todos());
    }

    #[test]
    fn superusuario_oferta_o_catalogo_inteiro() {
        assert_eq!(escopos_ofertaveis(&v(&["*"])), todos());
    }

    #[test]
    fn staff_nao_enxerga_tenant_admin_para_marcar() {
        // O DoD do plano em uma linha: a regra do subconjunto é a própria tela.
        let ofertaveis = escopos_ofertaveis(&v(&[
            "clientes:read",
            "atendimentos:read",
            "atendimentos:write",
        ]));
        assert!(!ofertaveis.contains(&"tenant:admin"));
        assert!(!ofertaveis.contains(&"configuracoes:write"));
        assert_eq!(ofertaveis.len(), 3);
    }

    #[test]
    fn intersecao_encolhe_quando_o_usuario_e_rebaixado() {
        let concedidos = v(&["atendimentos:read", "atendimentos:write", "tenant:admin"]);
        // Depois do rebaixamento o usuário só tem leitura.
        let efetivos = interseccionar(&concedidos, &v(&["atendimentos:read"]));
        assert_eq!(efetivos, vec!["atendimentos:read".to_string()]);
    }

    #[test]
    fn intersecao_nunca_amplia_alem_do_concedido() {
        // Usuário virou admin depois de conectar: o grant continua valendo o que
        // ele era. Promoção não amplia agente já conectado sem novo consentimento.
        let concedidos = v(&["atendimentos:read"]);
        let efetivos = interseccionar(&concedidos, &v(&["tenant:admin"]));
        assert_eq!(efetivos, vec!["atendimentos:read".to_string()]);
    }

    #[test]
    fn intersecao_sai_na_ordem_do_catalogo_e_nao_na_de_entrada() {
        let concedidos = v(&["clientes:read", "atendimentos:read"]);
        let efetivos = interseccionar(&concedidos, &v(&["tenant:admin"]));
        assert_eq!(
            efetivos,
            vec!["atendimentos:read".to_string(), "clientes:read".to_string()]
        );
    }

    #[test]
    fn escopo_desconhecido_e_descartado_e_nao_propagado() {
        let pedidos = v(&["atendimentos:read", "tudo:agora", "admin"]);
        assert_eq!(
            apenas_conhecidos(&pedidos),
            vec!["atendimentos:read".to_string()]
        );
    }
}
