use crate::common::{criar_tenant_para_teste, obter_admin_pool_teste, obter_pool_teste};
use infrastructure_postgres::{
    auth::users::{AuthUserRepository, PostgresAuthUserRepository},
    hash_password,
    tenants::tenants::{
        PostgresTenantInviteRepository, PostgresTenantUserRepository, TenantInviteRepository,
        TenantUserRepository,
    },
    verify_password, DbError,
};
use uuid::Uuid;

#[tokio::test]
async fn test_auth_user_criar_e_buscar() {
    let pool = obter_admin_pool_teste().await;
    let repo = PostgresAuthUserRepository;

    let username = format!("user_{}", Uuid::new_v4().simple());
    let email = format!("{}@test.com", Uuid::new_v4().simple());
    let hash = hash_password("senha123").unwrap();

    let user = repo
        .criar(&pool, &username, &email, &hash, false)
        .await
        .expect("Falha ao criar auth_user");

    assert_eq!(user.username, username);
    assert_eq!(user.email, email);
    assert!(user.is_active);
    assert!(!user.is_superuser);

    let por_id = repo
        .buscar_por_id(&pool, user.id)
        .await
        .unwrap()
        .expect("Deve encontrar por id");
    assert_eq!(por_id.id, user.id);

    let por_username = repo
        .buscar_por_username(&pool, &username)
        .await
        .unwrap()
        .expect("Deve encontrar por username");
    assert_eq!(por_username.id, user.id);

    let por_email = repo
        .buscar_por_email(&pool, &email)
        .await
        .unwrap()
        .expect("Deve encontrar por email");
    assert_eq!(por_email.id, user.id);

    // Limpeza (best-effort — não falha o teste se houver corrida de teardown)
    let _ = sqlx::query!("DELETE FROM auth_user WHERE id = $1", user.id)
        .execute(&pool)
        .await;
}

#[tokio::test]
async fn test_atualizar_senha_e_login() {
    let pool = obter_admin_pool_teste().await;
    let repo = PostgresAuthUserRepository;

    let username = format!("upd_{}", Uuid::new_v4().simple());
    let email = format!("{}@test.com", Uuid::new_v4().simple());
    let hash_inicial = hash_password("senha_antiga").unwrap();

    let user = repo
        .criar(&pool, &username, &email, &hash_inicial, false)
        .await
        .expect("Falha ao criar auth_user");
    assert!(user.last_login.is_none(), "last_login inicia nulo");

    // Atualizar senha e confirmar que o novo hash verifica e o antigo não
    let novo_hash = hash_password("senha_nova").unwrap();
    repo.atualizar_senha(&pool, user.id, &novo_hash)
        .await
        .expect("Falha ao atualizar senha");
    let recarregado = repo.buscar_por_id(&pool, user.id).await.unwrap().unwrap();
    assert!(verify_password("senha_nova", &recarregado.password_hash));
    assert!(!verify_password("senha_antiga", &recarregado.password_hash));

    // Registrar último login
    repo.atualizar_ultimo_login(&pool, user.id)
        .await
        .expect("Falha ao atualizar último login");
    let pos_login = repo.buscar_por_id(&pool, user.id).await.unwrap().unwrap();
    assert!(pos_login.last_login.is_some(), "last_login deve ser setado");

    // Desativar
    repo.desativar(&pool, user.id)
        .await
        .expect("Falha ao desativar");
    let desativado = repo.buscar_por_id(&pool, user.id).await.unwrap().unwrap();
    assert!(!desativado.is_active, "usuário deve estar inativo");

    let _ = sqlx::query!("DELETE FROM auth_user WHERE id = $1", user.id)
        .execute(&pool)
        .await;
}

#[tokio::test]
async fn test_email_duplicado_retorna_erro() {
    let pool = obter_admin_pool_teste().await;
    let repo = PostgresAuthUserRepository;

    let email = format!("dup_{}@test.com", Uuid::new_v4().simple());
    let hash = hash_password("x").unwrap();
    let u1 = format!("u1_{}", Uuid::new_v4().simple());
    let u2 = format!("u2_{}", Uuid::new_v4().simple());

    let user = repo
        .criar(&pool, &u1, &email, &hash, false)
        .await
        .expect("Primeiro usuário deve ser criado");

    // Segundo usuário com o MESMO email viola o índice único parcial
    let err = repo
        .criar(&pool, &u2, &email, &hash, false)
        .await
        .expect_err("Email duplicado deve falhar");
    assert!(
        matches!(err, DbError::UniqueViolation(_)),
        "esperado UniqueViolation, veio: {err:?}"
    );

    let _ = sqlx::query!("DELETE FROM auth_user WHERE id = $1", user.id)
        .execute(&pool)
        .await;
}

