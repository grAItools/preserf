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

   if (serialisation_enabled == 0) return
   call require_open(s, 'fs_write_field')
   call require_savepoint(sp, 'fs_write_field')
   call require_savepoint_owner(s, sp, 'fs_write_field')
   call validate_field_shape(s, fieldname, shape(data), TID_BOOLEAN, 'write')
   call ensure_dims(sp%grpid, fieldname, shape(data), dimids)
   call ensure_variable(sp%grpid, fieldname, NF90_BYTE, dimids, varid)
   buf = merge(1_int8, 0_int8, data)
   ncerr = nf90_put_var(sp%grpid, varid, buf)
   call preserf_check_nf_with_msg(ncerr, 'put_var '//trim(fieldname))
end subroutine PRESERF_SUB
