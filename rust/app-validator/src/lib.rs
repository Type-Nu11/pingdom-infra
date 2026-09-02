use base64::{engine::general_purpose::STANDARD, Engine};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

type HmacSha256 = Hmac<Sha256>;

// private const SECRET_KEY: &[u8] = b"NarshaApp
pub const VALID: i32 = 0;
pub const INVALID_TIMESTAMP: i32 = 1;
pub const INVALID_SIGNATURE: i32 = 2;
pub const INVALID_APP_VERSION: i32 = 3;
pub const INVALID_DEVICE_ID: i32 = 4;
pub const INVALID_INPUT: i32 = 5;
pub const CLOCK_ERROR: i32 = 6;

const TIME_STAMP: i64 = 60;

#[no_mangle]
pub unsafe extern "C" fn validate_app_request(
    method: *const u8,
    method_len: usize,

    uri: *const u8,
    uri_len: usize,

    timestamp: *const u8,
    timestamp_len: usize,

    signature: *const u8,
    signature_len: usize,

    app_version: *const u8,
    app_version_len: usize,

    device_id: *const u8,
    device_id_len: usize,

    body: *const u8,
    body_len: usize,

    secret: *const u8,
    secret_len: usize,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let method = read_bytes(method, method_len)?;
        let uri = read_bytes(uri, uri_len)?;
        let timestamp = read_bytes(timestamp, timestamp_len)?;
        let signature = read_bytes(signature, signature_len)?;
        let app_version = read_bytes(app_version, app_version_len)?;
        let device_id = read_bytes(device_id, device_id_len)?;
        let body = read_bytes(body, body_len)?;
        let secret = read_bytes(secret, secret_len)?;

        validate(
            method, 
            uri,
            timestamp,
            signature,
            app_version,
            device_id,
            body,
            secret
        )
    }));

    match result {
        Ok(code) => code,
        Err(_) => INVALID_INPUT,
    }
}

