!> preserf Fortran helper: serializer / savepoint state + lifecycle.
!>
!> This module owns the global state that `pp_ser`-expanded directives
!> rely on (`ppser_serializer`, `ppser_serializer_ref`, `ppser_savepoint`,
!> `ppser_realtype`, `ppser_zrperturb`, plus the mode getter/setter).
!>
!> The actual netCDF operations live in m_preserf; this module only
!> handles dataset open/close and mode state. v0.1 targets plain
!> NetCDF4 stores only — NCZarr URL targets are out of scope (see
!> src/preserf-fortran/README.md "Known limitations" §NCZarr).
!>
!> Backed by the schema documented in
!> `docs/references/storage_mapping.md`.
module utils_preserf
   use, intrinsic :: iso_fortran_env, only: int32, real64
   use netcdf
   implicit none
   private

   ! -------------------------------------------------------------------------
   ! Public type definitions
   ! -------------------------------------------------------------------------
   !
   ! t_serializer wraps a netCDF dataset plus the schema group IDs.
   ! ncid == -1 means "not initialised".
   !
   type, public :: t_serializer
      integer :: ncid = -1
      integer :: fields_grpid = -1
      integer :: savepoints_grpid = -1
      integer :: next_sp_index = 0
      logical :: writable = .true.
   end type t_serializer

   !
   ! t_savepoint refers to one /savepoints/sp_NNNNNN subgroup.
   !
   ! `owner_ncid` records the `ncid` of the serializer that created
   ! the group. fs_write_field validates the field registry through
   ! its serializer argument but writes the data variable under
   ! `grpid`; cross-checking `owner_ncid` rejects a savepoint that
   ! belongs to a different store, which would otherwise let the
   ! registry and the data variable diverge into different files.
   !
   type, public :: t_savepoint
      integer :: grpid = -1
      integer :: idx = -1
      integer :: owner_ncid = -1
   end type t_savepoint

   ! -------------------------------------------------------------------------
   ! Module-level state (mirrors Serialbox's utils_ppser surface)
   ! -------------------------------------------------------------------------
   type(t_serializer), public, save, target :: ppser_serializer
   type(t_serializer), public, save, target :: ppser_serializer_ref
   type(t_savepoint), public, save :: ppser_savepoint

   ! Byte-length constants for pp_ser-emitted `fs_register_field`
   ! calls. Declared in default `integer` kind (not int32) so they
   ! match the `bytes_per_element` dummy argument's kind on builds
   ! that compile with `-fdefault-integer-8` or similar — Fortran's
   ! explicit-interface kind checking would otherwise fail when
   ! generated code passes `ppser_reallength` to `fs_register_field`.
   integer, parameter, public :: ppser_intlength = 4

   ! Real-field type metadata for pp_ser-emitted `fs_register_field`
   ! calls. These are mutable `save` state (not `parameter`) so the
   ! `realtype` / `rprecision` keywords on `!$SER INIT` can override
   ! them via `ppser_initialize`; the `PPSER_DEFAULT_*` parameters
   ! below are the Serialbox double-precision defaults, used both as
   ! the initial values here and as the reset target on every fresh
   ! `ppser_initialize` (so a prior override does not stick across a
   ! later init that omits the keyword). `ppser_realtype` is
   ! fixed-length (padded with blanks); `type_id_from_datatype` trims
   ! before matching, so the padding is harmless.
   integer, parameter, public :: PPSER_DEFAULT_REALLENGTH = 8
   character(len=*), parameter, public :: PPSER_DEFAULT_REALTYPE = 'double'
   real(real64), parameter, public :: PPSER_DEFAULT_RPERTURB = 0.0_real64
   integer, public, save :: ppser_reallength = PPSER_DEFAULT_REALLENGTH
   character(len=16), public, save :: ppser_realtype = PPSER_DEFAULT_REALTYPE
   real(real64), public, save :: ppser_zrperturb = PPSER_DEFAULT_RPERTURB

   ! Mode: 0 = write, 1 = read, 2 = read-perturb.
   integer, save :: ppser_mode_state = 0

   ! ON / OFF gate for the fs_* I/O entry points in m_preserf.
   ! 1 = enabled (default), 0 = disabled. Owned here (rather than in
   ! m_preserf) so `ppser_initialize` can reset it on a fresh session;
   ! without that reset, a process that called `fs_disable_serialization`
   ! before a previous `ppser_finalize` would silently no-op every
   ! subsequent fs_* call in the same process.
   integer, save, public :: serialisation_enabled = 1

   ! Schema version written into _preserf_schema_version. Must match
   ! tests/_support/storage.py SCHEMA_VERSION.
   integer(int32), parameter, public :: PRESERF_SCHEMA_VERSION = 1

   ! Cap matching storage_mapping.md §5 (sp_{idx:06d} naming).
   integer, parameter, public :: PRESERF_SAVEPOINT_INDEX_LIMIT = 1000000

   ! -------------------------------------------------------------------------
   ! Public procedures
   ! -------------------------------------------------------------------------
   public :: ppser_initialize, ppser_finalize
   public :: ppser_get_mode, ppser_set_mode
   public :: preserf_check_nf, preserf_check_nf_with_msg
   public :: preserf_writer_version

contains

   !> Check a netCDF return code; abort the program with a helpful message
   !> if it indicates an error.
   subroutine preserf_check_nf(ncerr)
      integer, intent(in) :: ncerr
      if (ncerr /= NF90_NOERR) then
         write (*, '(a,a)') 'preserf: netCDF error: ', trim(nf90_strerror(ncerr))
         error stop 1
      end if
   end subroutine preserf_check_nf

   subroutine preserf_check_nf_with_msg(ncerr, where)
      integer, intent(in) :: ncerr
      character(len=*), intent(in) :: where
      if (ncerr /= NF90_NOERR) then
         write (*, '(a,a,a,a)') 'preserf: netCDF error in ', trim(where), &
            ': ', trim(nf90_strerror(ncerr))
         error stop 1
      end if
   end subroutine preserf_check_nf_with_msg

   function preserf_writer_version() result(s)
      use preserf_version_mod, only: PRESERF_VERSION
      character(len=:), allocatable :: s
      s = 'preserf '//PRESERF_VERSION
   end function preserf_writer_version

   !> Initialise the global serializer (and optionally a read-reference
   !> serializer) by opening a **NetCDF4** dataset under `directory`
   !> with name `prefix`. v0.1 only supports plain NetCDF4 stores —
   !> NCZarr URL targets are out of scope (see
   !> src/preserf-fortran/README.md "Known limitations" §NCZarr).
   !>
   !> **Precondition:** `directory` MUST already exist on disk. The
   !> helper calls `nf90_create(directory//'/'//prefix//'.nc', ...)`
   !> directly and does not create parent directories — `nf90_create`
   !> propagates the underlying HDF5 / system error if the parent is
   !> missing. The Python reference writer in `tests/_support/storage.py`
   !> creates the directory with `mkdir(parents=True, exist_ok=True)`;
   !> Fortran callers are responsible for an equivalent step before
   !> calling `ppser_initialize`. The CTest target
   !> `preserf_fortran_minimal_setup` runs `cmake -E make_directory`
   !> for this reason; tests/integration_tests/test_fortran_wire_compat.py uses pytest's
   !> `tmp_path` fixture.
   !>
   !> `mode` is one of: 'w' (write, create or truncate), 'r' (read-only).
   !> Append mode ('a') is reserved but currently rejected — see
   !> src/preserf-fortran/README.md follow-ups.
   !>
   !> When mode is 'r', the schema-version attribute on the root group is
   !> validated. In 'r' mode, `ppser_serializer_ref` is also populated:
   !>   * If `directory_ref` AND `prefix_ref` are both supplied, the
   !>     reference serializer opens that distinct store read-only.
   !>   * Otherwise it opens the same `directory/prefix` store read-only,
   !>     so pp_ser-generated DATA branches that use
   !>     `fs_read_field(ppser_serializer_ref, ...)` work without
   !>     further setup.
   !>
   !> When `directory_ref`/`prefix_ref` are supplied, the reference
   !> store is opened *before* the main store, so a wrong reference
   !> path aborts cleanly without truncating an existing target file
   !> in write mode.
   subroutine ppser_initialize(directory, prefix, mode, &
                               directory_ref, prefix_ref, &
                               singlefile, mpi_rank, rprecision, &
                               rperturb, realtype, archive, unique_id)
      character(len=*), intent(in) :: directory
      character(len=*), intent(in) :: prefix
      character(len=*), intent(in) :: mode
      character(len=*), intent(in), optional :: directory_ref
      character(len=*), intent(in), optional :: prefix_ref
      ! Serialbox-compatible keywords pp_ser passes through from
      ! `!$SER INIT`. Defaults match Serialbox so existing call sites
      ! are unaffected when a keyword is absent.
      logical, intent(in), optional :: singlefile
      integer, intent(in), optional :: mpi_rank
      integer, intent(in), optional :: rprecision
      real(real64), intent(in), optional :: rperturb
      character(len=*), intent(in), optional :: realtype
      character(len=*), intent(in), optional :: archive
      integer, intent(in), optional :: unique_id

      ! Validate optional-argument coherence BEFORE creating/truncating
      ! the main store, so a partial-arg mistake doesn't trash an
      ! existing target file.
      if (present(directory_ref) .neqv. present(prefix_ref)) then
         write (*, '(a)') 'preserf: ppser_initialize requires either both '// &
            'directory_ref and prefix_ref, or neither'
         error stop 1
      end if

      ! Behaviour-changing keywords: update the module state that
      ! pp_ser-generated REGISTER / DATA calls consume. `rprecision`
      ! is the real byte length; `realtype` is the type string passed
      ! to `fs_register_field`; `rperturb` feeds the read-perturb path
      ! (Slice A-2) via `ppser_zrperturb`.
      !
      ! Reset to the Serialbox defaults FIRST. These three are module
      ! SAVE state, so without a reset an override from a prior init in
      ! the same process would stick across a later init that omits the
      ! keyword — the omitting init must see the documented default, not
      ! the stale override.
      ppser_reallength = PPSER_DEFAULT_REALLENGTH
      ppser_realtype = PPSER_DEFAULT_REALTYPE
      ppser_zrperturb = PPSER_DEFAULT_RPERTURB
      if (present(rprecision)) ppser_reallength = rprecision
      if (present(realtype)) then
         ! `realtype` comes from a user-authored `!$SER INIT` directive,
         ! so reject an over-long value loudly rather than silently
         ! truncating it into the fixed-length `ppser_realtype` (which
         ! would then mis-register every real field).
         if (len_trim(realtype) > len(ppser_realtype)) then
            write (*, '(a,i0,a)') &
               'preserf: realtype string exceeds ', len(ppser_realtype), &
               ' characters'
            error stop 1
         end if
         ppser_realtype = realtype
      end if
      if (present(rperturb)) ppser_zrperturb = rperturb

      ! singlefile / archive / unique_id are metadata-only on the
      ! preserf side; recording them in root attributes is Slice D
      ! Phase 3 (deferred). Accept them here for signature
      ! compatibility with pp_ser-emitted INIT calls; the present()
      ! probes keep -Wall/-Wextra from flagging them as unused dummies.
      if (present(singlefile) .or. present(archive) .or. &
          present(unique_id)) continue

      ! Open the read-only reference store FIRST when an explicit
      ! `directory_ref`/`prefix_ref` pair is supplied. In write or
      ! append mode the main `nf90_create` truncates the target file
      ! on success, so a wrong reference path discovered after the
      ! main open would have already destroyed the user's data. By
      ! opening the reference first, a bad reference path aborts
      ! cleanly without touching the writable target.
      if (present(directory_ref) .and. present(prefix_ref)) then
         call preserf_open_serializer(ppser_serializer_ref, &
                                      directory_ref, prefix_ref, 'r', &
                                      rank=mpi_rank)
      end if

      call preserf_open_serializer(ppser_serializer, directory, prefix, mode, &
                                   rank=mpi_rank)

      if (.not. (present(directory_ref) .and. present(prefix_ref))) then
         if (mode == 'r' .or. mode == 'R') then
            ! pp_ser-generated read/read-perturb DATA branches call
            ! `fs_read_field(ppser_serializer_ref, ...)`. In a plain
            ! read-mode init without explicit reference args, point
            ! the ref serializer at the same store so those branches
            ! just work. Both serializers open their own netCDF
            ! handle to the same on-disk file (HDF5 allows multiple
            ! read-only opens).
            call preserf_open_serializer(ppser_serializer_ref, &
                                         directory, prefix, 'r', &
                                         rank=mpi_rank)
         end if
      end if

      ! Default the runtime DATA mode to match the open mode, so
      ! pp_ser-generated `SELECT CASE (ppser_get_mode())` blocks
      ! take the matching branch out of the box: 'w' → 0 (write),
      ! 'r' → 1 (read). Callers that want read-perturb (mode 2) or
      ! some other override still need to call `ppser_set_mode(...)`
      ! explicitly. Without this default, a read-only init would
      ! leave the mode at 0 and a generated DATA block would attempt
      ! to write into the read-only store.
      select case (mode)
      case ('w', 'W')
         ppser_mode_state = 0
      case ('r', 'R')
         ppser_mode_state = 1
      end select

      ! Re-enable the ON/OFF gate. The flag is module SAVE state and
      ! survives a previous ppser_finalize, so a caller that ran
      ! fs_disable_serialization() before its last finalize would
      ! otherwise leave every subsequent fs_* call in this process a
      ! silent no-op even after a fresh INIT.
      serialisation_enabled = 1
   end subroutine ppser_initialize

   !> Close the dataset(s) opened by ppser_initialize.
   subroutine ppser_finalize()
      call preserf_close_serializer(ppser_serializer)
      call preserf_close_serializer(ppser_serializer_ref)
      ppser_savepoint%grpid = -1
      ppser_savepoint%idx = -1
      ppser_savepoint%owner_ncid = -1
      ppser_mode_state = 0
      ! Also restore the ON/OFF gate to its default. ppser_initialize
      ! re-sets this on every fresh session as belt-and-braces, but
      ! resetting here too means an explicit finalize + later code
      ! that touches fs_* without a fresh init at least starts from
      ! a clean state.
      serialisation_enabled = 1
   end subroutine ppser_finalize

   function ppser_get_mode() result(m)
      integer :: m
      m = ppser_mode_state
   end function ppser_get_mode

   !> Set the runtime DATA mode. Only 0 (write), 1 (read), and 2
   !> (read-perturb) are accepted; pp_ser-generated SELECT CASE blocks
   !> only branch on these three values, so silently storing an
   !> out-of-range mode would make subsequent DATA directives behave
   !> as no-ops without explanation.
   subroutine ppser_set_mode(m)
      integer, intent(in) :: m
      if (m < 0 .or. m > 2) then
         write (*, '(a,i0,a)') &
            'preserf: ppser_set_mode(', m, &
            ') is out of range; expected 0 (write), 1 (read), '// &
            'or 2 (read-perturb)'
         error stop 1
      end if
      ppser_mode_state = m
   end subroutine ppser_set_mode

   ! -------------------------------------------------------------------------
   ! Internal helpers
   ! -------------------------------------------------------------------------

   subroutine preserf_open_serializer(s, directory, prefix, mode, rank)
      type(t_serializer), intent(inout) :: s
      character(len=*), intent(in) :: directory
      character(len=*), intent(in) :: prefix
      character(len=*), intent(in) :: mode
      integer, intent(in), optional :: rank

      character(len=:), allocatable :: path
      character(len=32) :: rank_suffix
      integer :: ncerr, version

      ! `mpi_rank` maps to a `_rank<n>` suffix on the on-disk store
      ! name (storage_mapping.md §9) so parallel runs write one store
      ! per rank instead of clobbering a shared file. The suffix is
      ! applied here, the single point where the path is built, and
      ! only to the file name — the logical `prefix` recorded in the
      ! `_preserf_serialbox_prefix` root attribute stays unsuffixed.
      if (present(rank)) then
         write (rank_suffix, '(a,i0)') '_rank', rank
         path = trim(directory)//'/'//trim(prefix)//trim(rank_suffix)//'.nc'
      else
         path = trim(directory)//'/'//trim(prefix)//'.nc'
      end if

      select case (mode)
      case ('w', 'W')
         ncerr = nf90_create(path, NF90_NETCDF4, s%ncid)
         call preserf_check_nf_with_msg(ncerr, 'nf90_create '//path)
         s%writable = .true.
         call preserf_write_root_housekeeping(s, prefix)
         call preserf_create_skeleton_groups(s)

      case ('r', 'R')
         ncerr = nf90_open(path, NF90_NOWRITE, s%ncid)
         call preserf_check_nf_with_msg(ncerr, 'nf90_open '//path)
         s%writable = .false.
         call preserf_validate_schema_version(s, version)
         call preserf_resolve_skeleton_groups(s)

      case ('a', 'A')
         ! Append mode requires resuming next_sp_index by scanning the
         ! existing /savepoints/sp_NNNNNN groups, which needs an
         ! nf90_inq_grps call shape that the netcdf-fortran 4.5.x
         ! wrapper makes awkward (see src/preserf-fortran/README.md
         ! follow-ups). Until that is implemented, 'a' is rejected
         ! rather than silently corrupting _preserf_savepoint_count
         ! (which would be rewritten to 0 on close).
         write (*, '(a)') &
            'preserf: append mode (a) is not yet supported in v0.1; '// &
            'use w (create) or r (read)'
         error stop 1

      case default
         write (*, '(a,a)') 'preserf: unknown open mode: ', mode
         error stop 1
      end select
      ! Silence "unused" warning for `version` on write-path opens.
      if (.false.) version = version
   end subroutine preserf_open_serializer

   subroutine preserf_close_serializer(s)
      type(t_serializer), intent(inout) :: s
      integer :: ncerr
      integer(int32) :: savepoint_count
      logical :: entered_define_mode

      if (s%ncid /= -1) then
         if (s%writable) then
            ! Refresh the savepoint count attribute before closing.
            !
            ! On NETCDF4 (HDF5-backed) datasets nf90_redef is a no-op
            ! and returns NF90_NOERR; on classic datasets it actually
            ! enters define mode. Some files may already be in define
            ! mode from earlier writes, in which case redef returns
            ! NF90_EINDEFINE — we treat that as a no-op too. Any
            ! other return code is unexpected and aborts the close
            ! rather than silently skipping the metadata refresh.
            ncerr = nf90_redef(s%ncid)
            if (ncerr == NF90_NOERR) then
               entered_define_mode = .true.
            else if (ncerr == NF90_EINDEFINE) then
               entered_define_mode = .false.
            else
               call preserf_check_nf_with_msg(ncerr, 'nf90_redef before close')
               entered_define_mode = .false.  ! unreachable
            end if

            savepoint_count = int(s%next_sp_index, int32)
            ncerr = nf90_put_att(s%ncid, NF90_GLOBAL, &
                                 '_preserf_savepoint_count', savepoint_count)
            call preserf_check_nf_with_msg(ncerr, &
                                           'nf90_put_att _preserf_savepoint_count')

            if (entered_define_mode) then
               ncerr = nf90_enddef(s%ncid)
               call preserf_check_nf_with_msg(ncerr, 'nf90_enddef before close')
            end if
         end if
         ncerr = nf90_close(s%ncid)
         call preserf_check_nf_with_msg(ncerr, 'nf90_close')
         s%ncid = -1
         s%fields_grpid = -1
         s%savepoints_grpid = -1
         s%next_sp_index = 0
         s%writable = .true.
      end if
   end subroutine preserf_close_serializer

   subroutine preserf_write_root_housekeeping(s, prefix)
      type(t_serializer), intent(inout) :: s
      character(len=*), intent(in) :: prefix
      integer :: ncerr
      integer(int32) :: zero, schema_version

      zero = 0_int32
      schema_version = PRESERF_SCHEMA_VERSION

      ncerr = nf90_put_att(s%ncid, NF90_GLOBAL, &
                           '_preserf_schema_version', schema_version)
      call preserf_check_nf_with_msg(ncerr, 'put_att _preserf_schema_version')

      ncerr = nf90_put_att(s%ncid, NF90_GLOBAL, &
                           '_preserf_serialbox_prefix', trim(prefix))
      call preserf_check_nf_with_msg(ncerr, 'put_att _preserf_serialbox_prefix')

      ncerr = nf90_put_att(s%ncid, NF90_GLOBAL, &
                           '_preserf_savepoint_count', zero)
      call preserf_check_nf_with_msg(ncerr, 'put_att _preserf_savepoint_count')

      ncerr = nf90_put_att(s%ncid, NF90_GLOBAL, &
                           '_preserf_writer', preserf_writer_version())
      call preserf_check_nf_with_msg(ncerr, 'put_att _preserf_writer')
   end subroutine preserf_write_root_housekeeping

   subroutine preserf_create_skeleton_groups(s)
      type(t_serializer), intent(inout) :: s
      integer :: ncerr

      ncerr = nf90_def_grp(s%ncid, '_fields', s%fields_grpid)
      call preserf_check_nf_with_msg(ncerr, 'def_grp /_fields')

      ncerr = nf90_def_grp(s%ncid, 'savepoints', s%savepoints_grpid)
      call preserf_check_nf_with_msg(ncerr, 'def_grp /savepoints')
   end subroutine preserf_create_skeleton_groups

   subroutine preserf_resolve_skeleton_groups(s)
      type(t_serializer), intent(inout) :: s
      integer :: ncerr

      ncerr = nf90_inq_ncid(s%ncid, '_fields', s%fields_grpid)
      call preserf_check_nf_with_msg(ncerr, 'inq_ncid /_fields')

      ncerr = nf90_inq_ncid(s%ncid, 'savepoints', s%savepoints_grpid)
      call preserf_check_nf_with_msg(ncerr, 'inq_ncid /savepoints')

      ! Append-mode index resumption (scanning existing /savepoints/sp_*
      ! groups to pick up where the previous run left off) is intentionally
      ! deferred — it requires nf90_inq_grps with a pre-sized output array,
      ! and 'a' mode is out of scope for the minimal v0.1 helper.
      s%next_sp_index = 0
   end subroutine preserf_resolve_skeleton_groups

   subroutine preserf_validate_schema_version(s, version)
      type(t_serializer), intent(in) :: s
      integer, intent(out) :: version
      integer :: ncerr

      ncerr = nf90_get_att(s%ncid, NF90_GLOBAL, &
                           '_preserf_schema_version', version)
      call preserf_check_nf_with_msg(ncerr, &
                                     'get_att _preserf_schema_version (not a preserf store?)')

      if (version /= PRESERF_SCHEMA_VERSION) then
         write (*, '(a,i0,a,i0)') &
            'preserf: unsupported schema version ', version, &
            '; this build supports ', PRESERF_SCHEMA_VERSION
         error stop 1
      end if
   end subroutine preserf_validate_schema_version

end module utils_preserf
