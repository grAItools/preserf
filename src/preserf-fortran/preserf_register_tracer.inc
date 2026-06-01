! Template body for a ppser_register_tracer overload (ADR 0003 §3,
! storage_mapping.md §4a). Instantiated per rank from m_preserf.F90 via
! PRESERF_SUB (full subroutine name) and PRESERF_DIMS (the rank's
! dimension spec). Each overload flattens the caller's real(real64)
! tracer array into a 1-D buffer and records its Fortran shape; the
! shared register_tracer_impl does the table insertion. v1.0 covers
! real(real64) ranks 1-4; other dtypes are a future stanza set
! (docs/adr/0004-fortran-cpp-templates.md).
subroutine PRESERF_SUB(name, data, stype)
   character(len=*), intent(in) :: name
   real(real64), intent(in) PRESERF_DIMS :: data
   character(len=*), intent(in), optional :: stype
   call register_tracer_impl(name, reshape(data, [size(data)]), shape(data), stype)
end subroutine PRESERF_SUB
