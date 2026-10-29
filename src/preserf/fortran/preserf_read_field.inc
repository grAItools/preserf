! Template body for a numeric fs_read_field overload (DATA directive,
! read side). Instantiated per (dtype, rank) from m_preserf.F90 via the
! same macros as preserf_write_field.inc. See
! dev/adr/0004-fortran-cpp-templates.md. Logical fields use
! preserf_read_field_logical.inc instead.
subroutine PRESERF_SUB(s, sp, fieldname, data)
   type(t_serializer), intent(in) :: s
   type(t_savepoint), intent(in) :: sp
   character(len=*), intent(in) :: fieldname
   PRESERF_DTYPE, intent(inout) PRESERF_DIMS :: data
   integer :: ncerr, varid, read_grpid, data_grpid
   integer(int32), allocatable :: reg_dims(:)

   if (serialisation_enabled == 0) return
   call require_open(s, 'fs_read_field')
   call require_savepoint(sp, 'fs_read_field')
   call validate_field_shape(s, fieldname, shape(data), PRESERF_TID, 'read', &
                             registered_dims_out=reg_dims)
   read_grpid = resolve_savepoint_grpid(s, sp)
   ! In a deduplicated store (ADR 0014) the savepoint variable references a
   ! `/_dict` entry; resolve_read_variable follows that one indirection and
   ! returns the savepoint variable itself for a default store.
   call resolve_read_variable(s, read_grpid, fieldname, data_grpid, varid)
   call require_variable_xtype(s, data_grpid, varid, fieldname, PRESERF_NCTYPE, &
                               known_dims_c=reg_dims)
   ncerr = nf90_get_var(data_grpid, varid, data)
   call preserf_check_nf_with_msg(ncerr, 'get_var '//trim(fieldname))
end subroutine PRESERF_SUB
