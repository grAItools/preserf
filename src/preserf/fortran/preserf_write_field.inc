! Template body for a numeric fs_write_field overload (DATA directive,
! write side). Instantiated per (dtype, rank) from m_preserf.F90 via the
! macros PRESERF_SUB (full subroutine name), PRESERF_DTYPE (declared
! type), PRESERF_DIMS (dimension attribute, empty for rank 0),
! PRESERF_NCTYPE (on-disk netCDF type) and PRESERF_TID (Serialbox
! TypeID). See docs/adr/0004-fortran-cpp-templates.md. Logical fields use
! preserf_write_field_logical.inc instead (they need a 0/1 byte buffer).
subroutine PRESERF_SUB(s, sp, fieldname, data)
   type(t_serializer), intent(inout) :: s
   type(t_savepoint), intent(in) :: sp
   character(len=*), intent(in) :: fieldname
   PRESERF_DTYPE, intent(in) PRESERF_DIMS :: data
   integer :: ncerr, varid
   integer, allocatable :: dimids(:)

   if (serialisation_enabled == 0) return
   call require_open(s, 'fs_write_field')
   call require_savepoint(sp, 'fs_write_field')
   call require_savepoint_owner(s, sp, 'fs_write_field')
   ! shape(data) is a zero-length vector for a rank-0 (scalar) field, so
   ! the same body covers 0-D through 4-D: validate, create the
   ! dims/variable, and write.
   call validate_field_shape(s, fieldname, shape(data), PRESERF_TID, 'write')
   call ensure_dims(sp%grpid, fieldname, shape(data), dimids)
   call ensure_variable(sp%grpid, fieldname, PRESERF_NCTYPE, dimids, varid)
   ncerr = nf90_put_var(sp%grpid, varid, data)
   call preserf_check_nf_with_msg(ncerr, 'put_var '//trim(fieldname))
end subroutine PRESERF_SUB
