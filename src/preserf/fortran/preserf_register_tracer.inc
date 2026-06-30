! Template body for a ppser_register_tracer overload (ADR 0003 §3,
! storage_mapping.md §4a). Instantiated per rank from m_preserf.F90 via
! PRESERF_SUB (full subroutine name), PRESERF_DIMS (the rank's dimension
! spec), PRESERF_RANK (the integer rank) and PRESERF_PTR (the matching
! rank-specific pointer component of t_tracer_entry).
!
! The registry keeps a *pointer* to the caller's array (not a copy) so a
! read-mode `!$SER TRACER` can read the stored field back into it. The
! `data` actual MUST therefore have the TARGET attribute and outlive the
! run. Covers real(real64) ranks 1-4; other dtypes are a future
! stanza set (docs/adr/0004-fortran-cpp-templates.md).
subroutine PRESERF_SUB(name, data, stype)
   character(len=*), intent(in) :: name
   real(real64), target PRESERF_DIMS :: data
   character(len=*), intent(in), optional :: stype
   integer :: n
   n = register_tracer_slot(name, PRESERF_RANK, shape(data), stype)
   ppser_tracers(n)%PRESERF_PTR => data
end subroutine PRESERF_SUB
