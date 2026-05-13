!> preserf Fortran helper: serializer / savepoint state + lifecycle.
!>
!> This module owns the global state that `pp_ser`-expanded directives
!> rely on (`ppser_serializer`, `ppser_serializer_ref`, `ppser_savepoint`,
!> `ppser_realtype`, `ppser_zrperturb`, plus the mode getter/setter).
!>
!> The actual netCDF / NCZarr operations live in m_preserf; this module
!> only handles dataset open/close and mode state.
!>
!> Backed by the schema documented in
!> `development/references/storage_mapping.md`.
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
    type, public :: t_savepoint
        integer :: grpid = -1
        integer :: idx = -1
    end type t_savepoint

    ! -------------------------------------------------------------------------
    ! Module-level state (mirrors Serialbox's utils_ppser surface)
    ! -------------------------------------------------------------------------
    type(t_serializer), public, save, target :: ppser_serializer
    type(t_serializer), public, save, target :: ppser_serializer_ref
    type(t_savepoint),  public, save :: ppser_savepoint

    integer(int32), parameter, public :: ppser_intlength  = 4
    integer(int32), parameter, public :: ppser_reallength = 8
    character(len=*), parameter, public :: ppser_realtype = 'double'
    real(real64), public, save :: ppser_zrperturb = 0.0_real64

    ! Mode: 0 = write, 1 = read, 2 = read-perturb.
    integer, save :: ppser_mode_state = 0

    ! Schema version written into _preserf_schema_version. Must match
    ! tests/_storage.py SCHEMA_VERSION.
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
        character(len=:), allocatable :: s
        s = 'preserf 0.1.0'
    end function preserf_writer_version

    !> Initialise the global serializer (and optionally a read-reference
    !> serializer) by opening a netCDF / NCZarr dataset under `directory`
    !> with name `prefix`.
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
    subroutine ppser_initialize(directory, prefix, mode, &
                                directory_ref, prefix_ref)
        character(len=*), intent(in) :: directory
        character(len=*), intent(in) :: prefix
        character(len=*), intent(in) :: mode
        character(len=*), intent(in), optional :: directory_ref
        character(len=*), intent(in), optional :: prefix_ref

        ! Validate optional-argument coherence BEFORE creating/truncating
        ! the main store, so a partial-arg mistake doesn't trash an
        ! existing target file.
        if (present(directory_ref) .neqv. present(prefix_ref)) then
            write (*, '(a)') 'preserf: ppser_initialize requires either both '//&
                'directory_ref and prefix_ref, or neither'
            error stop 1
        end if

        call preserf_open_serializer(ppser_serializer, directory, prefix, mode)

        if (present(directory_ref) .and. present(prefix_ref)) then
            call preserf_open_serializer(ppser_serializer_ref, &
                                         directory_ref, prefix_ref, 'r')
        else if (mode == 'r' .or. mode == 'R') then
            ! pp_ser-generated read/read-perturb DATA branches call
            ! `fs_read_field(ppser_serializer_ref, ...)`. In a plain
            ! read-mode init without explicit reference args, point the
            ! ref serializer at the same store so those branches just
            ! work. Both serializers open their own netCDF handle to
            ! the same on-disk file (HDF5 allows multiple read-only
            ! opens).
            call preserf_open_serializer(ppser_serializer_ref, &
                                         directory, prefix, 'r')
        end if
    end subroutine ppser_initialize

    !> Close the dataset(s) opened by ppser_initialize.
    subroutine ppser_finalize()
        call preserf_close_serializer(ppser_serializer)
        call preserf_close_serializer(ppser_serializer_ref)
        ppser_savepoint%grpid = -1
        ppser_savepoint%idx = -1
        ppser_mode_state = 0
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
                ') is out of range; expected 0 (write), 1 (read), '//&
                'or 2 (read-perturb)'
            error stop 1
        end if
        ppser_mode_state = m
    end subroutine ppser_set_mode

    ! -------------------------------------------------------------------------
    ! Internal helpers
    ! -------------------------------------------------------------------------

    subroutine preserf_open_serializer(s, directory, prefix, mode)
        type(t_serializer), intent(inout) :: s
        character(len=*), intent(in) :: directory
        character(len=*), intent(in) :: prefix
        character(len=*), intent(in) :: mode

        character(len=:), allocatable :: path
        integer :: ncerr, version

        path = trim(directory) // '/' // trim(prefix) // '.nc'

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
                'preserf: append mode (a) is not yet supported in v0.1; '//&
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
