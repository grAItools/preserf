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

end program test_minimal
