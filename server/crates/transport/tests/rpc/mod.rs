use contracts::{Envelope, MessageKind};
use std::time::Duration;
use transport::codec::FlatbuffersCodec;
use transport::error::TransportError;
use transport::runtime::{Endpoint, MuxClient, Server};

#[tokio::test]
async fn test_rpc_flow_success() {
    let addr_str = "tcp://127.0.0.1:28491";
    let endpoint = Endpoint::parse(addr_str).unwrap();

    // 1. Configura e spawna o servidor RPC
    let server = Server::new(endpoint.clone(), "flatbuffers").route("Ping", |env| {
        Box::pin(async move {
            Envelope {
                kind: MessageKind::Reply as i32,
                method: "PingReply".to_string(),
                payload: b"Pong".to_vec(),
                ..env
            }
        })
    });

    let server_handle = tokio::spawn(async move {
        server.run().await.unwrap();
    });

    // Dá um tempo curto para o TcpListener vincular à porta
    tokio::time::sleep(Duration::from_millis(200)).await;

    // 2. Conecta o cliente e executa a chamada
    let codec = Box::new(FlatbuffersCodec);
    let client = MuxClient::conectar(endpoint, codec)
        .await
        .expect("Falha ao conectar cliente");

    let request = Envelope {
        tenant_id: "tenant-1".to_string(),
        schema_version: 1,
        message_id: "msg-1".to_string(),
        causation_id: "".to_string(),
        traceparent: "".to_string(),
        occurred_at: 0,
        kind: MessageKind::Request as i32,
        method: "Ping".to_string(),
        payload: vec![],
        error: None,
        auth_user_id: 0,
        auth_scopes: vec![],
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let response = client
        .call(request, Duration::from_secs(2))
        .await
        .expect("Falha na chamada RPC");

    assert_eq!(response.method, "PingReply");
    assert_eq!(response.payload, b"Pong");
    assert!(response.error.is_none());

    // Limpa a task do servidor
    server_handle.abort();
}

#[tokio::test]
async fn test_rpc_flow_method_not_found() {
    let addr_str = "tcp://127.0.0.1:28492";
    let endpoint = Endpoint::parse(addr_str).unwrap();

    let server = Server::new(endpoint.clone(), "flatbuffers");
    let server_handle = tokio::spawn(async move {
        server.run().await.unwrap();
    });

    tokio::time::sleep(Duration::from_millis(200)).await;

    let codec = Box::new(FlatbuffersCodec);
    let client = MuxClient::conectar(endpoint, codec).await.unwrap();

    let request = Envelope {
        tenant_id: "tenant-1".to_string(),
        schema_version: 1,
        message_id: "msg-2".to_string(),
        causation_id: "".to_string(),
        traceparent: "".to_string(),
        occurred_at: 0,
        kind: MessageKind::Request as i32,
        method: "MetodoInexistente".to_string(),
        payload: vec![],
        error: None,
        auth_user_id: 0,
        auth_scopes: vec![],
        auth_is_superuser: false,
        flow_permissions: vec![],
        user_agent: String::new(),
    };

    let response = client.call(request, Duration::from_secs(2)).await.unwrap();

    // Deve retornar envelope de erro com código METHOD_NOT_FOUND
    assert_eq!(response.kind, MessageKind::Error as i32);
    assert!(response.error.is_some());
    let err = response.error.unwrap();
    assert_eq!(err.code, "METHOD_NOT_FOUND");

    server_handle.abort();
}

#[tokio::test]
async fn test_rpc_flow_timeout() {
    let addr_str = "tcp://127.0.0.1:28493";
    let endpoint = Endpoint::parse(addr_str).unwrap();

    let server = Server::new(endpoint.clone(), "flatbuffers").route("Slow", |_env| {
        Box::pin(async move {
            tokio::time::sleep(Duration::from_millis(400)).await;
            Envelope::default()
        })
    });

    let server_handle = tokio::spawn(async move {
        server.run().await.unwrap();
    });

    tokio::time::sleep(Duration::from_millis(200)).await;

    let codec = Box::new(FlatbuffersCodec);
    let client = MuxClient::conectar(endpoint, codec).await.unwrap();

    let request = Envelope {
        kind: MessageKind::Request as i32,
        method: "Slow".to_string(),
        ..Envelope::default()
    };

    // Chamada com timeout de 100ms (menor que o delay de 400ms do servidor)
    let call_res = client.call(request, Duration::from_millis(100)).await;

    assert!(call_res.is_err());
    assert!(matches!(call_res.err().unwrap(), TransportError::Timeout));

    server_handle.abort();
}

#[tokio::test]
async fn test_rpc_flow_auto_reconnect() {
    let addr_str = "tcp://127.0.0.1:28494";
    let endpoint = Endpoint::parse(addr_str).unwrap();
    let codec = Box::new(FlatbuffersCodec);

    // 1. Cria TcpListener direto de teste para simular o primeiro servidor
    let listener = tokio::net::TcpListener::bind("127.0.0.1:28494")
        .await
        .unwrap();

    // Spawna task para atender apenas 1 conexão e fechar ativamente
    let listener_handle = tokio::spawn(async move {
        let (mut stream, _) = listener.accept().await.unwrap();
        // Lê o request frame
        let frame = transport::framing::read_frame(&mut stream).await.unwrap();

        // Decodifica e monta a resposta
        let codec = FlatbuffersCodec;
        let env = transport::codec::Codec::decode(&codec, &frame.body).unwrap();
        let resp_env = Envelope {
            payload: b"oi".to_vec(),
            ..env
        };
        let resp_body = transport::codec::Codec::encode(&codec, &resp_env).to_vec();
        let resp_frame = transport::framing::Frame {
            flags: 0,
            corr_id: frame.corr_id,
            body: resp_body,
        };

        // Escreve a resposta
        transport::framing::write_frame(&mut stream, &resp_frame)
            .await
            .unwrap();
        // Dropa a conexão física ativamente do lado do servidor
        drop(stream);
    });

    // Conecta o cliente
    let client = MuxClient::conectar(endpoint.clone(), codec).await.unwrap();

    let request = Envelope {
        kind: MessageKind::Request as i32,
        method: "Echo".to_string(),
        payload: vec![],
        ..Envelope::default()
    };

    // Primeira chamada: deve retornar "oi"
    let resp1 = client
        .call(request.clone(), Duration::from_secs(2))
        .await
        .unwrap();
    assert_eq!(resp1.payload, b"oi");

    // Aguarda finalização da conexão direta
    let _ = listener_handle.await;
    tokio::time::sleep(Duration::from_millis(100)).await;

    // 2. Agora sobe o Server real de produção na mesma porta
    let server2 = Server::new(endpoint.clone(), "flatbuffers").route("Echo", |env| {
        Box::pin(async move {
            Envelope {
                payload: b"reconectado".to_vec(),
                ..env
            }
        })
    });
    let server_handle2 = tokio::spawn(async move {
        server2.run().await.unwrap();
    });

    tokio::time::sleep(Duration::from_millis(200)).await;

    // 3. Segunda chamada: o cliente detecta a conexão antiga fechada (EOF),
    // reconecta ao novo Server de produção e obtém sucesso.
    let resp2 = client
        .call(request, Duration::from_secs(5))
        .await
        .expect("Deveria ter reconectado automaticamente");
    assert_eq!(resp2.payload, b"reconectado");

    server_handle2.abort();
}
