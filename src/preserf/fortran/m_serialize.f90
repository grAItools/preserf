!> Re-export of `m_preserf` under Serialbox's historical module name.
!>
!> pp_ser by default emits `USE m_serialize, ONLY: fs_write_field, ...`
!> (configurable via `--module`). This module preserves the historical
!> module identifier for the API surface documented in
!> `src/preserf/fortran/README.md`: `fs_register_field`,
!> `fs_create_savepoint`, `fs_add_savepoint_metainfo`,
!> `fs_add_serializer_metainfo`, `fs_write_field`, `fs_read_field`,
!> `fs_enable_serialization`, `fs_disable_serialization`,
!> `fs_serialization_status`, plus the tracer + k-buffer + option surface
!> (ADR 0003): `fs_RegisterAllTracers`,
!> `ppser_write_tracer_by_name`, `ppser_write_tracer_by_idx`,
!> `ppser_write_tracer_all`, the host-side `ppser_register_tracer`,
!> `fs_write_kbuff` (DATA_KBUFF), and `fs_Option` (OPTION).
module m_serialize
   use m_preserf
   implicit none
   ! `use m_preserf` re-exports everything m_preserf marks public; no
   ! additional declarations are needed.
end module m_serialize