#[tokio::test]
async fn test_password_hash_e_verify() {
    let hash = hash_password("minha_senha_segura").unwrap();
    assert!(
        hash.starts_with("$argon2id$"),
        "deve ser string PHC argon2id"
    );
    assert!(
        verify_password("minha_senha_segura", &hash),
        "senha correta deve verificar"
    );
    assert!(
        !verify_password("senha_errada", &hash),
        "senha errada deve falhar"
    );
}

#[tokio::test]
async fn test_criar_superuser() {
    let pool = obter_admin_pool_teste().await;
    let repo = PostgresAuthUserRepository;

    let username = format!("super_{}", Uuid::new_v4().simple());
    let email = format!("super_{}@system.com", Uuid::new_v4().simple());
    let hash = hash_password("super_senha").unwrap();

    let user = repo
        .criar(&pool, &username, &email, &hash, true)
        .await
        .expect("Falha ao criar superuser");

    assert!(user.is_superuser);

    // Confirmar que não há TenantUser associado (superuser é global, sem tenant)
    let tenant_user_repo = PostgresTenantUserRepository;
    let tenant_user = tenant_user_repo
        .buscar_por_user_id(&pool, user.id)
        .await
        .unwrap();
    assert!(
        tenant_user.is_none(),
        "superuser não deve ter TenantUser associado"
    );

    // Limpeza (best-effort — não falha o teste se houver corrida de teardown)
    let _ = sqlx::query!("DELETE FROM auth_user WHERE id = $1", user.id)
        .execute(&pool)
        .await;
}

#[tokio::test]
async fn test_invite_lookup_com_admin_pool() {
    let runtime_pool = obter_pool_teste().await;
    let admin_pool = obter_admin_pool_teste().await;

    // Criar tenant e convite via pool runtime (dentro de transação com RLS)
    let mut tx = runtime_pool.begin().await.unwrap();
    let tenant = criar_tenant_para_teste(&mut tx, "Tenant Invite Auth").await;

    let token = format!("tok_{}", Uuid::new_v4().simple());
    let expires_at = chrono::Utc::now() + chrono::Duration::hours(24);

    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant.id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query!(
        r#"INSERT INTO tenants_tenantinvite
               (tenant_id, email, name, role, token, expires_at)
           VALUES ($1, 'convidado@test.com', 'Convidado', 'staff', $2, $3)"#,
        tenant.id,
        token,
        expires_at
    )
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    // buscar_por_token deve funcionar com admin_pool (cross-tenant, sem RLS)
    let invite_repo = PostgresTenantInviteRepository;
    let invite = invite_repo
        .buscar_por_token(&admin_pool, &token)
        .await
        .expect("Falha em buscar_por_token")
        .expect("Convite deve ser encontrado com admin_pool");

    assert_eq!(invite.token, token);
    assert!(!invite.used);

    // marcar_usado também deve funcionar com admin_pool
    invite_repo
        .marcar_usado(&admin_pool, invite.id)
        .await
        .expect("Falha em marcar_usado");

    let invite_usado = invite_repo
        .buscar_por_token(&admin_pool, &token)
        .await
        .unwrap()
        .unwrap();
    assert!(invite_usado.used, "convite deve estar marcado como usado");

    // Limpeza
    let mut clean_tx = runtime_pool.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_tenant', $1, true)")
        .bind(tenant.id.to_string())
        .execute(&mut *clean_tx)
        .await
        .unwrap();
    sqlx::query!("DELETE FROM tenants_tenantinvite WHERE token = $1", token)
        .execute(&mut *clean_tx)
        .await
        .unwrap();
    sqlx::query!("DELETE FROM tenants_tenant WHERE id = $1", tenant.id)
        .execute(&mut *clean_tx)
        .await
        .unwrap();
    clean_tx.commit().await.unwrap();
}
