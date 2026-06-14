! Template body for an fs_write_kbuff overload (DATA_KBUFF, ADR 0003 §5).
! `data` is the horizontal slice at vertical level `k`. In write mode the
! helper buffers each slice and, on the last level (k == k_size), assembles
! and writes the full field of shape (slice_shape..., k_size) via the field
! write path, so the on-disk variable is byte-identical to a !$SER DATA
! write (storage_mapping.md §6). In read / read-perturb mode it loads the
! full stored field once and copies level `k` back into `data`. v1.0 covers
! real(real64) slices of rank 1-3 (full fields rank 2-4). Instantiated per
! slice rank from m_preserf.F90 via PRESERF_SUB (full subroutine name) and
! PRESERF_DIMS (the slice's dimension spec).
subroutine PRESERF_SUB(s, sp, fieldname, data, k, k_size, mode)
   type(t_serializer), intent(inout) :: s
   type(t_savepoint), intent(in) :: sp
   character(len=*), intent(in) :: fieldname
   real(real64), intent(inout) PRESERF_DIMS :: data
   integer, intent(in) :: k, k_size, mode
   integer :: idx, off, ss
   if (serialisation_enabled == 0) return
   call require_open(s, 'fs_write_kbuff')
   call require_savepoint(sp, 'fs_write_kbuff')
   call require_savepoint_owner(s, sp, 'fs_write_kbuff')
   if (mode == 0) then
      call kbuff_accumulate(s, sp, fieldname, reshape(data, [size(data)]), &
                            shape(data), k, k_size)
   else
      ! Read / read-perturb load from the REFERENCE serializer, matching the
      ! DATA read path; resolve_savepoint_grpid re-resolves the savepoint
      ! group under the reference (a no-op when it aliases the primary).
      ss = size(data)
      idx = kbuff_load(resolve_savepoint_grpid(ppser_serializer_ref, sp), &
                       fieldname, shape(data), ss, k, k_size)
      off = (k - 1)*ss
      data = reshape(ppser_kbuffers(idx)%buffer(off + 1:off + ss), shape(data))
      if (k == k_size) call kbuff_free(idx)
   end if
end subroutine PRESERF_SUB
