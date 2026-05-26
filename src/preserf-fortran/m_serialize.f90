!> Re-export of `m_preserf` under Serialbox's historical module name.
!>
!> pp_ser by default emits `USE m_serialize, ONLY: fs_write_field, ...`
!> (configurable via `--module`). This module preserves the historical
!> module identifier for the **v0.1 API surface** documented in
!> `src/preserf-fortran/README.md`: `fs_register_field`,
!> `fs_create_savepoint`, `fs_add_savepoint_metainfo`,
!> `fs_add_serializer_metainfo`, `fs_write_field`, `fs_read_field`,
!> `fs_enable_serialization`, `fs_disable_serialization`,
!> `fs_serialization_status`.
!>
!> pp_ser output that uses directives not yet implemented (e.g.
!> `DATA_KBUFF`, `OPTION`, `REGISTERTRACERS`, `TRACER`) imports
!> `fs_write_kbuff` / `fs_Option` / `fs_RegisterAllTracers` /
!> `ppser_write_tracer_*`, which `m_preserf` does NOT yet export, and
!> will fail to compile against this re-export until those follow-ups
!> land.
module m_serialize
   use m_preserf
   implicit none
   ! `use m_preserf` re-exports everything m_preserf marks public; no
   ! additional declarations are needed.
end module m_serialize
