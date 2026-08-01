use std::ffi::c_void;

/// Supplies the libatomic query that vendored OpenSSL expects on 32-bit x86.
///
/// Reporting eight-byte atomics as not lock-free makes OpenSSL use its locked
/// fallback, which is safe on i686 CPUs with or without `cmpxchg8b` support.
#[unsafe(export_name = "__atomic_is_lock_free")]
pub(crate) extern "C" fn atomic_is_lock_free(size: usize, _pointer: *const c_void) -> bool {
    matches!(size, 1 | 2 | 4)
}
