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

pub const TIME_SKEWL: i64 = 30;

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
    }))

    match result {
        Ok(Ok(code)) => code,
        Ok(Err(code)) => code,
        Err(_) => JWT_INVALIDE_INPUT
    }
}

unsafe fn read_bytes<'a>(
    ptr *const u8,
    len usize
) -> Result<&'a [u8], i32> {
    if len == 0 || ptr.is_null() {
        return Err(JWT_INVALID_INPUT)
    }

    Ok(slice::from_raw_parts(ptr, len))
}

