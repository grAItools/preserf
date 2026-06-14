! Template body for a per-rank tracer write/read at the current savepoint
! (ADR 0003 §2). In write mode it emits the tracer's array as a savepoint
! variable named by the tracer (byte-identical to a !$SER DATA field) with
! the integer timelevel as an optional attribute; in read mode it reads the
! stored variable back into the host array the registry points at. The
! data moves through the rank-specific pointer component PRESERF_PTR.
! Instantiated per rank from m_preserf.F90 via PRESERF_SUB and PRESERF_PTR.
subroutine PRESERF_SUB(grpid, entry, mode, timelevel, has_timelevel)
   integer, intent(in) :: grpid
   type(t_tracer_entry), intent(in) :: entry
   integer, intent(in) :: mode, timelevel
   logical, intent(in) :: has_timelevel
   integer :: ncerr, varid
   integer, allocatable :: dimids(:)
   integer(int32) :: tl

   if (mode == 0) then
      call ensure_dims(grpid, trim(entry%name), shape(entry%PRESERF_PTR), dimids)
      call ensure_variable(grpid, trim(entry%name), NF90_DOUBLE, dimids, varid)
      ncerr = nf90_put_var(grpid, varid, entry%PRESERF_PTR)
      call preserf_check_nf_with_msg(ncerr, 'put_var tracer '//trim(entry%name))
      if (has_timelevel) then
         call require_fits_int32(timelevel, 'timelevel')
         tl = int(timelevel, int32)
         ncerr = nf90_put_att(grpid, varid, 'timelevel', tl)
         call preserf_check_nf_with_msg(ncerr, &
                                        'put_att tracer timelevel '//trim(entry%name))
      else
         ! "Last write wins": if a prior write of this tracer at this
         ! savepoint set a timelevel and this (final) write omits it, the
         ! attribute must not linger on the reused variable. Removing an
         ! absent attribute is a no-op (NF90_ENOTATT).
         ncerr = nf90_del_att(grpid, varid, 'timelevel')
         if (ncerr /= NF90_NOERR .and. ncerr /= NF90_ENOTATT) &
            call preserf_check_nf_with_msg(ncerr, &
                                           'del_att tracer timelevel '//trim(entry%name))
      end if
   else
      ncerr = nf90_inq_varid(grpid, trim(entry%name), varid)
      if (ncerr == NF90_ENOTVAR) then
         write (*, '(a,a,a)') &
            'preserf: read-mode tracer "', trim(entry%name), &
            '" is not present at this savepoint'
         error stop 1
      end if
      call preserf_check_nf_with_msg(ncerr, 'inq_varid tracer '//trim(entry%name))
      ncerr = nf90_get_var(grpid, varid, entry%PRESERF_PTR)
      call preserf_check_nf_with_msg(ncerr, 'get_var tracer '//trim(entry%name))
   end if
end subroutine PRESERF_SUB
