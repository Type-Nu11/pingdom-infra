const std = @import("std");

pub const GUARD_ALLOW: c_int = 0; // valid
pub const GUARD_INVALID_METHOD: c_int = 20;
pub const GUARD_URI_TOO_LONG: c_int = 21;
pub const GUARD_USER_AGENT_TOO_LONG: c_int = 22;
pub const GUARD_BODY_TOO_LARGE: c_int = 23;
pub const GUARD_INVALID_CHARACTER: c_int = 24;
pub const GUARD_NULL_BYTE: c_int = 25;
pub const GUARD_CRLF_INJECTION: c_int = 26;
pub const GUARD_PATH_TRAVERSAL: c_int = 27;
pub const GUARD_DOUBLE_ENCODING: c_int = 28;
pub const GUARD_CONTROL_CHARACTER: c_int = 29;

// about params
const MAX_METHOD_LEN: usize = 16;
const MAX_URI_LEN: usize = 4096;
const MAX_USER_AGENT_LEN: usize = 1024;
const MAX_BODY_LEN: usize = 10 * 1024 * 1024;

export fn inspect_web_request(
    method_ptr: [*]const u8,
    method_len: usize,
    uri_ptr: [*]const u8,
    uri_len: usize,
    user_agent_ptr: [*]const u8,
    user_agent_len: usize,
    body_len: usize
) c_int {
    if (method_len == 0 or method_len > MAX_METHOD_LEN) {
        return GUARD_INVALID_METHOD;
    }

    if (uri_len == 0 or uri_len > MAX_URI_LEN) {
        return GUARD_URI_TOO_LONG;
    }

    if (user_agent_len == 0 or user_agent_len > MAX_USER_AGENT_LEN) {
        return GUARD_USER_AGENT_TOO_LONG;
    }

    if (body_len == 0 or body_len > MAX_BODY_LEN) {
        return GUARD_BODY_TOO_LARGE;
    }

    const method = method_ptr[0..method_len];
    const uri = uri_ptr[0..uri_len];
    const user_agent = user_agent_ptr[0..user_agent_len];

    if (!is_allowed_method(method)) {
        return GUARD_INVALID_METHOD;
    }

    if (contains_null_byte(method) or 
        contains_null_byte(uri) or
        contains_null_byte(user_agent))
    {
        return GUARD_NULL_BYTE;
    }

    if (has_invalid_control_character(method) or
        has_invalid_control_character(uri)
        has_invalid_control_character(user_agent)) 
    {
        return GUARD_CONTROL_CHARACTER;
    }

    if (has_path_traversal(uri)) {
        return GUARD_PATH_TRAVERSAL;
    }

    if (has_double_encoding(uri)) {
        return GUARD_DOUBLE_ENCODING;
    }

    return GUARD_ALLOW;
}

fn is_allowed_method(method: []const u8) bool {
    const allowed = [_][]const u8{
        "GET",
        "POST",
        "PUT",
        "PATCH",
        "DELETE",
        "OPTIONS",
    };

    for (allowed) |candidate| {
        if (std.mem.eql(u8, method, candidate)) {
            return true;
        }
    }

    return false;
}

fn contains_null_byte(value: []const u8) bool {
    for (value) |byte| {
        if (byte==0x00) {
            return true;
        }
    }

    return false;
}

fn has_invalid_control_character(value: []const u8) bool {
    for (value) |byte| {
        if (byte < 0x20 or byte == 0x7f) {
            return true;
        }
    }

    return false;

}

fn has_path_traversal(uri: []const u8) bool {
    var i: usize = 0;

    while (i < uri.len) : (i += 1) {
        if (i + 2 < uri.len and
            uri[i] == '.' and
            uri[i + 1] == '.' and
            (uri[i + 2] == '/' or uri[i + 2] == '\\'))
        {
            return true;
        }

        if (i+2 < uri.len and uri[i] == "%") {

            const first = hex_value(uri[i+1]);
            const second = hex_value(uri[i+2]);

            if (first != null and second != null) {

                const decoded = (first.? << 4) | second.?;

                if (decoded == '/' or decoded == '\\') {
                    if (i>=2 and
                        uri[i-2] == '.' and
                        uri[i-1] == '.')
                    {
                        return true;
                    }
                }
            }
        }
    }

    return false;
}

