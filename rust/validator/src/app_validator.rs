use std::panic::{catch_unwind, AssertUnwindSafe};
use std::slice;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

pub const VALID: i32 = 0;
pub const INVALID_TIMESTAMP: i32 = 1;
pub const INVALID_APP_VERSION: i32 = 2;
pub const INVALID_DEVICE_ID: i32 = 3;
pub const INVALID_INPUT: i32 = 4;
pub const CLOCK_ERROR: i32 = 5;
pub const INVALID_VERSION_POLICY: i32 = 6;

// This checks timestamp freshness only. Without a MAC or server-side nonce,
// it does not prevent replay of a request inside this time window.
const TIMESTAMP_TTL_SECONDS: u64 = 60;

#[no_mangle]
pub unsafe extern "C" fn validate_app_headers(
    timestamp: *const u8,
    timestamp_len: usize,
    app_version: *const u8,
    app_version_len: usize,
    minimum_app_version: *const u8,
    minimum_app_version_len: usize,
    device_id: *const u8,
    device_id_len: usize,
) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<i32, i32> {
        let timestamp = read_bytes(timestamp, timestamp_len)?;
        let app_version = read_bytes(app_version, app_version_len)?;
        let minimum_app_version = read_bytes(minimum_app_version, minimum_app_version_len)?;
        let device_id = read_bytes(device_id, device_id_len)?;
        Ok(validate(
            timestamp,
            app_version,
            minimum_app_version,
            device_id,
        ))
    }));

    match result {
        Ok(Ok(code)) => code,
        Ok(Err(code)) => code,
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

fn validate(
    timestamp: &[u8],
    app_version: &[u8],
    minimum_app_version: &[u8],
    device_id: &[u8],
) -> i32 {
    let timestamp_text = match std::str::from_utf8(timestamp) {
        Ok(value) if !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit()) => value,
        _ => return INVALID_TIMESTAMP,
    };
    let timestamp = match timestamp_text.parse::<i64>() {
        Ok(value) => value,
        Err(_) => return INVALID_TIMESTAMP,
    };

    let now = match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(value) => value.as_secs(),
        Err(_) => return CLOCK_ERROR,
    };

    if timestamp < 0 || timestamp.abs_diff(now as i64) > TIMESTAMP_TTL_SECONDS {
        return INVALID_TIMESTAMP;
    }

    let app_version = match std::str::from_utf8(app_version) {
        Ok(value) => value,
        Err(_) => return INVALID_APP_VERSION,
    };
    let minimum_app_version = match std::str::from_utf8(minimum_app_version) {
        Ok(value) => value,
        Err(_) => return INVALID_APP_VERSION,
    };
    if !is_numeric_semver(app_version) {
        return INVALID_APP_VERSION;
    }
    if !is_numeric_semver(minimum_app_version) {
        return INVALID_VERSION_POLICY;
    }
    match version_meets_minimum(app_version, minimum_app_version) {
        Some(true) => {}
        Some(false) => return INVALID_APP_VERSION,
        None => return INVALID_VERSION_POLICY,
    }

    let device_id = match std::str::from_utf8(device_id) {
        Ok(value) => value,
        Err(_) => return INVALID_DEVICE_ID,
    };
    if device_id.len() != 36 || Uuid::parse_str(device_id).is_err() {
        return INVALID_DEVICE_ID;
    }

    VALID
}

fn is_numeric_semver(value: &str) -> bool {
    let mut parts = value.split('.');
    let Some(major) = parts.next() else {
        return false;
    };
    let Some(minor) = parts.next() else {
        return false;
    };
    let Some(patch) = parts.next() else {
        return false;
    };

    parts.next().is_none()
        && [major, minor, patch].iter().all(|part| {
            !part.is_empty()
                && part.bytes().all(|byte| byte.is_ascii_digit())
                && (part.len() == 1 || !part.starts_with('0'))
        })
}

fn version_meets_minimum(current: &str, minimum: &str) -> Option<bool> {
    let parse = |value: &str| -> Option<[u64; 3]> {
        let mut parts = value.split('.');
        Some([
            parts.next()?.parse().ok()?,
            parts.next()?.parse().ok()?,
            parts.next()?.parse().ok()?,
        ])
    };

    Some(parse(current)? >= parse(minimum)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn now_seconds() -> i64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64
    }

    const VERSION: &[u8] = b"1.2.3";
    const DEVICE_ID: &[u8] = b"550e8400-e29b-41d4-a716-446655440000";

    #[test]
    fn accepts_fresh_timestamp_and_valid_metadata() {
        assert_eq!(
            validate(
                now_seconds().to_string().as_bytes(),
                VERSION,
                b"0.0.0",
                DEVICE_ID
            ),
            VALID
        );
    }

    #[test]
    fn rejects_missing_malformed_and_stale_timestamps() {
        assert_eq!(
            validate(b"", VERSION, b"0.0.0", DEVICE_ID),
            INVALID_TIMESTAMP
        );
        assert_eq!(
            validate(b"not-a-timestamp", VERSION, b"0.0.0", DEVICE_ID),
            INVALID_TIMESTAMP
        );
        assert_eq!(
            validate(
                (now_seconds() - 61).to_string().as_bytes(),
                VERSION,
                b"0.0.0",
                DEVICE_ID
            ),
            INVALID_TIMESTAMP
        );
    }

    #[test]
    fn rejects_invalid_app_versions_and_device_ids() {
        let now = now_seconds().to_string();
        assert_eq!(
            validate(now.as_bytes(), b"1.2", b"0.0.0", DEVICE_ID),
            INVALID_APP_VERSION
        );
        assert_eq!(
            validate(now.as_bytes(), b"1.x.3", b"0.0.0", DEVICE_ID),
            INVALID_APP_VERSION
        );
        assert_eq!(
            validate(now.as_bytes(), VERSION, b"0.0.0", b"not-a-uuid"),
            INVALID_DEVICE_ID
        );
    }

    #[test]
    fn rejects_versions_below_configured_minimum() {
        let now = now_seconds().to_string();
        assert_eq!(
            validate(now.as_bytes(), b"1.2.2", b"1.2.3", DEVICE_ID),
            INVALID_APP_VERSION
        );
        assert_eq!(
            validate(now.as_bytes(), b"1.2.3", b"1.2.3", DEVICE_ID),
            VALID
        );
    }

    #[test]
    fn rejects_invalid_minimum_version_policy_as_configuration_error() {
        let now = now_seconds().to_string();
        assert_eq!(
            validate(now.as_bytes(), VERSION, b"not-a-version", DEVICE_ID),
            INVALID_VERSION_POLICY
        );
    }
}
