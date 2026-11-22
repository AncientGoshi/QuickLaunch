mod targets;

use std::ffi::{CString, c_char};

fn error(message: String) -> *mut c_char {
    CString::new(message.replace('\0', "�"))
        .expect("NUL bytes removed")
        .into_raw()
}

/// # Safety
/// For nonzero length, `data` must point to `len` readable bytes for this call.
/// The returned error, if non-null, must be released using `ql_free_error`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ql_targets(
    data: *const u8,
    len: usize,
    launch: bool,
    count: &mut usize,
) -> *mut c_char {
    let bytes = if len == 0 {
        &[]
    } else {
        // SAFETY: The caller guarantees a readable buffer of this length.
        unsafe { std::slice::from_raw_parts(data, len) }
    };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return error("Targets must be valid UTF-8.".to_owned());
    };
    let result = if launch {
        targets::launch(text)
    } else {
        targets::validate(text).map(|n| *count = n)
    };
    match result {
        Ok(()) => std::ptr::null_mut(),
        Err(message) => error(message),
    }
}

/// # Safety
/// `message` must be null or a live pointer returned by `ql_targets` that
/// has not already been released.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn ql_free_error(message: *mut c_char) {
    if !message.is_null() {
        // SAFETY: `message` was allocated by CString::into_raw in this library.
        drop(unsafe { CString::from_raw(message) });
    }
}
