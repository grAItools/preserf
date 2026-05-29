! Template body for a numeric fs_read_field overload (DATA directive,
! read side). Instantiated per (dtype, rank) from m_preserf.F90 via the
! same macros as preserf_write_field.inc. See
! docs/adr/0004-fortran-cpp-templates.md. Logical fields use
! preserf_read_field_logical.inc instead.
subroutine PRESERF_SUB(s, sp, fieldname, data)
   type(t_serializer), intent(in) :: s
   type(t_savepoint), intent(in) :: sp
   character(len=*), intent(in) :: fieldname
   PRESERF_DTYPE, intent(inout) PRESERF_DIMS :: data
   integer :: ncerr, varid, read_grpid
   integer(int32), allocatable :: reg_dims(:)

   if (serialisation_enabled == 0) return
   call require_open(s, 'fs_read_field')
   call require_savepoint(sp, 'fs_read_field')
   call validate_field_shape(s, fieldname, shape(data), PRESERF_TID, 'read', &
                             registered_dims_out=reg_dims)
   read_grpid = resolve_savepoint_grpid(s, sp)
   ncerr = nf90_inq_varid(read_grpid, trim(fieldname), varid)
   call preserf_check_nf_with_msg(ncerr, 'inq_varid '//trim(fieldname))
   call require_variable_xtype(s, read_grpid, varid, fieldname, PRESERF_NCTYPE, &
                               known_dims_c=reg_dims)
   ncerr = nf90_get_var(read_grpid, varid, data)
   call preserf_check_nf_with_msg(ncerr, 'get_var '//trim(fieldname))
end subroutine PRESERF_SUB
