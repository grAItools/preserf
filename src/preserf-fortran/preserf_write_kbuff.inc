! Template body for an fs_write_kbuff overload (DATA_KBUFF, ADR 0003 §5).
! `data` is the horizontal slice at vertical level `k`; the helper buffers
! each slice and, on the last level (k == k_size), assembles and writes the
! full field of shape (slice_shape..., k_size) via the field write path, so
! the on-disk variable is byte-identical to a !$SER DATA write
! (storage_mapping.md §6). v1.0 covers real(real64) slices of rank 1-3
! (full fields rank 2-4) and write mode only; read mode is a no-op (the
! full field is recoverable via fs_read_field). Instantiated per slice
! rank from m_preserf.F90 via PRESERF_SUB (full subroutine name) and
! PRESERF_DIMS (the slice's dimension spec).
subroutine PRESERF_SUB(s, sp, fieldname, data, k, k_size, mode)
   type(t_serializer), intent(inout) :: s
   type(t_savepoint), intent(in) :: sp
   character(len=*), intent(in) :: fieldname
   real(real64), intent(in) PRESERF_DIMS :: data
   integer, intent(in) :: k, k_size, mode
   if (serialisation_enabled == 0) return
   ! Read / read-perturb: k-buffer read-back into per-k slices is deferred
   ! for v1.0 (the assembled field is recoverable via fs_read_field).
   if (mode /= 0) return
   call require_open(s, 'fs_write_kbuff')
   call require_savepoint(sp, 'fs_write_kbuff')
   call require_savepoint_owner(s, sp, 'fs_write_kbuff')
   call kbuff_accumulate(s, sp, fieldname, reshape(data, [size(data)]), &
                         shape(data), k, k_size)
end subroutine PRESERF_SUB
