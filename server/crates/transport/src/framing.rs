// transport/src/framing.rs  (comentários em pt-br)
// ┌────────┬──────────┬──────────────┬────────────────────────────┐
// │ len:u32│ flags:u8 │ corr_id:u128 │ envelope serializado (len)  │
// └────────┴──────────┴──────────────┴────────────────────────────┘
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub mod flags {
    pub const STREAM_ITEM: u8 = 0b0000_0001;
    pub const STREAM_END:  u8 = 0b0000_0010;
    pub const IS_ERROR:    u8 = 0b0000_0100;
    pub const COMPRESSED:  u8 = 0b0000_1000; // futuro
}

#[derive(Debug, Clone)]
pub struct Frame {
    pub flags: u8,
    pub corr_id: u128,
    pub body: Vec<u8>,
}

pub async fn write_frame<W: AsyncWriteExt + Unpin>(w: &mut W, f: &Frame) -> std::io::Result<()> {
    w.write_u32(f.body.len() as u32).await?;   // prefixo de tamanho (resolve TCP stream)
    w.write_u8(f.flags).await?;
    w.write_u128(f.corr_id).await?;            // correlaciona REQUEST↔REPLY / itens de STREAM
    w.write_all(&f.body).await?;
    w.flush().await
}

pub async fn read_frame<R: AsyncReadExt + Unpin>(r: &mut R) -> std::io::Result<Frame> {
    let len = r.read_u32().await? as usize;
    let flags = r.read_u8().await?;
    let corr_id = r.read_u128().await?;
    let mut body = vec![0u8; len];
    r.read_exact(&mut body).await?;
    Ok(Frame { flags, corr_id, body })
}
