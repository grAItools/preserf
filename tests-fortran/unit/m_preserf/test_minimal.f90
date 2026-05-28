!> Minimal end-to-end exercise of the preserf Fortran helper API.
!>
!> Registers three `real(real64)` fields covering the 1-D / 2-D / 3-D
!> `fs_write_field` / `fs_read_field` overloads (`v(5)`, `w(3,4)`,
!> `u(4,3,2)`), with non-zero halos on `u` to exercise the `put_halo_attr`
!> path. Writes a serializer-level metainfo mix that covers every
!> scalar overload (String, Int32, Boolean, Int64, Float32) plus a
!> savepoint with Int32 + Float64 metainfo. Then re-opens the store
!> read-only and reads all three fields back to verify lossless
!> round-trip.
!>
!> The Python test in tests/integration_tests/test_fortran_wire_compat.py runs this binary
!> and additionally validates the on-disk attribute and variable types
!> directly via netCDF4 (so the kind-specific `nf90_put_att` branches
!> are protected against on-disk type regressions).
program test_minimal
   use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
   ! Deliberately import the alias module names rather than the real
   ! ones (utils_preserf, m_preserf). pp_ser-generated source uses
   ! `USE m_serialize` / `USE utils_ppser`, so wiring the integration
   ! test through the same names protects the re-export path against
   ! regressions (a removed/renamed public symbol that breaks the
   ! aliases will fail this test instead of silently slipping
   ! through).
   use utils_ppser
   use m_serialize
   implicit none

   character(len=:), allocatable :: out_dir
   character(len=:), allocatable :: arg_buf
   integer :: arg_len, arg_stat
   real(real64), allocatable :: u(:, :, :), u_back(:, :, :)
   real(real64), allocatable :: v(:), v_back(:)
   real(real64), allocatable :: w(:, :), w_back(:, :)
   integer, parameter :: ni = 4, nj = 3, nk = 2
   integer, parameter :: nv = 5
   integer, parameter :: nw_i = 3, nw_j = 4
   integer :: i, j, k
   real(real64) :: maxdiff
   ! No local `sp` declaration: pp_ser-generated code uses the
   ! module-level `ppser_savepoint` from utils_ppser, so exercising
   ! the integration test through that handle protects the
   ! default-arg branch of fs_create_savepoint against regressions.

   if (command_argument_count() < 1) then
      write (*, '(a)') 'usage: test_minimal <output_dir>'
      error stop 1
   end if
   ! Query the argument length first (the LENGTH= form of
   ! get_command_argument returns the full required size), then
   ! allocate a buffer of exactly that length — a fixed-size buffer
   ! could truncate or overflow.
   call get_command_argument(1, length=arg_len, status=arg_stat)
   if (arg_stat /= 0) then
      write (*, '(a,i0)') &
         'preserf-test_minimal: get_command_argument(length) failed, status=', &
         arg_stat
      error stop 1
   end if
   allocate (character(len=arg_len) :: arg_buf)
   call get_command_argument(1, value=arg_buf, status=arg_stat)
   if (arg_stat /= 0) then
      write (*, '(a,i0)') &
         'preserf-test_minimal: get_command_argument(value) failed, status=', &
         arg_stat
      error stop 1
   end if
   out_dir = arg_buf
   ! Note: the caller is responsible for ensuring out_dir exists.
   ! Both invocation paths handle this:
   !   * pytest creates the dir via the tmp_path fixture before exec.
   !   * ctest's COMMAND list runs `cmake -E make_directory` first.

   ! An optional second argument selects an alternate scenario; with
   ! no second argument the full hello-world round-trip below runs.
   !
   ! 'badref-write' exercises the bad-reference-path safety property
   ! of ppser_initialize: when an explicit directory_ref / prefix_ref
   ! pair is supplied, the reference store is opened *before* the
   ! writable main store is created/truncated, so a missing reference
   ! path must abort without destroying the target file. This branch
   ! just triggers the abort; tests/integration_tests/test_fortran_wire_compat.py drives the
   ! scenario and asserts the writable target survived intact.
   if (command_argument_count() >= 2) then
      block
         character(len=:), allocatable :: scenario
         integer :: s_len, s_stat
         call get_command_argument(2, length=s_len, status=s_stat)
         if (s_stat /= 0) error stop &
            'preserf-test_minimal: get_command_argument(2,length) failed'
         allocate (character(len=s_len) :: scenario)
         call get_command_argument(2, value=scenario, status=s_stat)
         if (s_stat /= 0) error stop &
            'preserf-test_minimal: get_command_argument(2,value) failed'
         if (scenario == 'badref-write') then
            ! The reference directory does not exist, so the
            ! reference nf90_open fails and ppser_initialize aborts
            ! before the main nf90_create can truncate the target.
            call ppser_initialize(out_dir, 'fhello', 'w', &
                                  directory_ref=trim(out_dir)//'/__preserf_no_such_ref__', &
                                  prefix_ref='nope')
            ! Unreachable: a missing reference store must abort.
            error stop &
               'preserf-test_minimal: bad directory_ref was accepted'
         else if (scenario == 'init-keywords') then
            ! Exercise the behaviour-changing keywords widened onto
            ! ppser_initialize in Slice D: realtype / rprecision (real
            ! field type metadata), rperturb (read-perturb scale), and
            ! mpi_rank (per-rank store suffix). Metadata-only keywords
            ! (singlefile / archive / unique_id) are Slice D Phase 3.
            block
               use netcdf
               ! Mirrors the (private) TID_FLOAT32 in m_preserf; the
               ! float32 TypeID per storage_mapping.md.
               integer, parameter :: TID_FLOAT32 = 4
               integer :: ncerr, varid
               integer(int32) :: type_id_back
               logical :: exist0, exist1, exist_plain

               ! --- realtype / rprecision override ppser_realtype /
               ! ppser_reallength so a real field registers as float32 ---
               call ppser_initialize(out_dir, 'fkw', 'w', &
                                     realtype='float', rprecision=4)
               if (trim(ppser_realtype) /= 'float') error stop &
                  'init-keywords: realtype did not update ppser_realtype'
               if (ppser_reallength /= 4) error stop &
                  'init-keywords: rprecision did not update ppser_reallength'
               call fs_register_field(ppser_serializer, 'f32', &
                                      ppser_realtype, ppser_reallength, &
                                      3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
               ncerr = nf90_inq_varid(ppser_serializer%fields_grpid, &
                                      'f32', varid)
               if (ncerr /= nf90_noerr) error stop &
                  'init-keywords: inq_varid f32 failed'
               ncerr = nf90_get_att(ppser_serializer%fields_grpid, varid, &
                                    'type_id', type_id_back)
               if (ncerr /= nf90_noerr) error stop &
                  'init-keywords: get_att type_id failed'
               if (type_id_back /= TID_FLOAT32) error stop &
                  'init-keywords: realtype=float did not register float32'
               call ppser_finalize()

               ! --- rperturb threads to ppser_zrperturb (Slice A-2) ---
               call ppser_initialize(out_dir, 'fkw', 'w', rperturb=1.5_real64)
               if (ppser_zrperturb /= 1.5_real64) error stop &
                  'init-keywords: rperturb did not update ppser_zrperturb'
               ! realtype / rprecision were omitted on this init, so the
               ! prior init's overrides must NOT stick: they are module
               ! SAVE state and ppser_initialize resets them to the
               ! Serialbox defaults on every fresh session.
               if (trim(ppser_realtype) /= 'double') error stop &
                  'init-keywords: realtype override stuck across re-init'
               if (ppser_reallength /= 8) error stop &
                  'init-keywords: rprecision override stuck across re-init'
               call ppser_finalize()

               ! rperturb omitted here must likewise fall back to the
               ! default (0), not the 1.5 override from the init above.
               call ppser_initialize(out_dir, 'fkw', 'w')
               if (ppser_zrperturb /= 0.0_real64) error stop &
                  'init-keywords: rperturb override stuck across re-init'
               call ppser_finalize()

               ! --- mpi_rank suffixes the store name: one file per rank,
               ! and never the bare prefix (storage_mapping.md §9) ---
               ! Clear any fmr* stores first. The ctest fixture creates
               ! test-output but never cleans it, so a store left by a
               ! prior run could otherwise satisfy the positive existence
               ! checks (without this run writing it) or trip the
               ! bare-prefix negative check below — both false results.
               call delete_if_exists(trim(out_dir)//'/fmr.nc')
               call delete_if_exists(trim(out_dir)//'/fmr_rank0.nc')
               call delete_if_exists(trim(out_dir)//'/fmr_rank1.nc')
               call ppser_initialize(out_dir, 'fmr', 'w', mpi_rank=0)
               call ppser_finalize()
               call ppser_initialize(out_dir, 'fmr', 'w', mpi_rank=1)
               call ppser_finalize()
               inquire (file=trim(out_dir)//'/fmr_rank0.nc', exist=exist0)
               inquire (file=trim(out_dir)//'/fmr_rank1.nc', exist=exist1)
               inquire (file=trim(out_dir)//'/fmr.nc', exist=exist_plain)
               if (.not. (exist0 .and. exist1)) error stop &
                  'init-keywords: mpi_rank did not produce one store per rank'
               if (exist_plain) error stop &
                  'init-keywords: mpi_rank store must be suffixed, not bare'

               ! --- metadata-only keywords: signature compatibility ---
               ! singlefile / archive / unique_id are recorded as
               ! `_preserf_*` root attributes (Slice D Phase 3); the
               ! cross-language round-trip of their values is asserted in
               ! tests/integration_tests/test_preprocessor_e2e.py. Pass all
               ! three (with the behaviour-changing ones too) so a
               ! type/name mismatch in the widened interface fails to
               ! compile here rather than in downstream generated code.
               call ppser_initialize(out_dir, 'fmeta', 'w', &
                                     singlefile=.true., archive='netcdf', &
                                     unique_id=42, mpi_rank=0, &
                                     rprecision=8, rperturb=0.0_real64, &
                                     realtype='double')
               call ppser_finalize()

               write (*, '(a)') 'preserf-fortran: init-keywords OK'
               stop
            end block
         else if (scenario == 'realtype-too-long') then
            ! A realtype string longer than ppser_realtype's fixed
            ! length must abort rather than silently truncate (which
            ! would mis-register every real field). Python's
            ! test_fortran_realtype_too_long_aborts drives this scenario
            ! and asserts the non-zero exit + guard message.
            call ppser_initialize(out_dir, 'frt', 'w', &
                                  realtype='this_type_name_is_far_too_long')
            ! Unreachable: the length guard must abort before returning.
            error stop &
               'preserf-test_minimal: over-long realtype was accepted'
         else if (scenario == 'backend-nczarr') then
            ! Slice E: ppser_initialize(..., backend='nczarr-v2') makes
            ! the helper emit an NCZarr V2 `.zarr` directory store (via a
            ! file://...#mode=nczarr,zarr2 URL) instead of a `.nc` file,
            ! using the same group-per-savepoint schema. Write one real64
            ! field, finalize, then re-open the same store read-only (also
            ! backend='nczarr-v2') and read it back to prove the URL
            ! round-trips end to end through the Fortran helper. The
            ! Python wire-compat test additionally decodes the `.zarr`
            ! store via tests/_support/storage.py.
            block
               real(real64) :: uz(3), uz_back(3)
               integer :: i
               do i = 1, 3
                  uz(i) = 500.0_real64 + real(i, real64)
               end do
               call ppser_initialize(out_dir, 'fzarr', 'w', backend='nczarr-v2')
               call fs_add_serializer_metainfo(ppser_serializer, 'author', &
                                               'fortran-test')
               call fs_register_field(ppser_serializer, 'u', 'double', &
                                      ppser_reallength, 3, 0, 0, 0, &
                                      0, 0, 0, 0, 0, 0, 0, 0)
               call fs_create_savepoint('step', ppser_savepoint)
               call fs_add_savepoint_metainfo(ppser_savepoint, 'ntstep', 1_int32)
               call fs_write_field(ppser_serializer, ppser_savepoint, 'u', uz)
               call ppser_finalize()
               ! Re-open the NCZarr store read-only and read the field back.
               call ppser_initialize(out_dir, 'fzarr', 'r', backend='nczarr-v2')
               if (ppser_get_mode() /= 1) error stop &
                  'backend-nczarr: read open should set mode 1'
               call fs_register_field(ppser_serializer, 'u', 'double', &
                                      ppser_reallength, 3, 0, 0, 0, &
                                      0, 0, 0, 0, 0, 0, 0, 0)
               call fs_create_savepoint('step', ppser_savepoint)
               call fs_add_savepoint_metainfo(ppser_savepoint, 'ntstep', 1_int32)
               call fs_read_field(ppser_serializer, ppser_savepoint, 'u', uz_back)
               do i = 1, 3
                  if (uz_back(i) /= 500.0_real64 + real(i, real64)) error stop &
                     'backend-nczarr: data round-trip mismatch'
               end do
               call ppser_finalize()
               write (*, '(a)') 'preserf-fortran: backend-nczarr OK'
               stop
            end block
         else if (scenario == 'backend-bad') then
            ! Slice E: an unrecognised backend must abort at the
            ! ppser_initialize boundary, before any store is opened, with
            ! a clear message rather than a deep netCDF URL error.
            call ppser_initialize(out_dir, 'fbad', 'w', backend='zarr3')
            ! Unreachable: the backend allowlist must abort first.
            error stop &
               'preserf-test_minimal: unknown backend was accepted'
         else if (scenario == 'backend-nczarr-relpath') then
            ! Slice E: NCZarr's file:// URL needs an absolute directory.
            ! A relative directory must abort with a clear message rather
            ! than build a malformed file://<authority>/... URL that would
            ! silently target the wrong store.
            call ppser_initialize('relative_dir_not_absolute', 'frel', 'w', &
                                  backend='nczarr-v2')
            ! Unreachable: the absolute-directory guard must abort first.
            error stop &
               'preserf-test_minimal: relative nczarr directory was accepted'
         else if (scenario == 'read-roundtrip') then
            ! Slice A-1 Phase 1 + Phase 3: write a store, finalize, then
            ! re-open read-only and replay the same REGISTER / SAVEPOINT /
            ! METAINFO directives pp_ser emits outside the DATA-mode
            ! SELECT CASE. None of them may attempt an nf90_def_* on the
            ! read-only handle. Two savepoints exercise the read-side
            ! next_sp_index increment (sp_000000 → sp_000001).
            block
               real(real64) :: u_back(3)
               integer :: i
               call write_store(out_dir, 'frtrip', 100.0_real64)
               call ppser_initialize(out_dir, 'frtrip', 'r')
               if (ppser_get_mode() /= 1) error stop &
                  'read-roundtrip: ppser_initialize(..., "r") should set mode 1'
               ! Serializer + field metainfo / registry validation
               ! (all matching the written store).
               call fs_add_serializer_metainfo(ppser_serializer, 'author', &
                                               'fortran-test')
               call fs_register_field(ppser_serializer, 'u', 'double', &
                                      ppser_reallength, 3, 0, 0, 0, &
                                      1, 2, 0, 0, 0, 0, 0, 0)
               ! Savepoint 0 (sp_000000).
               call fs_create_savepoint('step', ppser_savepoint)
               if (ppser_savepoint%idx /= 0) error stop &
                  'read-roundtrip: first savepoint should resolve idx 0'
               call fs_add_savepoint_metainfo(ppser_savepoint, 'ntstep', 1_int32)
               call fs_add_savepoint_metainfo(ppser_savepoint, 't', 0.5_real64)
               call fs_read_field(ppser_serializer, ppser_savepoint, 'u', u_back)
               do i = 1, 3
                  if (u_back(i) /= 100.0_real64 + real(i, real64)) error stop &
                     'read-roundtrip: sp_000000 data round-trip mismatch'
               end do
               ! Savepoint 1 (sp_000001) — proves the index advanced.
               call fs_create_savepoint('step2', ppser_savepoint)
               if (ppser_savepoint%idx /= 1) error stop &
                  'read-roundtrip: second savepoint should resolve idx 1'
               call fs_add_savepoint_metainfo(ppser_savepoint, 'ntstep', 2_int32)
               call fs_read_field(ppser_serializer, ppser_savepoint, 'u', u_back)
               do i = 1, 3
                  if (u_back(i) /= 100.0_real64 + real(i + 3, real64)) error stop &
                     'read-roundtrip: sp_000001 data round-trip mismatch'
               end do
               call ppser_finalize()
               write (*, '(a)') 'preserf-fortran: read-roundtrip OK'
               stop
            end block
         else if (scenario == 'perturb-roundtrip') then
            ! Slice A-2: the 5-arg fs_read_field applies symmetric
            ! multiplicative noise data*(1 + scale*(2*r-1)) for every
            ! rank (1D / 2D / 3D). A non-zero scale must keep each element
            ! within [orig*(1-scale), orig*(1+scale)] and shift the field
            ! overall; a zero scale must leave the data bit-identical.
            block
               real(real64) :: u1(3), u1b(3)
               real(real64) :: u2(2, 2), u2b(2, 2)
               real(real64) :: u3(2, 2, 2), u3b(2, 2, 2)
               real(real64) :: dev
               integer :: i, j, k
               ! Distinct, strictly-positive fixtures so the relative
               ! bounds are unambiguous for every element.
               do i = 1, 3
                  u1(i) = 100.0_real64 + real(i, real64)
               end do
               do j = 1, 2
                  do i = 1, 2
                     u2(i, j) = 200.0_real64 + real(10*i + j, real64)
                  end do
               end do
               do k = 1, 2
                  do j = 1, 2
                     do i = 1, 2
                        u3(i, j, k) = 300.0_real64 + real(100*i + 10*j + k, real64)
                     end do
                  end do
               end do
               ! Write a store carrying one field of each rank.
               call ppser_initialize(out_dir, 'fpert', 'w')
               call fs_register_field(ppser_serializer, 'u1', 'double', &
                                      ppser_reallength, 3, 0, 0, 0, &
                                      0, 0, 0, 0, 0, 0, 0, 0)
               call fs_register_field(ppser_serializer, 'u2', 'double', &
                                      ppser_reallength, 2, 2, 0, 0, &
                                      0, 0, 0, 0, 0, 0, 0, 0)
               call fs_register_field(ppser_serializer, 'u3', 'double', &
                                      ppser_reallength, 2, 2, 2, 0, &
                                      0, 0, 0, 0, 0, 0, 0, 0)
               call fs_create_savepoint('step', ppser_savepoint)
               call fs_write_field(ppser_serializer, ppser_savepoint, 'u1', u1)
               call fs_write_field(ppser_serializer, ppser_savepoint, 'u2', u2)
               call fs_write_field(ppser_serializer, ppser_savepoint, 'u3', u3)
               call ppser_finalize()
               ! Re-open read-only and perturb-read every rank (scale 0.1).
               call ppser_initialize(out_dir, 'fpert', 'r')
               call fs_register_field(ppser_serializer, 'u1', 'double', &
                                      ppser_reallength, 3, 0, 0, 0, &
                                      0, 0, 0, 0, 0, 0, 0, 0)
               call fs_register_field(ppser_serializer, 'u2', 'double', &
                                      ppser_reallength, 2, 2, 0, 0, &
                                      0, 0, 0, 0, 0, 0, 0, 0)
               call fs_register_field(ppser_serializer, 'u3', 'double', &
                                      ppser_reallength, 2, 2, 2, 0, &
                                      0, 0, 0, 0, 0, 0, 0, 0)
               call fs_create_savepoint('step', ppser_savepoint)
               call fs_read_field(ppser_serializer, ppser_savepoint, 'u1', u1b, 0.1_real64)
               call fs_read_field(ppser_serializer, ppser_savepoint, 'u2', u2b, 0.1_real64)
               call fs_read_field(ppser_serializer, ppser_savepoint, 'u3', u3b, 0.1_real64)
               dev = 0.0_real64
               do i = 1, 3
                  if (u1b(i) < u1(i)*0.9_real64 .or. u1b(i) > u1(i)*1.1_real64) &
                     error stop 'perturb-roundtrip: 1d value out of bounds'
                  dev = dev + abs(u1b(i) - u1(i))
               end do
               do j = 1, 2
                  do i = 1, 2
                     if (u2b(i, j) < u2(i, j)*0.9_real64 .or. &
                         u2b(i, j) > u2(i, j)*1.1_real64) &
                        error stop 'perturb-roundtrip: 2d value out of bounds'
                     dev = dev + abs(u2b(i, j) - u2(i, j))
                  end do
               end do
               do k = 1, 2
                  do j = 1, 2
                     do i = 1, 2
                        if (u3b(i, j, k) < u3(i, j, k)*0.9_real64 .or. &
                            u3b(i, j, k) > u3(i, j, k)*1.1_real64) &
                           error stop 'perturb-roundtrip: 3d value out of bounds'
                        dev = dev + abs(u3b(i, j, k) - u3(i, j, k))
                     end do
                  end do
               end do
               if (dev <= 0.0_real64) error stop &
                  'perturb-roundtrip: scale 0.1 left data unchanged'
               ! Zero scale: identity across ranks (re-read same savepoint).
               call fs_read_field(ppser_serializer, ppser_savepoint, 'u1', u1b, 0.0_real64)
               call fs_read_field(ppser_serializer, ppser_savepoint, 'u2', u2b, 0.0_real64)
               call fs_read_field(ppser_serializer, ppser_savepoint, 'u3', u3b, 0.0_real64)
               do i = 1, 3
                  if (u1b(i) /= u1(i)) error stop &
                     'perturb-roundtrip: scale 0.0 should be identity (1d)'
               end do
               do j = 1, 2
                  do i = 1, 2
                     if (u2b(i, j) /= u2(i, j)) error stop &
                        'perturb-roundtrip: scale 0.0 should be identity (2d)'
                  end do
               end do
               do k = 1, 2
                  do j = 1, 2
                     do i = 1, 2
                        if (u3b(i, j, k) /= u3(i, j, k)) error stop &
                           'perturb-roundtrip: scale 0.0 should be identity (3d)'
                     end do
                  end do
               end do
               call ppser_finalize()
               write (*, '(a)') 'preserf-fortran: perturb-roundtrip OK'
               stop
            end block
         else if (scenario == 'read-ref') then
            ! Slice A-1 Phase 2: with an explicit directory_ref / prefix_ref
            ! the savepoint is resolved against the PRIMARY serializer (as
            ! pp_ser's SAVEPOINT directive does) but the read targets the
            ! REFERENCE serializer. The data must come from the reference
            ! file, not the primary — proving fs_read_field re-resolves the
            ! savepoint under its own serializer.
            block
               real(real64) :: u_back(3)
               integer :: i
               call write_store(out_dir, 'fprimary', 100.0_real64)
               call write_store(out_dir, 'fref', 200.0_real64)
               call ppser_initialize(out_dir, 'fprimary', 'r', &
                                     directory_ref=out_dir, prefix_ref='fref')
               if (ppser_serializer_ref%ncid == -1) error stop &
                  'read-ref: explicit ref should open ppser_serializer_ref'
               call fs_register_field(ppser_serializer, 'u', 'double', &
                                      ppser_reallength, 3, 0, 0, 0, &
                                      1, 2, 0, 0, 0, 0, 0, 0)
               call fs_create_savepoint('step', ppser_savepoint)
               call fs_read_field(ppser_serializer_ref, ppser_savepoint, 'u', &
                                  u_back)
               do i = 1, 3
                  if (u_back(i) /= 200.0_real64 + real(i, real64)) error stop &
                     'read-ref: read returned primary data, not reference data'
               end do
               call ppser_finalize()
               write (*, '(a)') 'preserf-fortran: read-ref OK'
               stop
            end block
         else if (scenario == 'read-bad-dtype') then
            call write_store(out_dir, 'fbdtype', 0.0_real64)
            call ppser_initialize(out_dir, 'fbdtype', 'r')
            ! 'float'/4 registers as type_id FLOAT32; the store has FLOAT64.
            call fs_register_field(ppser_serializer, 'u', 'float', 4, &
                                   3, 0, 0, 0, 1, 2, 0, 0, 0, 0, 0, 0)
            call abort_unexpected('read-bad-dtype')
         else if (scenario == 'read-bad-dims') then
            call write_store(out_dir, 'fbdims', 0.0_real64)
            call ppser_initialize(out_dir, 'fbdims', 'r')
            ! Size 4 instead of the registered size 3.
            call fs_register_field(ppser_serializer, 'u', 'double', &
                                   ppser_reallength, 4, 0, 0, 0, &
                                   1, 2, 0, 0, 0, 0, 0, 0)
            call abort_unexpected('read-bad-dims')
         else if (scenario == 'read-bad-halo') then
            call write_store(out_dir, 'fbhalo', 0.0_real64)
            call ppser_initialize(out_dir, 'fbhalo', 'r')
            ! iMinusHalo 9 instead of the registered 1.
            call fs_register_field(ppser_serializer, 'u', 'double', &
                                   ppser_reallength, 3, 0, 0, 0, &
                                   9, 2, 0, 0, 0, 0, 0, 0)
            call abort_unexpected('read-bad-halo')
         else if (scenario == 'read-bad-spname') then
            call write_store(out_dir, 'fbspn', 0.0_real64)
            call ppser_initialize(out_dir, 'fbspn', 'r')
            call fs_register_field(ppser_serializer, 'u', 'double', &
                                   ppser_reallength, 3, 0, 0, 0, &
                                   1, 2, 0, 0, 0, 0, 0, 0)
            ! Store's sp_000000 carries name 'step'.
            call fs_create_savepoint('wrongname', ppser_savepoint)
            call abort_unexpected('read-bad-spname')
         else if (scenario == 'read-bad-meta-value') then
            call write_store(out_dir, 'fbmval', 0.0_real64)
            call ppser_initialize(out_dir, 'fbmval', 'r')
            call fs_register_field(ppser_serializer, 'u', 'double', &
                                   ppser_reallength, 3, 0, 0, 0, &
                                   1, 2, 0, 0, 0, 0, 0, 0)
            call fs_create_savepoint('step', ppser_savepoint)
            ! Store has ntstep == 1.
            call fs_add_savepoint_metainfo(ppser_savepoint, 'ntstep', 999_int32)
            call abort_unexpected('read-bad-meta-value')
         else if (scenario == 'read-bad-meta-typeid') then
            call write_store(out_dir, 'fbmtid', 0.0_real64)
            call ppser_initialize(out_dir, 'fbmtid', 'r')
            call fs_register_field(ppser_serializer, 'u', 'double', &
                                   ppser_reallength, 3, 0, 0, 0, &
                                   1, 2, 0, 0, 0, 0, 0, 0)
            call fs_create_savepoint('step', ppser_savepoint)
            ! Store stored ntstep as Int32; replay as Float64 → type-id clash.
            call fs_add_savepoint_metainfo(ppser_savepoint, 'ntstep', 1.0_real64)
            call abort_unexpected('read-bad-meta-typeid')
         else if (scenario == 'read-bad-xtype') then
            ! Hand-build a store whose registry says FLOAT64 but whose
            ! savepoint variable is FLOAT32, so validate_field_shape passes
            ! and require_variable_xtype is the check that must reject it.
            call build_xtype_mismatch_store(trim(out_dir)//'/fbxtype.nc')
            call ppser_initialize(out_dir, 'fbxtype', 'r')
            call fs_register_field(ppser_serializer, 'u', 'double', &
                                   ppser_reallength, 3, 0, 0, 0, &
                                   0, 0, 0, 0, 0, 0, 0, 0)
            call fs_create_savepoint('step', ppser_savepoint)
            block
               real(real64) :: u_back(3)
               call fs_read_field(ppser_serializer, ppser_savepoint, 'u', u_back)
            end block
            call abort_unexpected('read-bad-xtype')
         else
            write (*, '(a,a)') &
               'preserf-test_minimal: unknown scenario argument: ', &
               scenario
            error stop 1
         end if
      end block
   end if

   allocate (u(ni, nj, nk), u_back(ni, nj, nk))
   do k = 1, nk
      do j = 1, nj
         do i = 1, ni
            ! Distinct, easy-to-decode value at each cell so the Python
            ! cross-check can verify the axis-order mapping precisely:
            !   value = 100*i + 10*j + k
            ! e.g. u(2,3,1) = 231, u(4,3,2) = 432.
            u(i, j, k) = real(100*i + 10*j + k, real64)
         end do
      end do
   end do

   ! 1-D field — exercises the fs_write_field_r8_1d /
   ! fs_read_field_r8_1d overload path and the rank-1 dim creation /
   ! reversal logic.
   allocate (v(nv), v_back(nv))
   do i = 1, nv
      v(i) = real(i, real64)
   end do

   ! 2-D field — exercises fs_write_field_r8_2d / fs_read_field_r8_2d.
   ! Same i*10 + j encoding as the 3-D case for axis-order verification.
   allocate (w(nw_i, nw_j), w_back(nw_i, nw_j))
   do j = 1, nw_j
      do i = 1, nw_i
         w(i, j) = real(10*i + j, real64)
      end do
   end do

   ! ---------------- write phase ----------------
   call ppser_initialize(out_dir, 'fhello', 'w')
   ! ppser_initialize sets ppser_mode_state from the open mode
   ! (`'w'` → 0), so pp_ser-generated SELECT CASE (ppser_get_mode())
   ! blocks pick the write branch by default. Verify the contract.
   if (ppser_get_mode() /= 0) error stop &
      'ppser_initialize(..., "w") should default mode to 0'

   call fs_add_serializer_metainfo(ppser_serializer, 'author', 'fortran-test')
   call fs_add_serializer_metainfo(ppser_serializer, 'schema_version', 7_int32)
   ! Exercise the Boolean → NF90_BYTE path so the test confirms the
   ! on-disk attribute type matches storage_mapping.md §1.
   call fs_add_serializer_metainfo(ppser_serializer, 'use_gpu', .true.)
   ! Exercise the Int64 and Float32 metainfo overloads — these kind-
   ! specific nf90_put_att branches are easy to break independently.
   call fs_add_serializer_metainfo(ppser_serializer, &
                                   'wallclock_ns', 1700000000000000000_int64)
   call fs_add_serializer_metainfo(ppser_serializer, &
                                   'tolerance32', 1.0e-3_real32)

   ! Non-zero halos on u exercise the put_halo_attr path; the helper
   ! emits each non-zero halo as a named attribute on the registry
   ! variable. Only the halos for the active rank get written
   ! (storage_mapping.md §4): iminushalo, iplushalo for axis i;
   ! jminushalo, jplushalo for axis j; kminushalo, kplushalo for k.
   call fs_register_field(ppser_serializer, 'u', 'double', ppser_reallength, &
                          ni, nj, nk, 0, &
                          1, 2, 3, 4, 0, 5, 0, 0)
   call fs_register_field(ppser_serializer, 'v', 'double', ppser_reallength, &
                          nv, 0, 0, 0, &
                          0, 0, 0, 0, 0, 0, 0, 0)
   call fs_register_field(ppser_serializer, 'w', 'double', ppser_reallength, &
                          nw_i, nw_j, 0, 0, &
                          0, 0, 0, 0, 0, 0, 0, 0)

   ! Use the two-argument fs_create_savepoint form pp_ser actually
   ! emits — relies on the default-serializer branch updating the
   ! module-level ppser_savepoint via ppser_serializer.
   call fs_create_savepoint('step', ppser_savepoint)
   call fs_add_savepoint_metainfo(ppser_savepoint, 'ntstep', 1_int32)
   call fs_add_savepoint_metainfo(ppser_savepoint, 't', 0.5_real64)
   call fs_write_field(ppser_serializer, ppser_savepoint, 'u', u)
   call fs_write_field(ppser_serializer, ppser_savepoint, 'v', v)
   call fs_write_field(ppser_serializer, ppser_savepoint, 'w', w)

   ! ---------------- ON / OFF gate exercise ----------------
   ! Disable serialization, attempt fs_* operations that would
   ! otherwise mutate the store, then re-enable. The Python pytest
   ! verifies that nothing was written while disabled (no
   ! `disabled_field` in /_fields, no `disabled_meta` attribute on
   ! root).
   if (.not. fs_serialization_status()) error stop &
      'fs_serialization_status() should be .true. by default'
   block
      integer :: grpid_before, idx_before
      grpid_before = ppser_savepoint%grpid
      idx_before = ppser_savepoint%idx
      call fs_disable_serialization()
      if (fs_serialization_status()) error stop &
         'fs_serialization_status() should be .false. after fs_disable_serialization'
      call fs_register_field(ppser_serializer, 'disabled_field', 'double', &
                             ppser_reallength, 1, 0, 0, 0, &
                             0, 0, 0, 0, 0, 0, 0, 0)
      call fs_add_serializer_metainfo(ppser_serializer, 'disabled_meta', 42_int32)
      ! fs_create_savepoint must be a true no-op when disabled: it
      ! MUST NOT clobber the caller's ppser_savepoint to -1.
      call fs_create_savepoint('would_be_step', ppser_savepoint)
      if (ppser_savepoint%grpid /= grpid_before .or. &
          ppser_savepoint%idx /= idx_before) then
         error stop &
            'fs_create_savepoint clobbered savepoint while disabled'
      end if
      ! fs_write_field (the DATA path) must also be a true no-op when
      ! disabled: writing a -999 sentinel into the already-populated
      ! `u` savepoint variable MUST leave the on-disk data untouched.
      ! The Python test asserts the sentinel never reached disk; the
      ! maxdiff round-trip check at the end of this program would also
      ! flag a leak. Without this call, a regression that dropped the
      ! `serialisation_enabled` early return from fs_write_field would
      ! go unnoticed.
      u_back = -999.0_real64
      call fs_write_field(ppser_serializer, ppser_savepoint, 'u', u_back)
      ! fs_read_field (the DATA read path) must likewise be a true
      ! no-op when disabled. Its `data` argument is intent(inout), so
      ! the early return leaves the caller's buffer intact: fill
      ! u_back with a -777 sentinel, attempt a disabled read, and
      ! confirm nothing was overwritten. A regression dropping the
      ! `serialisation_enabled` early return from the read overloads
      ! would clobber the sentinel here.
      u_back = -777.0_real64
      call fs_read_field(ppser_serializer, ppser_savepoint, 'u', u_back)
      if (any(u_back /= -777.0_real64)) error stop &
         'fs_read_field was not a no-op while serialization was disabled'
      call fs_enable_serialization()
      if (.not. fs_serialization_status()) error stop &
         'fs_serialization_status() should be .true. after fs_enable_serialization'
   end block

   call ppser_finalize()

   ! ---------------- read phase ----------------
   ! Disable the gate AFTER ppser_finalize. ppser_finalize itself
   ! resets `serialisation_enabled` to 1, so disabling *before* it
   ! would leave the flag already enabled going into the init below
   ! and prove nothing about ppser_initialize. Disabling here —
   ! between finalize and the fresh init — means the flag is 0 on
   ! entry to ppser_initialize, so the assertion isolates
   ! ppser_initialize's own reset path: without that reset the stale
   ! disabled SAVE state would silently no-op every fs_* call in the
   ! read phase.
   call fs_disable_serialization()
   call ppser_initialize(out_dir, 'fhello', 'r')
   if (.not. fs_serialization_status()) error stop &
      'ppser_initialize should reset serialisation_enabled on a fresh session'
   ! And `'r'` → 1, so pp_ser DATA blocks pick the read branch
   ! without an explicit ppser_set_mode call.
   if (ppser_get_mode() /= 1) error stop &
      'ppser_initialize(..., "r") should default mode to 1'
   ! pp_ser-generated read DATA branches call
   ! `fs_read_field(ppser_serializer_ref, ppser_savepoint, ...)`,
   ! so read through `ppser_serializer_ref` here to exercise the
   ! ref-serializer setup in ppser_initialize(..., 'r'). The
   ! savepoint group must be resolved under the ref serializer's
   ! own ncid (HDF5 returns distinct grpids per open even for the
   ! same on-disk file).
   if (ppser_serializer_ref%ncid == -1) error stop &
      'ppser_initialize(..., "r") should also open ppser_serializer_ref'
   block
      use netcdf
      integer :: ncerr, sps_grpid, sp_grpid
      ncerr = nf90_inq_ncid(ppser_serializer_ref%ncid, &
                            'savepoints', sps_grpid)
      if (ncerr /= 0) error stop 'inq_ncid savepoints (ref) failed'
      ncerr = nf90_inq_ncid(sps_grpid, 'sp_000000', sp_grpid)
      if (ncerr /= 0) error stop 'inq_ncid sp_000000 (ref) failed'
      ppser_savepoint%grpid = sp_grpid
      ppser_savepoint%idx = 0
   end block
   call fs_read_field(ppser_serializer_ref, ppser_savepoint, 'u', u_back)
   call fs_read_field(ppser_serializer_ref, ppser_savepoint, 'v', v_back)
   call fs_read_field(ppser_serializer_ref, ppser_savepoint, 'w', w_back)

   ! Compile-only resolution check for the 5-argument fs_read_field
   ! perturb form (pp_ser-generated CASE(2) branches). Wrapped in
   ! `if (.false.)` so the runtime never reaches
   ! `read_perturb_not_implemented`; the call existing in source is
   ! enough to verify the generic interface continues to resolve the
   ! 5-argument signature.
   if (.false.) then
      call fs_read_field(ppser_serializer_ref, ppser_savepoint, 'u', &
                         u_back, 1.0e-3_real64)
      call fs_read_field(ppser_serializer_ref, ppser_savepoint, 'v', &
                         v_back, 1.0e-3_real64)
      call fs_read_field(ppser_serializer_ref, ppser_savepoint, 'w', &
                         w_back, 1.0e-3_real64)
   end if

   call ppser_finalize()

   ! ---------------- explicit-reference read ----------------
   ! Re-open read-only, this time passing an *explicit* directory_ref
   ! / prefix_ref pair (here pointing back at the same store). This
   ! exercises the branch in ppser_initialize that opens the reference
   ! serializer from explicit arguments rather than implicitly from
   ! the main directory/prefix. pp_ser-generated read DATA branches
   ! call fs_read_field(ppser_serializer_ref, ...), so the explicitly
   ! opened reference serializer must resolve the savepoint and field
   ! exactly like the implicit-reference case above.
   block
      use netcdf
      integer :: ncerr, sps_grpid, sp_grpid
      real(real64), allocatable :: u_ref(:, :, :)
      allocate (u_ref(ni, nj, nk))
      call ppser_initialize(out_dir, 'fhello', 'r', &
                            directory_ref=out_dir, prefix_ref='fhello')
      if (ppser_serializer_ref%ncid == -1) error stop &
         'explicit directory_ref/prefix_ref should open ppser_serializer_ref'
      ncerr = nf90_inq_ncid(ppser_serializer_ref%ncid, &
                            'savepoints', sps_grpid)
      if (ncerr /= 0) error stop 'inq_ncid savepoints (explicit ref) failed'
      ncerr = nf90_inq_ncid(sps_grpid, 'sp_000000', sp_grpid)
      if (ncerr /= 0) error stop 'inq_ncid sp_000000 (explicit ref) failed'
      ppser_savepoint%grpid = sp_grpid
      ppser_savepoint%idx = 0
      call fs_read_field(ppser_serializer_ref, ppser_savepoint, 'u', u_ref)
      if (maxval(abs(u - u_ref)) /= 0.0_real64) error stop &
         'explicit-reference read returned wrong data for u'
      call ppser_finalize()
   end block

   maxdiff = max( &
             maxval(abs(u - u_back)), &
             maxval(abs(v - v_back)), &
             maxval(abs(w - w_back)))
   if (maxdiff /= 0.0_real64) then
      write (*, '(a,es14.6)') 'preserf-fortran: round-trip mismatch, maxdiff=', &
         maxdiff
      error stop 1
   end if

   write (*, '(a)') 'preserf-fortran: hello-world OK'

contains

   !> Delete a file if it exists. The init-keywords scenario uses this
   !> to clear stores left behind by a prior run before asserting on
   !> store names, since the ctest output dir is reused, not cleaned.
   subroutine delete_if_exists(path)
      character(len=*), intent(in) :: path
      logical :: exists
      integer :: unit, ios
      inquire (file=path, exist=exists)
      if (.not. exists) return
      open (newunit=unit, file=path, status='old', iostat=ios)
      if (ios == 0) close (unit, status='delete')
   end subroutine delete_if_exists

   !> Write a small two-savepoint store used by the read-mode scenarios.
   !> Field `u` (1-D, size 3, iMinusHalo=1 / iPlusHalo=2) is written into
   !> savepoint 'step' (values base+1..3) and savepoint 'step2'
   !> (values base+4..6), each with a savepoint metainfo pair. The
   !> distinct `base` lets the read-ref scenario tell the primary and
   !> reference stores apart.
   subroutine write_store(out_dir, prefix, base)
      character(len=*), intent(in) :: out_dir, prefix
      real(real64), intent(in) :: base
      real(real64) :: u1(3), u2(3)
      integer :: i
      do i = 1, 3
         u1(i) = base + real(i, real64)
         u2(i) = base + real(i + 3, real64)
      end do
      call ppser_initialize(out_dir, prefix, 'w')
      call fs_add_serializer_metainfo(ppser_serializer, 'author', 'fortran-test')
      call fs_register_field(ppser_serializer, 'u', 'double', ppser_reallength, &
                             3, 0, 0, 0, 1, 2, 0, 0, 0, 0, 0, 0)
      call fs_create_savepoint('step', ppser_savepoint)
      call fs_add_savepoint_metainfo(ppser_savepoint, 'ntstep', 1_int32)
      call fs_add_savepoint_metainfo(ppser_savepoint, 't', 0.5_real64)
      call fs_write_field(ppser_serializer, ppser_savepoint, 'u', u1)
      call fs_create_savepoint('step2', ppser_savepoint)
      call fs_add_savepoint_metainfo(ppser_savepoint, 'ntstep', 2_int32)
      call fs_write_field(ppser_serializer, ppser_savepoint, 'u', u2)
      call ppser_finalize()
   end subroutine write_store

   !> Build, with raw netCDF calls, a schema-valid store whose `/_fields/u`
   !> registry records type_id FLOAT64 and dims [3] but whose
   !> savepoints/sp_000000/u variable is NF90_FLOAT. This is the one
   !> registry/variable inconsistency that validate_field_shape (which
   !> only checks the registry) cannot catch, so it isolates the
   !> read-side require_variable_xtype rejection.
   subroutine build_xtype_mismatch_store(path)
      use netcdf
      character(len=*), intent(in) :: path
      integer :: ncid, fgid, vid, spsid, spid, dimid, uvid
      integer(int32) :: schema, tid_f64, idx0, dimsvec(1)
      real(real32) :: vals(3)

      schema = 1_int32        ! PRESERF_SCHEMA_VERSION
      tid_f64 = 5_int32       ! TID_FLOAT64
      idx0 = 0_int32
      dimsvec = [3_int32]
      vals = [1.0_real32, 2.0_real32, 3.0_real32]

      call nc_must(nf90_create(path, NF90_NETCDF4, ncid), 'nf90_create')
      call nc_must(nf90_put_att(ncid, NF90_GLOBAL, '_preserf_schema_version', &
                                schema), 'put_att _preserf_schema_version')
      ! Registry carrier variable with type_id + dims attributes.
      call nc_must(nf90_def_grp(ncid, '_fields', fgid), 'def_grp _fields')
      call nc_must(nf90_def_var(fgid, 'u', NF90_INT, vid), 'def_var /_fields/u')
      call nc_must(nf90_put_att(fgid, vid, 'type_id', tid_f64), 'put_att type_id')
      call nc_must(nf90_put_att(fgid, vid, 'dims', dimsvec), 'put_att dims')
      ! Savepoint group with a FLOAT32 data variable (the inconsistency).
      call nc_must(nf90_def_grp(ncid, 'savepoints', spsid), 'def_grp savepoints')
      call nc_must(nf90_def_grp(spsid, 'sp_000000', spid), 'def_grp sp_000000')
      call nc_must(nf90_put_att(spid, NF90_GLOBAL, '_preserf_savepoint_index', &
                                idx0), 'put_att _preserf_savepoint_index')
      call nc_must(nf90_put_att(spid, NF90_GLOBAL, 'name', 'step'), 'put_att name')
      call nc_must(nf90_def_dim(spid, 'u_dim0', 3, dimid), 'def_dim u_dim0')
      call nc_must(nf90_def_var(spid, 'u', NF90_FLOAT, [dimid], uvid), &
                   'def_var sp_000000/u (float32)')
      ! NETCDF4/HDF5 lets data and define operations interleave, so the
      ! put_var below would succeed without this — but commit the
      ! definitions explicitly so the test does not depend on that
      ! behaviour (PR #22 review note).
      call nc_must(nf90_enddef(ncid), 'enddef')
      call nc_must(nf90_put_var(spid, uvid, vals), 'put_var sp_000000/u')
      call nc_must(nf90_close(ncid), 'nf90_close')
   end subroutine build_xtype_mismatch_store

   !> Abort the test build if a raw netCDF call in
   !> build_xtype_mismatch_store failed. Unchecked errors there could
   !> leave a malformed store that makes the read-bad-xtype negative
   !> test pass for the wrong reason (PR #22 review note).
   subroutine nc_must(ncerr, what)
      use netcdf, only: nf90_noerr, nf90_strerror
      integer, intent(in) :: ncerr
      character(len=*), intent(in) :: what
      if (ncerr /= nf90_noerr) then
         write (*, '(a,a,a,a)') 'build_xtype_mismatch_store: ', trim(what), &
            ' failed: ', trim(nf90_strerror(ncerr))
         error stop 1
      end if
   end subroutine nc_must

   !> Print a non-matching marker and exit 0 when a read-mode validation
   !> directive was expected to abort but returned instead. The negative
   !> ctest scenarios use PASS_REGULAR_EXPRESSION on the specific abort
   !> message, so a clean exit with this (non-matching) line fails the
   !> test — exactly what we want if validation silently accepts.
   subroutine abort_unexpected(name)
      character(len=*), intent(in) :: name
      write (*, '(a,a,a)') 'preserf-test_minimal: scenario ', trim(name), &
         ' did not abort as expected'
      stop
   end subroutine abort_unexpected

end program test_minimal
