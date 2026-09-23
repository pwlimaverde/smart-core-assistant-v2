//! Mapa rota → escopo exigido (N13.3).
//!
//! # O problema que este arquivo resolve
//!
//! Até aqui, `encaminhar_tenant` exigia `tenant:admin` para **todas** as rotas
//! que passam por ele. O efeito prático era duplo e contraditório:
//!
//! * **rígido demais** — um `manager` ou `staff` não conseguia criar um
//!   departamento, editar um fluxo ou cadastrar um treinamento. Como o painel só
//!   mostra o que o backend aceita, o catálogo de 14 escopos do doc 09 §3 estava
//!   documentado e não aplicado: na prática só existiam dois papéis, admin e
//!   ninguém;
//! * **frouxo demais** do outro lado — os handlers operacionais escritos à mão
//!   (enviar mensagem, mover atendimento, ler thread) exigiam apenas sessão
//!   válida, então um `viewer` mandava mensagem para o cliente final.
//!
//! O mapa abaixo corrige a primeira metade; os `exigir_escopo` espalhados nos
//! handlers operacionais corrigem a segunda.
//!
//! # Fail-closed
//!
//! Rota que não estiver declarada aqui é **negada**, não liberada. É a diferença
//! entre esquecer de restringir (que passa despercebido) e esquecer de declarar
//! (que aparece no primeiro teste). O teste
//! `toda_rota_de_encaminhar_tenant_tem_escopo_declarado` lê o próprio
//! `grpc_web.rs` e falha se uma rota nova entrar sem passar por aqui.

/// Escopos que satisfazem uma rota. Basta **um** deles.
///
/// `tenant:admin` e o coringa `*` do superusuário não aparecem nas listas: são
/// tratados em [`autorizado`] como implicando qualquer escopo, exatamente como
/// `RequestContext::has_permission` faz do lado do banco.
/// Rotas que **só** o administrador do tenant pode chamar.
///
/// Lista vazia NÃO significa "qualquer sessão passa": [`autorizado`] só devolve
/// `true` para uma lista vazia quando a sessão já tem `tenant:admin` ou o
/// coringa `*`. A constante existe para que quem lê o mapa não precise deduzir
/// isso a partir de um `&[]` solto.
pub const SOMENTE_ADMIN: &[&str] = &[];

