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
!> The Python test in tests/test_fortran_minimal.py runs this binary
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
    type(t_savepoint) :: sp

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
    call ppser_set_mode(0)

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

    call fs_create_savepoint('step', sp, ppser_serializer)
    call fs_add_savepoint_metainfo(sp, 'ntstep', 1_int32)
    call fs_add_savepoint_metainfo(sp, 't', 0.5_real64)
    call fs_write_field(ppser_serializer, sp, 'u', u)
    call fs_write_field(ppser_serializer, sp, 'v', v)
    call fs_write_field(ppser_serializer, sp, 'w', w)
    call ppser_finalize()

    ! ---------------- read phase ----------------
    call ppser_initialize(out_dir, 'fhello', 'r')
    call ppser_set_mode(1)
    ! In a real pp_ser flow ppser_savepoint would be populated by
    ! fs_create_savepoint on the reference serializer. For this minimal
    ! exercise we look up the savepoint group directly by name.
    block
        use netcdf
        integer :: ncerr, sps_grpid, sp_grpid
        ncerr = nf90_inq_ncid(ppser_serializer%ncid, 'savepoints', sps_grpid)
        if (ncerr /= 0) error stop 'inq_ncid savepoints failed'
        ncerr = nf90_inq_ncid(sps_grpid, 'sp_000000', sp_grpid)
        if (ncerr /= 0) error stop 'inq_ncid sp_000000 failed'
        sp%grpid = sp_grpid
        sp%idx = 0
    end block
    call fs_read_field(ppser_serializer, sp, 'u', u_back)
    call fs_read_field(ppser_serializer, sp, 'v', v_back)
    call fs_read_field(ppser_serializer, sp, 'w', w_back)
    call ppser_finalize()

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
