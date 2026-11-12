!> Re-export of `utils_preserf` under Serialbox's historical name.
!>
!> pp_ser hard-codes `USE utils_ppser` in its generated output. This
!> module preserves that identifier and re-exports the full symbol surface:
!> `ppser_serializer`, `ppser_serializer_ref`, `ppser_savepoint`,
!> `ppser_initialize`, `ppser_finalize`, `ppser_get_mode`,
!> `ppser_set_mode`, `ppser_intlength`, `ppser_reallength`,
!> `ppser_realtype`, `ppser_zrperturb`.
!>
!> `ppser_initialize` accepts the Serialbox-compatible keyword arguments
!> pp_ser passes through from `!$SER INIT`: `singlefile`, `mpi_rank`,
!> `rprecision`, `rperturb`, `realtype`, `archive`, and `unique_id`.
!> `mpi_rank` / `rprecision` / `rperturb` / `realtype` change behaviour;
!> `singlefile` / `archive` / `unique_id` are recorded in root attributes.
!>
!> It also accepts the preserf-specific `backend` (`netcdf4` /
!> `nczarr-v2`) and the store-wide `compression` keywords: `compression`
!> is a zlib deflate level (1..9 chunks and deflates every field- and
!> tracer-data variable, 0 keeps the backend's default layout) that the
!> preprocessor maps `on` onto `PPSER_DEFAULT_DEFLATE_LEVEL` and `off`
!> onto 0. See `dev/references/storage_mapping.md` §6 and §9.
module utils_ppser
   use utils_preserf
   implicit none
end module utils_ppser