pub const MAPA: &[(&str, &[&str])] = &[
    // --- Kanban: ver o quadro é leitura de atendimento; mexer na estrutura do
    // --- quadro é administração de Kanban.
    ("ListFluxos", &["atendimentos:read"]),
    ("ListEtapasFluxo", &["atendimentos:read"]),
    ("CreateFluxo", &["kanban:admin"]),
    ("UpdateFluxo", &["kanban:admin"]),
    ("DesativarFluxo", &["kanban:admin"]),
    ("CreateEtapaFluxo", &["kanban:admin"]),
    ("UpdateEtapaFluxo", &["kanban:admin"]),
    ("DesativarEtapaFluxo", &["kanban:admin"]),
    ("MoverEtapaFluxo", &["kanban:admin"]),
    // --- Estrutura operacional: departamentos, atendentes e conexões.
    ("ListDepartamentos", &["operacional:read"]),
    ("CreateDepartamento", &["operacional:admin"]),
    ("UpdateDepartamento", &["operacional:admin"]),
    ("DesativarDepartamento", &["operacional:admin"]),
    ("ListAtendentes", &["operacional:read"]),
    ("CreateAtendente", &["operacional:admin"]),
    ("UpdateAtendente", &["operacional:admin"]),
    ("DesativarAtendente", &["operacional:admin"]),
    ("ListWhatsappInstances", &["operacional:read"]),
    ("GetWhatsappInstanceStatus", &["operacional:read"]),
    ("CreateWhatsappInstance", &["operacional:admin"]),
    ("ReconnectWhatsappInstance", &["operacional:admin"]),
    ("DeleteWhatsappInstance", &["operacional:admin"]),
    // P7 — encerrar a sessão é do administrador pelo mesmo motivo que remover:
    // derruba o número do tenant inteiro. Ver o detalhe é leitura.
    ("DisconnectWhatsappInstance", &["operacional:admin"]),
    ("DetalheDaConexao", &["operacional:read"]),
    // P13 — a foto do contato é buscada para quem abre a conversa.
    ("GetWhatsappProfilePicture", &["atendimentos:read"]),
    ("ListDepartamentosDasConexoes", &["operacional:read"]),
    ("DefinirDepartamentoDaConexao", &["operacional:admin"]),
    // P7 — os números ignorados. Ler é `operacional:read` porque a lista explica
    // por que uma conversa nunca aparece; mexer nela é do administrador, já que
    // ignorar um número cala o atendimento daquela pessoa para todo mundo.
    ("ListNumerosIgnorados", &["operacional:read"]),
    ("CriarNumeroIgnorado", &["operacional:admin"]),
    ("AtualizarNumeroIgnorado", &["operacional:admin"]),
    ("RemoverNumeroIgnorado", &["operacional:admin"]),
    // D3 (plano `regras-do-bot-e-permissoes`). Os escopos abaixo são os que a
    // própria fase D3 documentou nos handlers — não escolhi por conta própria:
    //
    // · calar o bot da CONEXÃO muda o produto para todos os atendentes do
    //   tenant, então é decisão de administrador;
    // · calar o bot de UMA CONVERSA é decisão de quem atende aquela conversa, e
    //   o `data_postgres` revalida com `atendimentos:write` ou `tenant:admin`.
    ("DefinirRespostaBotInstancia", SOMENTE_ADMIN),
    ("DefinirBotDaConversa", &["atendimentos:write"]),
    // C3: abrir conversa é escrever no atendimento, não configurar o tenant.
    ("IniciarAtendimentoManual", &["atendimentos:write"]),
    // N9 E13 — desenhar a ficha é configurar o tenant, não atender.
    //
    // A chave é o método do ENVELOPE, não o nome do RPC: é ele que o
    // `encaminhar_tenant` manda ao data_postgres, e é ele que o teste de
    // cobertura deste mapa lê do `grpc_web.rs`.
    ("ListCamposPersonalizados", &["configuracoes:read"]),
    ("CreateCampoPersonalizado", &["configuracoes:write"]),
    ("UpdateCampoPersonalizado", &["configuracoes:write"]),
    ("DesativarCampoPersonalizado", &["configuracoes:write"]),
    // Já PREENCHER é atender: quem está na conversa é quem sabe o valor, e
    // exigir escopo de configuração para digitar na ficha travaria o
    // atendente no meio do atendimento.
    ("SetValorCampo", &["atendimentos:write"]),
    // --- Base de conhecimento do assistente.
    ("ListTreinamentos", &["treinamento:read"]),
    ("GetTreinamento", &["treinamento:read"]),
    ("QueryCompose", &["treinamento:read"]),
    ("CreateTreinamento", &["treinamento:write"]),
    ("RegistrarFeedbackTeste", &["treinamento:write"]),
    ("FinalizarTreinamento", &["treinamento:write"]),
    ("RemoverTreinamento", &["treinamento:write"]),
    ("ListIntents", &["treinamento:read"]),
    ("CreateIntent", &["treinamento:write"]),
    ("UpdateIntent", &["treinamento:write"]),
    ("RemoveIntent", &["treinamento:write"]),
    // --- Atendimento: detalhe, etiqueta e nota.
    ("GetDetalheAtendimento", &["atendimentos:read"]),
    ("CreateEtiqueta", &["atendimentos:write"]),
    ("AlternarEtiqueta", &["atendimentos:write"]),
    ("CreateNota", &["atendimentos:write"]),
    // --- Contatos.
    // Quem atende também procura o cliente — para abrir conversa (C3) e para
    // saber com quem fala. O `data_postgres` já aceitava `atendimentos:read`
    // aqui; só a borda barrava, e um `staff` convidado com os escopos padrão
    // não achava ninguém no "iniciar atendimento".
    ("ListContatos", &["clientes:read", "atendimentos:read"]),
    // C4 — cadastrar e corrigir o cliente é mexer no cadastro dele, não
    // configurar o tenant nem atender.
    ("CreateContato", &["clientes:write"]),
    ("UpdateContato", &["clientes:write"]),
    ("DefinirContatoAtivo", &["clientes:write"]),
    // B10 (N11 E5) — cadastro de clientes é dado de negócio do tenant: lê quem
    // lê cliente, escreve quem escreve cliente.
    ("ListClientes", &["clientes:read"]),
    ("ListContatosDoCliente", &["clientes:read"]),
    ("CreateCliente", &["clientes:write"]),
    ("UpdateCliente", &["clientes:write"]),
    ("DefinirClienteAtivo", &["clientes:write"]),
    ("VincularContatoCliente", &["clientes:write"]),
    // --- Painel e configuração.
    ("GetPainelTenant", &["atendimentos:read"]),
    ("UpdateTenantConfig", &["configuracoes:write"]),
    // Onboarding é a configuração inicial da conta: quem o conclui está
    // decidindo como o negócio funciona, não operando o dia a dia.
    ("GetOnboardingProgress", &["configuracoes:read"]),
    ("SetOnboardingProgress", &["configuracoes:write"]),
];

