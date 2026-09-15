use base64::{
    engine::general_purpose::URL_SAFE_NO_PAD,
    Engine
};

use hmac::{Hmac, Mac};
use serde_json::Value;
use sha2::Sha256;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;
use std::time::{SystemTime, UNIX_EPOCH};

type HmacSha256 = Hmac<Sha256>;

pub const JWT_VALID: i32 = 0;
pub const JWT_INVALID_INPUT: i32 = 10;
pub const JWT_INVALID_FORMAT: i32 = 11;
pub const JWT_INVALID_ALGORITHM: i32 = 12;
pub const JWT_INVALID_SIGNATURE: i32 = 13;
pub const JWT_EXPIRED: i32 = 14;
pub const JWT_NOT_YET_VALID: i32 = 15;

pub const CLOCK_SKEW: i64 = 30;

#[no_mangle]
pub unsafe extern "C" fn verify_jwt(
    token: *const u8,
    token_len: usize,
    secret: *const u8,
    secret_len: usize
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<i32, i32> {
        let token = read_bytes(token, token_len)?;
        let secret = read_bytes(secret, secret_len)?;

        Ok(validate_jwt(token, secret))
    }));

    match result {
        Ok(Ok(code)) => code,
        Ok(Err(code)) => code,
        Err(_) => JWT_INVALID_INPUT,
    }
}

unsafe fn read_bytes<'a>(
    ptr: *const u8,
    len: usize
) -> Result<&'a [u8], i32> {
    if len == 0 || ptr.is_null() {
        return Err(JWT_INVALID_INPUT);
    }

    Ok(slice::from_raw_parts(ptr, len))
}

fn validate_jwt(token: &[u8], secret: &[u8]) -> i32 {
    if secret.is_empty() {
        return JWT_INVALID_INPUT;
    }

    let token = match std::str::from_utf8(token) {
        Ok(value) => value,
        Err(_) => return JWT_INVALID_FORMAT,
    };

    // split
    let mut parts = token.split('.');

    // formatting
    let header_encoded = match parts.next(){
        Some(value) => value,
        None => return JWT_INVALID_FORMAT,
    };

    let payload_encoded = match parts.next() {
        Some(value) => value,
        None => return JWT_INVALID_FORMAT,
    };

    let signature_encoded = match parts.next() {
        Some(value) => value,
        None => return JWT_INVALID_FORMAT,
    };

    if parts.next().is_some() {
        return JWT_INVALID_FORMAT
    }

    // decode
    let header_bytes = match URL_SAFE_NO_PAD.decode(header_encoded) {
        Ok(value) => value,
        Err(_) => return JWT_INVALID_FORMAT,
    };

    let payload_bytes = match URL_SAFE_NO_PAD.decode(payload_encoded) {
        Ok(value) => value,
        Err(_) => return JWT_INVALID_FORMAT,
    };

    let provided_signature = match URL_SAFE_NO_PAD.decode(signature_encoded) {
        Ok(value) => value,
        Err(_) => return JWT_INVALID_SIGNATURE,
    };

    let header: Value = match serde_json::from_slice(&header_bytes) {
        Ok(value) => value,
        Err(_) => return JWT_INVALID_FORMAT,
    };

    let payload: Value = match serde_json::from_slice(&payload_bytes) {
        Ok(value) => value,
        Err(_) => return JWT_INVALID_FORMAT,
    };

    // header's algorithm field check. "none" is Algorithm COnfusion Attack
    if header.get("alg").and_then(Value::as_str) != Some("HS256") {
        return JWT_INVALID_ALGORITHM;
    }

    let signing_input = format!("{}.{}", header_encoded, payload_encoded);

    let mut mac = match HmacSha256::new_from_slice(secret) {
        Ok(value) => value,
        Err(_) => return JWT_INVALID_INPUT,
    };

    mac.update(signing_input.as_bytes());

    if mac.verify_slice(&provided_signature).is_err() {
        return JWT_INVALID_SIGNATURE;
    }

    let now = match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(value) => value.as_secs() as i64,
        Err(_) => return JWT_INVALID_INPUT,
    };

    if let Some(exp) = payload.get("exp").and_then(Value::as_i64) {
        if now > exp + CLOCK_SKEW {
            return JWT_EXPIRED;
        }
    }

    if let Some(iat) = payload.get("iat").and_then(Value::as_i64) {
        if iat > now + CLOCK_SKEW {
            return JWT_NOT_YET_VALID;
        }
    }

    JWT_VALID
}
