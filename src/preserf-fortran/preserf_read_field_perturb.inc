! Template body for a 5-argument fs_read_field overload (pp_ser's
! read-perturb CASE(2) form). Reads the unperturbed field via its 4-arg
! sibling PRESERF_BASE, then applies multiplicative noise via
! PRESERF_APPLY. The `perturb` scale is always real64 because pp_ser
! passes ppser_zrperturb (real64) regardless of the field's kind.
! Instantiated for the two floating dtypes x ranks 0-4.
subroutine PRESERF_SUB(s, sp, fieldname, data, perturb)
   type(t_serializer), intent(in) :: s
   type(t_savepoint), intent(in) :: sp
   character(len=*), intent(in) :: fieldname
   PRESERF_DTYPE, intent(inout) PRESERF_DIMS :: data
   real(real64), intent(in) :: perturb
   if (serialisation_enabled == 0) return
   call PRESERF_BASE(s, sp, fieldname, data)
   call PRESERF_APPLY(data, perturb)
end subroutine PRESERF_SUB
