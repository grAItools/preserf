!> Minimal end-to-end exercise of the preserf Fortran helper API.
!>
!> Writes one savepoint with a single 3-D real(real64) field plus a
!> selection of serializer / savepoint metainfo entries, then re-opens
!> the store and reads the field back.
!>
!> The Python test in tests/test_fortran_minimal.py runs this binary
!> and validates the resulting store via tests/_storage.py.
program test_minimal
    use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
    use utils_preserf
    use m_preserf
    implicit none

    character(len=:), allocatable :: out_dir
    character(len=1024) :: arg_buf
    integer :: arg_len
    real(real64), allocatable :: u(:, :, :), u_back(:, :, :)
    integer, parameter :: ni = 4, nj = 3, nk = 2
    integer :: i, j, k
    real(real64) :: maxdiff
    type(t_savepoint) :: sp

    if (command_argument_count() < 1) then
        write (*, '(a)') 'usage: test_minimal <output_dir>'
        error stop 1
    end if
    call get_command_argument(1, arg_buf, arg_len)
    out_dir = arg_buf(1:arg_len)
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

    ! ---------------- write phase ----------------
    call ppser_initialize(out_dir, 'fhello', 'w')
    call ppser_set_mode(0)

    call fs_add_serializer_metainfo(ppser_serializer, 'author', 'fortran-test')
    call fs_add_serializer_metainfo(ppser_serializer, 'schema_version', 7_int32)
    ! Exercise the Boolean → NF90_BYTE path so the test confirms the
    ! on-disk attribute type matches storage_mapping.md §1.
    call fs_add_serializer_metainfo(ppser_serializer, 'use_gpu', .true.)

    call fs_register_field(ppser_serializer, 'u', 'double', ppser_reallength, &
                           ni, nj, nk, 0, &
                           0, 0, 0, 0, 0, 0, 0, 0)

    call fs_create_savepoint('step', sp, ppser_serializer)
    call fs_add_savepoint_metainfo(sp, 'ntstep', 1_int32)
    call fs_add_savepoint_metainfo(sp, 't', 0.5_real64)
    call fs_write_field(ppser_serializer, sp, 'u', u)
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
    call ppser_finalize()

    maxdiff = maxval(abs(u - u_back))
    if (maxdiff /= 0.0_real64) then
        write (*, '(a,es14.6)') 'preserf-fortran: round-trip mismatch, maxdiff=', &
            maxdiff
        error stop 1
    end if

    write (*, '(a)') 'preserf-fortran: hello-world OK'

end program test_minimal
