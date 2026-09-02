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

unsafe fn read_bytes<'a>(ptr: *const u8, len: usize) -> Result<&'a [u8], i32> {
    if len == 0 {
        return Ok(&[]);
    }

    if ptr.is_null() {
        return Err(INVALID_INPUT);
    }

    Ok(slice::from_raw_parts(ptr, len))
}

// validate headers
fn validate(
    method: &[u8],
    uri: &[u8],
    timestamp: &[u8],
    signature: &[u8],
    app_version: &[u8],
    device_id: &[u8],
    body: &[u8],
    secret: &[u8],
) -> i32 {
    if secret.is_empty() {
        return INVALID_INPUT;
    }

    let timestamp = match std::str::from_utf8(timestamp) 
        .ok()
        .and_then(|val| val.trim().parse::<i64>().ok())
    {
        Some(val) => val,
        None => return INVALID_TIMESTAMP,
    };

    let now = match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(value) => value.as_secs() as i64,
        Err(_) => return CLOCK_ERROR,
    };

    if (now - timestamp).abs() > TIMESTAMP_TTL {
        return INVALID_TIMESTAMP;
    }

    let app_version = match std::str::from_utf8(app_version) {
        Ok(value) => value,
        Err(_) => return INVALID_APP_VERSION,
    };

    if !is_semver(app_version) {
        return INVALID_APP_VERSION;
    }

    let device_id = match std::str::from_utf8(device_id) {
        Ok(value) => value,
        Err(_) => return INVALID_DEVICE_ID,
    };

    if Uuid::parse_str(device_id).is_err() {
        return INVALID_DEVICE_ID;
    }

    let signature = match std::str::from_utf8(signature) {
        Ok(value) => value.trim(),
        Err(_) => return INVALID_SIGNATURE,
    };

    let provided_signature = match STANDARD.decode(signature) {
        Ok(value) => value,
        Err(_) => return INVALID_SIGNATURE,
    };

    let mut mac = match HmacSha256::new_from_slice(secret) {
        Ok(value) => value,
        Err(_) => return INVALID_INPUT,
    };

    mac.update(method);
    mac.update(b"|");
    mac.update(uri);
    mac.update(b"|");
    mac.update(timestamp.to_string().as_bytes());
    mac.update(b"|");
    mac.update(app_version.as_bytes());
    mac.update(b"|");
    mac.update(device_id.as_bytes());
    mac.update(b"|");
    mac.update(body);

    if mac.verify_slice(&provided_signature).is_err() {
        return INVALID_SIGNATURE;
    }

    VALID
}

fn is_semver(value: &str) -> bool {
    let parts: Vec<&str> = value.split('.').collect();

    parts.len() == 3
        && parts
            .iter()
            .all(|part| !part.is_empty() && part.chars().all(|c| c.is_ascii_digit()))
}