-- O atendente nunca era ligado ao login: o cadastro gravava o e-mail, mas
-- nenhum caminho preenchia `usuario_id`. Sem o vínculo, "Assumir", o filtro
-- "Minhas" e o aviso de conversa atribuída não funcionavam em tenant nenhum
-- ("seu usuário não está cadastrado como atendente").
--
-- Liga cada atendente ativo e sem vínculo ao usuário de mesmo e-mail que é
-- membro ativo do MESMO tenant — nunca a um login de fora dele. Um login fica
-- com um atendente só por tenant (o de menor id, se houver repetição).
UPDATE oraculo_atendente a
   SET usuario_id = v.user_id
  FROM (
        SELECT DISTINCT ON (a2.tenant_id, u.id) a2.id AS atendente_id, u.id AS user_id
          FROM oraculo_atendente a2
          JOIN auth_user u
            ON lower(trim(u.email)) = lower(trim(a2.email))
          JOIN tenants_tenantuser tu
            ON tu.user_id = u.id AND tu.tenant_id = a2.tenant_id AND tu.is_active
         WHERE a2.usuario_id IS NULL
           AND a2.ativo
           AND trim(a2.email) <> ''
           AND NOT EXISTS (
                 SELECT 1 FROM oraculo_atendente j
                  WHERE j.tenant_id = a2.tenant_id AND j.usuario_id = u.id
               )
         ORDER BY a2.tenant_id, u.id, a2.id
       ) v
 WHERE a.id = v.atendente_id;