/// Escopos exigidos por uma rota. `None` = rota não declarada (negada).
pub fn escopos_da_rota(metodo: &str) -> Option<&'static [&'static str]> {
    MAPA.iter()
        .find(|(rota, _)| *rota == metodo)
        .map(|(_, escopos)| *escopos)
}

/// `true` se os escopos da sessão satisfazem os exigidos.
///
/// `tenant:admin` implica todos os demais (doc 09 §3) e `*` é o coringa do
/// superusuário. Fora isso, basta possuir **um** dos escopos exigidos.
pub fn autorizado(escopos_da_sessao: &[String], exigidos: &[&str], is_superuser: bool) -> bool {
    if is_superuser {
        return true;
    }
    if escopos_da_sessao
        .iter()
        .any(|s| s == "*" || s == "tenant:admin")
    {
        return true;
    }
    exigidos
        .iter()
        .any(|exigido| escopos_da_sessao.iter().any(|s| s == exigido))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(itens: &[&str]) -> Vec<String> {
        itens.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn nenhuma_rota_declarada_duas_vezes() {
        let mut vistas = std::collections::HashSet::new();
        for (rota, _) in MAPA {
            assert!(vistas.insert(*rota), "rota declarada duas vezes: {rota}");
        }
    }

    #[test]
    fn lista_vazia_de_escopos_significa_somente_admin() {
        // Este teste substituiu um que proibia lista vazia "porque significaria
        // qualquer sessão passa". O motivo estava errado: `autorizado` com lista
        // vazia só aceita `tenant:admin` ou o coringa. O que vale testar é o
        // comportamento, não a forma — e ele é o mais restritivo possível.
        let admin = v(&["tenant:admin"]);
        let staff = v(&["clientes:read", "atendimentos:read", "atendimentos:write"]);

        assert!(autorizado(&admin, SOMENTE_ADMIN, false));
        assert!(autorizado(&[], SOMENTE_ADMIN, true)); // superusuário
        assert!(!autorizado(&staff, SOMENTE_ADMIN, false));
        assert!(!autorizado(&[], SOMENTE_ADMIN, false));
    }

    #[test]
    fn rota_de_bot_por_conexao_e_so_do_admin_e_a_de_conversa_e_de_quem_atende() {
        // Vieram da fase D3, que chegou pela dev. O par existe porque a decisão
        // tem alcance diferente: calar o bot de um número afeta todos os
        // atendentes; calar o de uma conversa afeta uma conversa.
        let staff = v(&["clientes:read", "atendimentos:read", "atendimentos:write"]);

        assert!(!autorizado(
            &staff,
            escopos_da_rota("DefinirRespostaBotInstancia").unwrap(),
            false
        ));
        assert!(autorizado(
            &staff,
            escopos_da_rota("DefinirBotDaConversa").unwrap(),
            false
        ));
    }

    #[test]
    fn nenhuma_rota_exige_tenant_admin_explicitamente() {
        // `tenant:admin` é implícito em `autorizado`. Declará-lo numa rota
        // sugeriria que ele é exigência daquela rota em particular, quando na
        // verdade ele satisfaz todas.
        for (rota, escopos) in MAPA {
            assert!(
                !escopos.contains(&"tenant:admin"),
                "{rota} declara tenant:admin, que já é implícito"
            );
        }
    }

    #[test]
    fn toda_rota_de_encaminhar_tenant_tem_escopo_declarado() {
        // Lê o próprio `grpc_web.rs` e extrai o método passado a cada chamada de
        // `encaminhar_tenant`. É o teste que faz o mapa não ficar para trás: uma
        // rota nova sem escopo declarado quebra aqui, e não em produção.
        let fonte = include_str!("grpc_web.rs");
        let mut faltando: Vec<String> = Vec::new();

        for (i, _) in fonte.match_indices("encaminhar_tenant(") {
            let janela = &fonte[i..(i + 400).min(fonte.len())];
            // O método é a primeira string literal depois do `&self.deps.pg`/
            // destino — na prática, a primeira string entre aspas da janela que
            // comece com maiúscula.
            let Some(metodo) = janela.split('"').skip(1).step_by(2).find(|s| {
                s.chars()
                    .next()
                    .map(|c| c.is_ascii_uppercase())
                    .unwrap_or(false)
            }) else {
                continue;
            };
            if escopos_da_rota(metodo).is_none() {
                faltando.push(metodo.to_string());
            }
        }

        faltando.sort();
        faltando.dedup();
        assert!(
            faltando.is_empty(),
            "rotas de encaminhar_tenant sem escopo declarado em rbac::MAPA: {faltando:?}"
        );
    }

    #[test]
    fn rota_nao_declarada_e_negada() {
        assert!(escopos_da_rota("RotaQueNaoExiste").is_none());
    }

    #[test]
    fn superusuario_passa_em_qualquer_rota() {
        assert!(autorizado(&[], &["operacional:admin"], true));
    }

    #[test]
    fn tenant_admin_implica_todos_os_escopos() {
        assert!(autorizado(
            &v(&["tenant:admin"]),
            &["treinamento:write"],
            false
        ));
    }

    #[test]
    fn manager_agora_edita_fluxo() {
        // Antes desta fase, `kanban:admin` não bastava: `encaminhar_tenant`
        // exigia `tenant:admin` em toda rota, e só o admin editava fluxo.
        let manager = v(&[
            "atendimentos:read",
            "atendimentos:write",
            "clientes:read",
            "clientes:write",
            "operacional:read",
            "operacional:admin",
            "kanban:admin",
            "treinamento:read",
            "treinamento:write",
            "configuracoes:read",
            "financeiro:read",
        ]);
        let exigidos = escopos_da_rota("UpdateFluxo").unwrap();
        assert!(autorizado(&manager, exigidos, false));
    }

    #[test]
    fn manager_nao_altera_configuracao_sensivel() {
        // O mesmo `manager` não tem `configuracoes:write` — chaves de API e
        // prompts continuam fora do alcance dele.
        let manager = v(&["configuracoes:read", "operacional:admin"]);
        let exigidos = escopos_da_rota("UpdateTenantConfig").unwrap();
        assert!(!autorizado(&manager, exigidos, false));
    }

    #[test]
    fn viewer_le_o_quadro_mas_nao_o_reorganiza() {
        let viewer = v(&[
            "atendimentos:read",
            "clientes:read",
            "operacional:read",
            "treinamento:read",
            "configuracoes:read",
            "financeiro:read",
        ]);
        assert!(autorizado(
            &viewer,
            escopos_da_rota("ListFluxos").unwrap(),
            false
        ));
        assert!(!autorizado(
            &viewer,
            escopos_da_rota("MoverEtapaFluxo").unwrap(),
            false
        ));
        assert!(!autorizado(
            &viewer,
            escopos_da_rota("CreateNota").unwrap(),
            false
        ));
    }

    #[test]
    fn staff_cria_nota_mas_nao_mexe_em_departamento() {
        let staff = v(&["clientes:read", "atendimentos:read", "atendimentos:write"]);
        assert!(autorizado(
            &staff,
            escopos_da_rota("CreateNota").unwrap(),
            false
        ));
        assert!(!autorizado(
            &staff,
            escopos_da_rota("CreateDepartamento").unwrap(),
            false
        ));
    }

    #[test]
    fn sessao_sem_escopo_nenhum_nao_passa_em_nada() {
        for (rota, escopos) in MAPA {
            assert!(
                !autorizado(&[], escopos, false),
                "sessão vazia passou em {rota}"
            );
        }
    }
}
