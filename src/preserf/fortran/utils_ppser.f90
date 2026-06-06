!> Re-export of `utils_preserf` under Serialbox's historical name.
!>
!> pp_ser hard-codes `USE utils_ppser` in its generated output. This
!> module preserves that identifier for the **v0.1 symbol surface**:
!> `ppser_serializer`, `ppser_serializer_ref`, `ppser_savepoint`,
!> `ppser_initialize`, `ppser_finalize`, `ppser_get_mode`,
!> `ppser_set_mode`, `ppser_intlength`, `ppser_reallength`,
!> `ppser_realtype`, `ppser_zrperturb`.
!>
!> `ppser_initialize` accepts the Serialbox-compatible keyword
!> arguments pp_ser passes through from `!$SER INIT`: `singlefile`,
!> `mpi_rank`, `rprecision`, `rperturb`, `realtype`, `archive`, and
!> `unique_id`. `mpi_rank` / `rprecision` / `rperturb` / `realtype`
!> change behaviour; `singlefile` / `archive` / `unique_id` are
!> accepted for compatibility and recorded in root attributes by a
!> follow-up (Slice D Phase 3).
module utils_ppser
   use utils_preserf
   implicit none
end module utils_ppser
