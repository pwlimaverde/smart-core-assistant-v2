// transport/src/framing.rs  (comentários em pt-br)
// ┌────────┬──────────┬──────────────┬────────────────────────────┐
// │ len:u32│ flags:u8 │ corr_id:u128 │ envelope serializado (len)  │
// └────────┴──────────┴──────────────┴────────────────────────────┘
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub mod flags {
    pub const STREAM_ITEM: u8 = 0b0000_0001;
    pub const STREAM_END: u8 = 0b0000_0010;
    pub const IS_ERROR: u8 = 0b0000_0100;
    pub const COMPRESSED: u8 = 0b0000_1000; // futuro
    /// Keepalive: requisição de ping (corpo vazio); o servidor responde com PONG no mesmo corr_id.
    pub const PING: u8 = 0b0001_0000;
    /// Keepalive: resposta de pong ao PING, reutilizando o corr_id da requisição.
    pub const PONG: u8 = 0b0010_0000;
}

#[derive(Debug, Clone)]
pub struct Frame {
    pub flags: u8,
    pub corr_id: u128,
    pub body: Vec<u8>,
}

pub async fn write_frame<W: AsyncWriteExt + Unpin>(w: &mut W, f: &Frame) -> std::io::Result<()> {
    w.write_u32(f.body.len() as u32).await?; // prefixo de tamanho (resolve TCP stream)
    w.write_u8(f.flags).await?;
    w.write_u128(f.corr_id).await?; // correlaciona REQUEST↔REPLY / itens de STREAM
    w.write_all(&f.body).await?;
    w.flush().await
}

pub async fn read_frame<R: AsyncReadExt + Unpin>(r: &mut R) -> std::io::Result<Frame> {
    let len = r.read_u32().await? as usize;
    let flags = r.read_u8().await?;
    let corr_id = r.read_u128().await?;
    let mut body = vec![0u8; len];
    r.read_exact(&mut body).await?;
    Ok(Frame {
        flags,
        corr_id,
        body,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn frame_flags_contain_expected_binary_representations() {
        // Valida as flags declaradas
        assert_eq!(flags::STREAM_ITEM, 0b0000_0001);
        assert_eq!(flags::STREAM_END, 0b0000_0010);
        assert_eq!(flags::IS_ERROR, 0b0000_0100);
        assert_eq!(flags::COMPRESSED, 0b0000_1000);
        assert_eq!(flags::PING, 0b0001_0000);
        assert_eq!(flags::PONG, 0b0010_0000);
    }

    #[tokio::test]
    async fn writes_and_reads_frame_successfully() {
        // Arrange
        let original_frame = Frame {
            flags: flags::STREAM_ITEM | flags::IS_ERROR,
            corr_id: 12345678901234567890,
            body: vec![10, 20, 30, 40, 50],
        };
        let mut buffer = Vec::new();

        // Act - Escrever
        let mut cursor_write = Cursor::new(&mut buffer);
        let write_res = write_frame(&mut cursor_write, &original_frame).await;
        assert!(write_res.is_ok());

        // Act - Ler de volta
        let mut cursor_read = Cursor::new(&buffer);
        let read_res = read_frame(&mut cursor_read).await;
        assert!(read_res.is_ok());

        // Assert
        let decoded_frame = read_res.unwrap();
        assert_eq!(decoded_frame.flags, original_frame.flags);
        assert_eq!(decoded_frame.corr_id, original_frame.corr_id);
        assert_eq!(decoded_frame.body, original_frame.body);
    }

    #[tokio::test]
    async fn read_frame_fails_on_empty_input() {
        // Arrange
        let buffer = Vec::new();
        let mut cursor = Cursor::new(buffer);

        // Act
        let read_res = read_frame(&mut cursor).await;

        // Assert
        assert!(read_res.is_err());
        assert_eq!(
            read_res.err().unwrap().kind(),
            std::io::ErrorKind::UnexpectedEof
        );
    }

    #[tokio::test]
    async fn read_frame_fails_on_truncated_header() {
        // Arrange - Escreve apenas 2 bytes (len precisa de 4 bytes)
        let buffer = vec![0u8, 5u8];
        let mut cursor = Cursor::new(buffer);

        // Act
        let read_res = read_frame(&mut cursor).await;

        // Assert
        assert!(read_res.is_err());
        assert_eq!(
            read_res.err().unwrap().kind(),
            std::io::ErrorKind::UnexpectedEof
        );
    }

    #[tokio::test]
    async fn read_frame_fails_on_truncated_body() {
        // Arrange - Escreve header completo indicando 10 bytes de corpo, mas envia apenas 3
        let mut buffer = Vec::new();
        let mut cursor_setup = Cursor::new(&mut buffer);
        cursor_setup.write_u32(10).await.unwrap(); // len = 10
        cursor_setup.write_u8(flags::STREAM_ITEM).await.unwrap(); // flags
        cursor_setup.write_u128(99).await.unwrap(); // corr_id
        cursor_setup.write_all(&[1, 2, 3]).await.unwrap(); // body incompleto (3 bytes)

        let mut cursor = Cursor::new(buffer);

        // Act
        let read_res = read_frame(&mut cursor).await;

        // Assert
        assert!(read_res.is_err());
        assert_eq!(
            read_res.err().unwrap().kind(),
            std::io::ErrorKind::UnexpectedEof
        );
    }
}
