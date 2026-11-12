! Template body for a logical fs_write_field overload. Logical fields
! land on disk as NF90_BYTE with 0/1 encoding (storage_mapping.md §1), so
! the value is converted to an int8 buffer before nf90_put_var. The
! buffer auto-allocates from the merge() result's shape, covering rank 0
! (scalar) through rank 4. Instantiated via PRESERF_SUB / PRESERF_DIMS.
subroutine PRESERF_SUB(s, sp, fieldname, data)
   type(t_serializer), intent(inout) :: s
   type(t_savepoint), intent(in) :: sp
   character(len=*), intent(in) :: fieldname
   logical, intent(in) PRESERF_DIMS :: data
   integer :: ncerr, varid
   integer, allocatable :: dimids(:)
   integer(int8), allocatable PRESERF_DIMS :: buf
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
   call validate_field_shape(s, fieldname, shape(data), TID_BOOLEAN, 'write')
   ! The write entry points on a read-only serializer abort with the same
   ! friendly lifecycle message the REGISTER sibling's guard produces,
   ! rather than a raw netCDF permission error from the first define/put
   ! on the read-only handle. Placed after validate_field_shape so the
   ! unregistered-field abort (which the read-mode write scenarios pin)
   ! keeps its message, and before the buffer conversion / put so a
   ! registered logical field on a read-only handle never reaches netCDF.
   if (.not. s%writable) then
      write (error_unit, '(a,a,a)') &
         'preserf: DATA of field "', trim(fieldname), &
         '" in write mode but the serializer was opened read-only'
      error stop 1
   end if
   buf = merge(1_int8, 0_int8, data)
   if (ppser_dedup_enabled) then
      ! Dedup path (ADR 0014): checksum the on-disk 0/1 byte image (`buf`),
      ! so two logical fields that encode identically collapse to one
      ! `/_dict` entry, and reference it from this savepoint. See the
      ! numeric template for the shared shape of this branch.
      raw = transfer(buf, raw)
      cksum = ppser_hash_bytes(raw)
      nbytes = size(raw, kind=int64)
      call ppser_dict_find_or_add(trim(fieldname), cksum, nbytes, &
                                  entry_name, is_new)
      call ensure_dict_group(s, dict_grpid)
      if (is_new) then
         call ensure_dims(dict_grpid, entry_name, shape(data), dimids)
         call ensure_variable(dict_grpid, entry_name, NF90_BYTE, dimids, varid)
         ncerr = nf90_put_var(dict_grpid, varid, buf)
         call preserf_check_nf_with_msg(ncerr, 'put_var '//entry_name)
      end if
      call write_dict_reference(sp%grpid, fieldname, entry_name)
   else
      call ensure_dims(sp%grpid, fieldname, shape(data), dimids)
      call ensure_variable(sp%grpid, fieldname, NF90_BYTE, dimids, varid)
      ncerr = nf90_put_var(sp%grpid, varid, buf)
      call preserf_check_nf_with_msg(ncerr, 'put_var '//trim(fieldname))
   end if
end subroutine PRESERF_SUB
