! Template body for a per-rank tracer-data writer (ADR 0003 §2). Writes
! an already-shaped real(real64) array as a savepoint variable named by
! the tracer, reusing the field data path (ensure_dims / ensure_variable
! / put_var) so the on-disk variable is byte-identical to a !$SER DATA
! field. `timelevel` is attached as an optional NF90_INT attribute only
! when `has_timelevel` is true. Instantiated per rank from m_preserf.F90
! via PRESERF_SUB (full subroutine name) and PRESERF_DIMS.
subroutine PRESERF_SUB(grpid, name, data, timelevel, has_timelevel)
   integer, intent(in) :: grpid
   character(len=*), intent(in) :: name
   real(real64), intent(in) PRESERF_DIMS :: data
   integer, intent(in) :: timelevel
   logical, intent(in) :: has_timelevel
   integer :: ncerr, varid
   integer, allocatable :: dimids(:)
   integer(int32) :: tl
   call ensure_dims(grpid, name, shape(data), dimids)
   call ensure_variable(grpid, name, NF90_DOUBLE, dimids, varid)
   ncerr = nf90_put_var(grpid, varid, data)
   call preserf_check_nf_with_msg(ncerr, 'put_var tracer '//trim(name))
   if (has_timelevel) then
      tl = int(timelevel, int32)
      ncerr = nf90_put_att(grpid, varid, 'timelevel', tl)
      call preserf_check_nf_with_msg(ncerr, 'put_att tracer timelevel '//trim(name))
   end if
end subroutine PRESERF_SUB
