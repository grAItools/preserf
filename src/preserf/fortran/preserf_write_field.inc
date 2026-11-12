! Template body for a numeric fs_write_field overload (DATA directive,
! write side). Instantiated per (dtype, rank) from m_preserf.F90 via the
! macros PRESERF_SUB (full subroutine name), PRESERF_DTYPE (declared
! type), PRESERF_DIMS (dimension attribute, empty for rank 0),
! PRESERF_NCTYPE (on-disk netCDF type) and PRESERF_TID (Serialbox
! TypeID). See dev/adr/0004-fortran-cpp-templates.md. Logical fields use
! preserf_write_field_logical.inc instead (they need a 0/1 byte buffer).
subroutine PRESERF_SUB(s, sp, fieldname, data)
   type(t_serializer), intent(inout) :: s
   type(t_savepoint), intent(in) :: sp
   character(len=*), intent(in) :: fieldname
   PRESERF_DTYPE, intent(in) PRESERF_DIMS :: data
   integer :: ncerr, varid
   integer, allocatable :: dimids(:)
   ! Cross-savepoint dedup state (ADR 0014); unused when dedup is off.
   integer :: dict_grpid
   integer(int8), allocatable :: raw(:)
   integer(int64) :: cksum, nbytes
   character(len=:), allocatable :: entry_name
   logical :: is_new

   if (serialisation_enabled == 0) return
   call require_open(s, 'fs_write_field')
   call require_savepoint(sp, 'fs_write_field')
   call require_savepoint_owner(s, sp, 'fs_write_field')
   ! shape(data) is a zero-length vector for a rank-0 (scalar) field, so
   ! the same body covers 0-D through 4-D: validate, create the
   ! dims/variable, and write.
   call validate_field_shape(s, fieldname, shape(data), PRESERF_TID, 'write')
   ! The write entry points on a read-only serializer abort with the same
   ! friendly lifecycle message the REGISTER sibling's guard produces,
   ! rather than a raw netCDF permission error from the first define/put
   ! on the read-only handle. Placed after validate_field_shape so the
   ! unregistered-field abort (which the read-mode write scenarios pin)
   ! keeps its message, and before the first define so a registered
   ! field on a read-only handle never reaches netCDF.
   if (.not. s%writable) then
      write (error_unit, '(a,a,a)') &
         'preserf: DATA of field "', trim(fieldname), &
         '" in write mode but the serializer was opened read-only'
      error stop 1
   end if
   if (ppser_dedup_enabled) then
      ! Dedup path (ADR 0014): checksum the raw payload bytes, resolve (or
      ! create) the `/_dict` entry for an identical payload, write the entry
      ! dataset only on a miss, and point this savepoint at it via a scalar
      ! reference carrier. `transfer(data, raw)` yields the payload's byte
      ! image for any rank (shape(data) is zero-length for a scalar field).
      raw = transfer(data, raw)
      cksum = ppser_hash_bytes(raw)
      nbytes = size(raw, kind=int64)
      call ppser_dict_find_or_add(trim(fieldname), cksum, nbytes, &
                                  entry_name, is_new)
      call ensure_dict_group(s, dict_grpid)
      if (is_new) then
         call ensure_dims(dict_grpid, entry_name, shape(data), dimids)
         call ensure_variable(dict_grpid, entry_name, PRESERF_NCTYPE, dimids, varid)
         ncerr = nf90_put_var(dict_grpid, varid, data)
         call preserf_check_nf_with_msg(ncerr, 'put_var '//entry_name)
      end if
      call write_dict_reference(sp%grpid, fieldname, entry_name)
   else
      call ensure_dims(sp%grpid, fieldname, shape(data), dimids)
      call ensure_variable(sp%grpid, fieldname, PRESERF_NCTYPE, dimids, varid)
      ncerr = nf90_put_var(sp%grpid, varid, data)
      call preserf_check_nf_with_msg(ncerr, 'put_var '//trim(fieldname))
   end if
end subroutine PRESERF_SUB
