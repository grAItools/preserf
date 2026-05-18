!> Re-export of `utils_preserf` under Serialbox's historical name.
!>
!> pp_ser hard-codes `USE utils_ppser` in its generated output. This
!> module preserves that identifier for the **v0.1 symbol surface**:
!> `ppser_serializer`, `ppser_serializer_ref`, `ppser_savepoint`,
!> `ppser_initialize`, `ppser_finalize`, `ppser_get_mode`,
!> `ppser_set_mode`, `ppser_intlength`, `ppser_reallength`,
!> `ppser_realtype`, `ppser_zrperturb`.
!>
!> Generated source that passes Serialbox-only keyword arguments to
!> `ppser_initialize` (e.g. `singlefile=.true.`, `mpi_rank=...`,
!> `archive=...`) is **not** supported by this slice and will fail to
!> compile until the pp_ser-port follow-up widens
!> `ppser_initialize`'s signature.
module utils_ppser
    use utils_preserf
    implicit none
end module utils_ppser
