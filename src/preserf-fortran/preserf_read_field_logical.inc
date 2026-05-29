! Template body for a logical fs_read_field overload. Reads the on-disk
! NF90_BYTE 0/1 encoding into an int8 buffer, then maps non-zero -> .true.
! PRESERF_BUFALLOC allocates the buffer to the caller's shape without
! touching `data` (which is intent(inout) and may be undefined on entry).
! Instantiated via PRESERF_SUB / PRESERF_DIMS / PRESERF_BUFALLOC.
subroutine PRESERF_SUB(s, sp, fieldname, data)
   type(t_serializer), intent(in) :: s
   type(t_savepoint), intent(in) :: sp
   character(len=*), intent(in) :: fieldname
   logical, intent(inout) PRESERF_DIMS :: data
   integer :: ncerr, varid, read_grpid
   integer(int8), allocatable PRESERF_DIMS :: buf
   integer(int32), allocatable :: reg_dims(:)

   if (serialisation_enabled == 0) return
   call require_open(s, 'fs_read_field')
   call require_savepoint(sp, 'fs_read_field')
   call validate_field_shape(s, fieldname, shape(data), TID_BOOLEAN, 'read', &
                             registered_dims_out=reg_dims)
   read_grpid = resolve_savepoint_grpid(s, sp)
   ncerr = nf90_inq_varid(read_grpid, trim(fieldname), varid)
   call preserf_check_nf_with_msg(ncerr, 'inq_varid '//trim(fieldname))
   call require_variable_xtype(s, read_grpid, varid, fieldname, NF90_BYTE, &
                               known_dims_c=reg_dims)
   PRESERF_BUFALLOC
   ncerr = nf90_get_var(read_grpid, varid, buf)
   call preserf_check_nf_with_msg(ncerr, 'get_var '//trim(fieldname))
   data = (buf /= 0_int8)
end subroutine PRESERF_SUB
