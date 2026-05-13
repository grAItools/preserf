!> Drop-in re-export of m_preserf under Serialbox's historical module name.
!>
!> pp_ser by default emits `USE m_serialize, ONLY: fs_write_field, ...`
!> (configurable via `--module`). This module exists so that pp_ser output
!> targeting Serialbox naming compiles unchanged against preserf.
module m_serialize
    use m_preserf
    implicit none
    ! `use m_preserf` re-exports everything m_preserf marks public; no
    ! additional declarations are needed.
end module m_serialize
