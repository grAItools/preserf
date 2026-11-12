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
   integer :: ncerr, varid, read_grpid, data_grpid
   integer(int8), allocatable PRESERF_DIMS :: buf
   integer(int32), allocatable :: reg_dims(:)

   if (serialisation_enabled == 0) return
   call require_open(s, 'fs_read_field')
   call require_savepoint(sp, 'fs_read_field')
   call validate_field_shape(s, fieldname, shape(data), TID_BOOLEAN, 'read', &
                             registered_dims_out=reg_dims)
   read_grpid = resolve_savepoint_grpid(s, sp)
   ! Resolve a dedup `/_dict` reference if present (ADR 0014); a default
   ! store returns the savepoint variable unchanged.
   call resolve_read_variable(s, read_grpid, fieldname, data_grpid, varid)
   call require_variable_xtype(s, data_grpid, varid, fieldname, NF90_BYTE, &
                               known_dims_c=reg_dims)
   PRESERF_BUFALLOC
   ncerr = nf90_get_var(data_grpid, varid, buf)
   call preserf_check_nf_with_msg(ncerr, 'get_var '//trim(fieldname))
   data = (buf /= 0_int8)
end subroutine PRESERF_SUB
