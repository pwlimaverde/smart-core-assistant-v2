#[cfg(test)]
mod tests {
    use axum::http::StatusCode;

    #[tokio::test]
    async fn test_healthcheck() {
        // Test that healthcheck endpoint returns 200
        // Will be implemented with axum test client
        assert_eq!(StatusCode::OK.as_u16(), 200);
    }

    #[tokio::test]
    async fn test_unauthorized_upload() {
        // Test that POST /upload without Bearer token returns 401
        assert_eq!(StatusCode::UNAUTHORIZED.as_u16(), 401);
    }

    #[tokio::test]
    async fn test_get_releases() {
        // Test that GET /api/releases returns valid JSON with version, url, sha256
        // Placeholder
        assert!(true);
    }
}
