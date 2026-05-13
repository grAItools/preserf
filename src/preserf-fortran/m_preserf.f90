!> preserf Fortran helper: serialisation operations.
!>
!> This module exposes the `fs_*` API that `pp_ser`-expanded directives
!> emit. The on-disk layout is the group-per-savepoint schema documented
!> in `development/references/storage_mapping.md`.
!>
!> v0.1 covers the directives needed for a hello-world flow:
!>   * `fs_register_field` — REGISTER directive
!>   * `fs_create_savepoint` — SAVEPOINT directive (without metainfo args)
!>   * `fs_add_savepoint_metainfo` — SAVEPOINT key=value pairs (scalars)
!>   * `fs_add_serializer_metainfo` — METAINFO directive (scalars)
!>   * `fs_write_field` / `fs_read_field` — DATA directive
!>                                          (real(real64), 1D / 2D / 3D)
!>   * `fs_enable_serialization` / `fs_disable_serialization` — ON / OFF
!>
!> Other directives (DATA_KBUFF, OPTION, TRACER, ACCDATA, REGISTERTRACERS)
!> are out of scope for this PR and will land in follow-ups.
module m_preserf
    use, intrinsic :: iso_fortran_env, only: int8, int32, int64, real32, real64
    use netcdf
    use utils_preserf, only: t_serializer, t_savepoint, &
                             ppser_serializer, &
                             preserf_check_nf_with_msg, &
                             PRESERF_SAVEPOINT_INDEX_LIMIT
    implicit none
    private

    ! Serialbox TypeID values (storage_mapping.md §1).
    integer(int32), parameter :: TID_BOOLEAN = 1
    integer(int32), parameter :: TID_INT32   = 2
    integer(int32), parameter :: TID_INT64   = 3
    integer(int32), parameter :: TID_FLOAT32 = 4
    integer(int32), parameter :: TID_FLOAT64 = 5
    integer(int32), parameter :: TID_STRING  = 6

    integer, save :: serialisation_enabled = 1   ! 1 = enabled, 0 = disabled

    public :: fs_create_savepoint
    public :: fs_register_field
    public :: fs_enable_serialization
    public :: fs_disable_serialization
    public :: fs_serialization_status

    interface fs_add_savepoint_metainfo
        module procedure fs_add_savepoint_metainfo_l
        module procedure fs_add_savepoint_metainfo_i4
        module procedure fs_add_savepoint_metainfo_i8
        module procedure fs_add_savepoint_metainfo_r4
        module procedure fs_add_savepoint_metainfo_r8
        module procedure fs_add_savepoint_metainfo_s
    end interface
    public :: fs_add_savepoint_metainfo

    interface fs_add_serializer_metainfo
        module procedure fs_add_serializer_metainfo_l
        module procedure fs_add_serializer_metainfo_i4
        module procedure fs_add_serializer_metainfo_i8
        module procedure fs_add_serializer_metainfo_r4
        module procedure fs_add_serializer_metainfo_r8
        module procedure fs_add_serializer_metainfo_s
    end interface
    public :: fs_add_serializer_metainfo

    interface fs_write_field
        module procedure fs_write_field_r8_1d
        module procedure fs_write_field_r8_2d
        module procedure fs_write_field_r8_3d
    end interface
    public :: fs_write_field

    interface fs_read_field
        module procedure fs_read_field_r8_1d
        module procedure fs_read_field_r8_2d
        module procedure fs_read_field_r8_3d
    end interface
    public :: fs_read_field

contains

    ! ========================================================================
    ! ON / OFF
    !
    ! When `serialisation_enabled == 0`, every fs_* entry point below
    ! returns early before performing any I/O. This matches the contract
    ! pp_ser-expanded `!$SER ON` / `!$SER OFF` directives need: an OFF
    ! must make subsequent SAVEPOINT / DATA / METAINFO directives behave
    ! as no-ops at runtime.
    ! ========================================================================
    subroutine fs_enable_serialization()
        serialisation_enabled = 1
    end subroutine fs_enable_serialization

    subroutine fs_disable_serialization()
        serialisation_enabled = 0
    end subroutine fs_disable_serialization

    !> True iff fs_* I/O is currently enabled. Exposed so callers / tests
    !> can introspect the runtime state.
    function fs_serialization_status() result(enabled)
        logical :: enabled
        enabled = (serialisation_enabled /= 0)
    end function fs_serialization_status

    ! ========================================================================
    ! REGISTER
    ! ========================================================================
    !> Register a field's static metadata under `/_fields/<fieldname>`.
    !> Matches the call shape that pp_ser emits for the REGISTER directive
    !> (see directives_specification.md §3.10).
    subroutine fs_register_field(s, fieldname, datatype, bytes_per_element, &
                                 iSize, jSize, kSize, lSize, &
                                 iMinusHalo, iPlusHalo, &
                                 jMinusHalo, jPlusHalo, &
                                 kMinusHalo, kPlusHalo, &
                                 lMinusHalo, lPlusHalo)
        type(t_serializer), intent(inout) :: s
        character(len=*), intent(in) :: fieldname
        character(len=*), intent(in) :: datatype
        integer, intent(in) :: bytes_per_element
        integer, intent(in) :: iSize, jSize, kSize, lSize
        integer, intent(in) :: iMinusHalo, iPlusHalo
        integer, intent(in) :: jMinusHalo, jPlusHalo
        integer, intent(in) :: kMinusHalo, kPlusHalo
        integer, intent(in) :: lMinusHalo, lPlusHalo

        integer :: ncerr, varid
        integer(int32) :: type_id, zero
        integer(int32), allocatable :: dims(:)
        integer :: rank

        if (serialisation_enabled == 0) return
        if (s%fields_grpid == -1) then
            write (*, '(a)') 'preserf: fs_register_field called before ppser_initialize'
            error stop 1
        end if

        type_id = type_id_from_datatype(datatype, bytes_per_element)
        ! `dims` records the netCDF C-order shape (slowest-varying axis
        ! first). Fortran callers declare sizes in column-major order
        ! (iSize, jSize, kSize, lSize); the helper reverses them so a
        ! Python / netCDF-C reader sees `dims[0]` as the leading numpy
        ! axis. See storage_mapping.md §1 + §4.
        dims = active_dims_c_order(iSize, jSize, kSize, lSize)
        rank = size(dims)
        zero = 0_int32

        ! Create the dummy attribute-carrier scalar variable.
        ncerr = nf90_def_var(s%fields_grpid, trim(fieldname), NF90_INT, varid)
        call preserf_check_nf_with_msg(ncerr, &
            'def_var /_fields/'//trim(fieldname))
        ncerr = nf90_put_att(s%fields_grpid, varid, 'type_id', type_id)
        call preserf_check_nf_with_msg(ncerr, 'put_att type_id')
        ncerr = nf90_put_att(s%fields_grpid, varid, 'dims', dims)
        call preserf_check_nf_with_msg(ncerr, 'put_att dims')

        ! Emit only non-zero halos. storage_mapping.md §4 declares halos
        ! optional; readers MUST treat absence as "no information".
        if (rank >= 1) then
            call put_halo_attr(s%fields_grpid, varid, 'iminushalo', iMinusHalo)
            call put_halo_attr(s%fields_grpid, varid, 'iplushalo',  iPlusHalo)
        end if
        if (rank >= 2) then
            call put_halo_attr(s%fields_grpid, varid, 'jminushalo', jMinusHalo)
            call put_halo_attr(s%fields_grpid, varid, 'jplushalo',  jPlusHalo)
        end if
        if (rank >= 3) then
            call put_halo_attr(s%fields_grpid, varid, 'kminushalo', kMinusHalo)
            call put_halo_attr(s%fields_grpid, varid, 'kplushalo',  kPlusHalo)
        end if
        if (rank >= 4) then
            call put_halo_attr(s%fields_grpid, varid, 'lminushalo', lMinusHalo)
            call put_halo_attr(s%fields_grpid, varid, 'lplushalo',  lPlusHalo)
        end if

        ! Write the scalar value (0) so the variable has a representable payload.
        ncerr = nf90_put_var(s%fields_grpid, varid, zero)
        call preserf_check_nf_with_msg(ncerr, 'put_var (registry placeholder)')
    end subroutine fs_register_field

    ! ========================================================================
    ! SAVEPOINT
    ! ========================================================================
    !> Create a new savepoint group under `/savepoints/`. The group is
    !> named `sp_NNNNNN` (zero-padded six-digit index, per
    !> storage_mapping.md §5).
    subroutine fs_create_savepoint(name, savepoint, s)
        character(len=*), intent(in) :: name
        type(t_savepoint), intent(out) :: savepoint
        type(t_serializer), intent(inout), optional :: s
        type(t_serializer), pointer :: ser
        character(len=9) :: group_name
        integer :: ncerr
        integer(int32) :: idx_attr

        if (serialisation_enabled == 0) return
        ser => default_serializer(s)
        if (ser%savepoints_grpid == -1) then
            write (*, '(a)') 'preserf: fs_create_savepoint called before ppser_initialize'
            error stop 1
        end if
        if (ser%next_sp_index >= PRESERF_SAVEPOINT_INDEX_LIMIT) then
            write (*, '(a,i0)') 'preserf: savepoint index exceeds cap of ', &
                PRESERF_SAVEPOINT_INDEX_LIMIT
            error stop 1
        end if

        write (group_name, '("sp_",i6.6)') ser%next_sp_index
        ncerr = nf90_def_grp(ser%savepoints_grpid, group_name, savepoint%grpid)
        call preserf_check_nf_with_msg(ncerr, 'def_grp '//group_name)
        savepoint%idx = ser%next_sp_index

        idx_attr = int(ser%next_sp_index, int32)
        ncerr = nf90_put_att(savepoint%grpid, NF90_GLOBAL, &
                             '_preserf_savepoint_index', idx_attr)
        call preserf_check_nf_with_msg(ncerr, 'put_att _preserf_savepoint_index')
        ncerr = nf90_put_att(savepoint%grpid, NF90_GLOBAL, 'name', trim(name))
        call preserf_check_nf_with_msg(ncerr, 'put_att name')

        ser%next_sp_index = ser%next_sp_index + 1
    end subroutine fs_create_savepoint

    ! ========================================================================
    ! METAINFO — scalar overloads (savepoint)
    ! ========================================================================
    subroutine fs_add_savepoint_metainfo_l(sp, key, value)
        type(t_savepoint), intent(in) :: sp
        character(len=*), intent(in) :: key
        logical, intent(in) :: value
        integer(int8) :: stored
        stored = merge(1_int8, 0_int8, value)
        call put_typed_scalar_attr(sp%grpid, key, NF90_BYTE, &
                                   i8_val=stored, tid=TID_BOOLEAN)
    end subroutine

    subroutine fs_add_savepoint_metainfo_i4(sp, key, value)
        type(t_savepoint), intent(in) :: sp
        character(len=*), intent(in) :: key
        integer(int32), intent(in) :: value
        call put_typed_scalar_attr(sp%grpid, key, NF90_INT, &
                                   i32_val=value, tid=TID_INT32)
    end subroutine

    subroutine fs_add_savepoint_metainfo_i8(sp, key, value)
        type(t_savepoint), intent(in) :: sp
        character(len=*), intent(in) :: key
        integer(int64), intent(in) :: value
        call put_typed_scalar_attr(sp%grpid, key, NF90_INT64, &
                                   i64_val=value, tid=TID_INT64)
    end subroutine

    subroutine fs_add_savepoint_metainfo_r4(sp, key, value)
        type(t_savepoint), intent(in) :: sp
        character(len=*), intent(in) :: key
        real(real32), intent(in) :: value
        call put_typed_scalar_attr(sp%grpid, key, NF90_FLOAT, &
                                   r32_val=value, tid=TID_FLOAT32)
    end subroutine

    subroutine fs_add_savepoint_metainfo_r8(sp, key, value)
        type(t_savepoint), intent(in) :: sp
        character(len=*), intent(in) :: key
        real(real64), intent(in) :: value
        call put_typed_scalar_attr(sp%grpid, key, NF90_DOUBLE, &
                                   r64_val=value, tid=TID_FLOAT64)
    end subroutine

    subroutine fs_add_savepoint_metainfo_s(sp, key, value)
        type(t_savepoint), intent(in) :: sp
        character(len=*), intent(in) :: key
        character(len=*), intent(in) :: value
        call put_typed_scalar_attr(sp%grpid, key, NF90_STRING, &
                                   s_val=value, tid=TID_STRING)
    end subroutine

    ! ========================================================================
    ! METAINFO — scalar overloads (serializer / root group)
    ! ========================================================================
    subroutine fs_add_serializer_metainfo_l(s, key, value)
        type(t_serializer), intent(in) :: s
        character(len=*), intent(in) :: key
        logical, intent(in) :: value
        integer(int8) :: stored
        stored = merge(1_int8, 0_int8, value)
        call put_typed_scalar_attr(s%ncid, key, NF90_BYTE, &
                                   i8_val=stored, tid=TID_BOOLEAN)
    end subroutine

    subroutine fs_add_serializer_metainfo_i4(s, key, value)
        type(t_serializer), intent(in) :: s
        character(len=*), intent(in) :: key
        integer(int32), intent(in) :: value
        call put_typed_scalar_attr(s%ncid, key, NF90_INT, &
                                   i32_val=value, tid=TID_INT32)
    end subroutine

    subroutine fs_add_serializer_metainfo_i8(s, key, value)
        type(t_serializer), intent(in) :: s
        character(len=*), intent(in) :: key
        integer(int64), intent(in) :: value
        call put_typed_scalar_attr(s%ncid, key, NF90_INT64, &
                                   i64_val=value, tid=TID_INT64)
    end subroutine

    subroutine fs_add_serializer_metainfo_r4(s, key, value)
        type(t_serializer), intent(in) :: s
        character(len=*), intent(in) :: key
        real(real32), intent(in) :: value
        call put_typed_scalar_attr(s%ncid, key, NF90_FLOAT, &
                                   r32_val=value, tid=TID_FLOAT32)
    end subroutine

    subroutine fs_add_serializer_metainfo_r8(s, key, value)
        type(t_serializer), intent(in) :: s
        character(len=*), intent(in) :: key
        real(real64), intent(in) :: value
        call put_typed_scalar_attr(s%ncid, key, NF90_DOUBLE, &
                                   r64_val=value, tid=TID_FLOAT64)
    end subroutine

    subroutine fs_add_serializer_metainfo_s(s, key, value)
        type(t_serializer), intent(in) :: s
        character(len=*), intent(in) :: key
        character(len=*), intent(in) :: value
        call put_typed_scalar_attr(s%ncid, key, NF90_STRING, &
                                   s_val=value, tid=TID_STRING)
    end subroutine

    ! ========================================================================
    ! DATA — write
    !
    ! The `s` argument is accepted to keep the call shape pp_ser emits
    ! (`fs_write_field(ppser_serializer, ppser_savepoint, ...)`); the
    ! actual netCDF state we need lives on the savepoint's group. We
    ! validate that `s` has been initialised so callers get a clear
    ! error if they forgot `ppser_initialize`.
    ! ========================================================================
    subroutine fs_write_field_r8_1d(s, sp, fieldname, data)
        type(t_serializer), intent(inout) :: s
        type(t_savepoint),  intent(in) :: sp
        character(len=*),   intent(in) :: fieldname
        real(real64),       intent(in) :: data(:)
        integer :: ncerr, varid
        integer, allocatable :: dimids(:)

        if (serialisation_enabled == 0) return
        call require_open(s, 'fs_write_field')
        call ensure_dims(sp%grpid, fieldname, shape(data), dimids)
        call ensure_variable(sp%grpid, fieldname, NF90_DOUBLE, dimids, varid)
        ncerr = nf90_put_var(sp%grpid, varid, data)
        call preserf_check_nf_with_msg(ncerr, 'put_var '//trim(fieldname)//' (1d)')
    end subroutine

    subroutine fs_write_field_r8_2d(s, sp, fieldname, data)
        type(t_serializer), intent(inout) :: s
        type(t_savepoint),  intent(in) :: sp
        character(len=*),   intent(in) :: fieldname
        real(real64),       intent(in) :: data(:, :)
        integer :: ncerr, varid
        integer, allocatable :: dimids(:)

        if (serialisation_enabled == 0) return
        call require_open(s, 'fs_write_field')
        call ensure_dims(sp%grpid, fieldname, shape(data), dimids)
        call ensure_variable(sp%grpid, fieldname, NF90_DOUBLE, dimids, varid)
        ncerr = nf90_put_var(sp%grpid, varid, data)
        call preserf_check_nf_with_msg(ncerr, 'put_var '//trim(fieldname)//' (2d)')
    end subroutine

    subroutine fs_write_field_r8_3d(s, sp, fieldname, data)
        type(t_serializer), intent(inout) :: s
        type(t_savepoint),  intent(in) :: sp
        character(len=*),   intent(in) :: fieldname
        real(real64),       intent(in) :: data(:, :, :)
        integer :: ncerr, varid
        integer, allocatable :: dimids(:)

        if (serialisation_enabled == 0) return
        call require_open(s, 'fs_write_field')
        call ensure_dims(sp%grpid, fieldname, shape(data), dimids)
        call ensure_variable(sp%grpid, fieldname, NF90_DOUBLE, dimids, varid)
        ncerr = nf90_put_var(sp%grpid, varid, data)
        call preserf_check_nf_with_msg(ncerr, 'put_var '//trim(fieldname)//' (3d)')
    end subroutine

    ! ========================================================================
    ! DATA — read
    ! ========================================================================
    subroutine fs_read_field_r8_1d(s, sp, fieldname, data)
        type(t_serializer), intent(in) :: s
        type(t_savepoint),  intent(in) :: sp
        character(len=*),   intent(in) :: fieldname
        real(real64),       intent(out) :: data(:)
        integer :: ncerr, varid
        if (serialisation_enabled == 0) return
        call require_open(s, 'fs_read_field')
        ncerr = nf90_inq_varid(sp%grpid, trim(fieldname), varid)
        call preserf_check_nf_with_msg(ncerr, 'inq_varid '//trim(fieldname))
        ncerr = nf90_get_var(sp%grpid, varid, data)
        call preserf_check_nf_with_msg(ncerr, 'get_var '//trim(fieldname)//' (1d)')
    end subroutine

    subroutine fs_read_field_r8_2d(s, sp, fieldname, data)
        type(t_serializer), intent(in) :: s
        type(t_savepoint),  intent(in) :: sp
        character(len=*),   intent(in) :: fieldname
        real(real64),       intent(out) :: data(:, :)
        integer :: ncerr, varid
        if (serialisation_enabled == 0) return
        call require_open(s, 'fs_read_field')
        ncerr = nf90_inq_varid(sp%grpid, trim(fieldname), varid)
        call preserf_check_nf_with_msg(ncerr, 'inq_varid '//trim(fieldname))
        ncerr = nf90_get_var(sp%grpid, varid, data)
        call preserf_check_nf_with_msg(ncerr, 'get_var '//trim(fieldname)//' (2d)')
    end subroutine

    subroutine fs_read_field_r8_3d(s, sp, fieldname, data)
        type(t_serializer), intent(in) :: s
        type(t_savepoint),  intent(in) :: sp
        character(len=*),   intent(in) :: fieldname
        real(real64),       intent(out) :: data(:, :, :)
        integer :: ncerr, varid
        if (serialisation_enabled == 0) return
        call require_open(s, 'fs_read_field')
        ncerr = nf90_inq_varid(sp%grpid, trim(fieldname), varid)
        call preserf_check_nf_with_msg(ncerr, 'inq_varid '//trim(fieldname))
        ncerr = nf90_get_var(sp%grpid, varid, data)
        call preserf_check_nf_with_msg(ncerr, 'get_var '//trim(fieldname)//' (3d)')
    end subroutine

    ! ========================================================================
    ! Internal helpers
    ! ========================================================================

    function default_serializer(s) result(ser)
        type(t_serializer), target, intent(in), optional :: s
        type(t_serializer), pointer :: ser
        if (present(s)) then
            ser => s
        else
            ser => ppser_serializer
        end if
    end function default_serializer

    !> Map a Serialbox-style type string + element-byte-length to a TypeID.
    function type_id_from_datatype(datatype, bytes_per_element) result(tid)
        character(len=*), intent(in) :: datatype
        integer, intent(in) :: bytes_per_element
        integer(int32) :: tid
        character(len=:), allocatable :: lc

        lc = to_lower(trim(datatype))
        select case (lc)
        case ('bool', 'boolean', 'logical')
            tid = TID_BOOLEAN
        case ('int', 'integer')
            if (bytes_per_element == 8) then
                tid = TID_INT64
            else
                tid = TID_INT32
            end if
        case ('int64', 'long')
            tid = TID_INT64
        case ('float', 'single')
            tid = TID_FLOAT32
        case ('double')
            tid = TID_FLOAT64
        case ('real')
            if (bytes_per_element == 4) then
                tid = TID_FLOAT32
            else
                tid = TID_FLOAT64
            end if
        case ('string', 'character')
            tid = TID_STRING
        case default
            write (*, '(a,a)') 'preserf: unknown datatype string: ', trim(datatype)
            error stop 1
        end select
    end function type_id_from_datatype

    !> Build the active dims vector in netCDF C-order (slowest-varying
    !> axis first) from the Fortran-natural (iSize, jSize, kSize, lSize)
    !> tuple. The Fortran tuple convention (per directives_specification.md
    !> §3.10) is that non-zero sizes form a contiguous leading prefix:
    !> e.g. shortcut "K1" expands to `(ke1, 0, 0, 0)` and shortcut "IJ"
    !> expands to `(ie, je, 0, 0)`. A zero followed by a non-zero is an
    !> inconsistent shape and aborts the program rather than silently
    !> producing an invalid dims vector with embedded zeros.
    function active_dims_c_order(iSize, jSize, kSize, lSize) result(d)
        integer, intent(in) :: iSize, jSize, kSize, lSize
        integer(int32), allocatable :: d(:)
        integer :: rank

        ! Reject non-contiguous prefixes up front.
        if (jSize > 0 .and. iSize <= 0) call active_dims_inconsistent( &
            iSize, jSize, kSize, lSize)
        if (kSize > 0 .and. jSize <= 0) call active_dims_inconsistent( &
            iSize, jSize, kSize, lSize)
        if (lSize > 0 .and. kSize <= 0) call active_dims_inconsistent( &
            iSize, jSize, kSize, lSize)

        rank = 0
        if (iSize > 0) rank = 1
        if (jSize > 0) rank = 2
        if (kSize > 0) rank = 3
        if (lSize > 0) rank = 4
        allocate (d(rank))
        ! Reverse from Fortran column-major declaration order into
        ! C-order: leading dim = slowest-varying = last Fortran index.
        if (rank == 1) d(1) = int(iSize, int32)
        if (rank == 2) then
            d(1) = int(jSize, int32); d(2) = int(iSize, int32)
        end if
        if (rank == 3) then
            d(1) = int(kSize, int32); d(2) = int(jSize, int32); d(3) = int(iSize, int32)
        end if
        if (rank == 4) then
            d(1) = int(lSize, int32); d(2) = int(kSize, int32)
            d(3) = int(jSize, int32); d(4) = int(iSize, int32)
        end if
    end function active_dims_c_order

    subroutine active_dims_inconsistent(iSize, jSize, kSize, lSize)
        integer, intent(in) :: iSize, jSize, kSize, lSize
        write (*, '(a,4(i0,a))') &
            'preserf: inconsistent dim tuple (', &
            iSize, ',', jSize, ',', kSize, ',', lSize, &
            '); non-zero sizes must form a contiguous leading prefix'
        error stop 1
    end subroutine active_dims_inconsistent

    subroutine put_halo_attr(grpid, varid, name, value)
        integer, intent(in) :: grpid, varid
        character(len=*), intent(in) :: name
        integer, intent(in) :: value
        integer :: ncerr
        integer(int32) :: v
        if (value == 0) return
        v = int(value, int32)
        ncerr = nf90_put_att(grpid, varid, name, v)
        call preserf_check_nf_with_msg(ncerr, 'put_att '//name)
    end subroutine put_halo_attr

    !> Write a typed metainfo attribute as `<key>` plus its shadow
    !> `<key>__preserf_type_id` (storage_mapping.md §3.3). The attribute
    !> is attached as a group-level attribute on `grpid` — NF90_GLOBAL
    !> is the netCDF varid that means "attach to the group itself".
    !>
    !> Exactly one of i8_val / i32_val / i64_val / r32_val / r64_val /
    !> s_val must be supplied, matching `nc_type`. The kind of the
    !> Fortran argument passed to `nf90_put_att` controls the on-disk
    !> netCDF attribute type, which is why each Serialbox TypeID gets
    !> its own kind-correct path here:
    !>
    !>   * Boolean → int8           → NC_BYTE
    !>   * Int32   → int32          → NC_INT
    !>   * Int64   → int64          → NC_INT64
    !>   * Float32 → real32         → NC_FLOAT
    !>   * Float64 → real64         → NC_DOUBLE
    !>   * String  → character(*)   → NC_CHAR  (see note below)
    !>
    !> The netcdf-fortran 4.5.x F90 wrapper writes `character(*)` as
    !> NC_CHAR rather than NC_STRING; storage_mapping.md §1 documents
    !> this asymmetry with the Python writer (which produces NC_STRING).
    !> Both round-trip losslessly because the `__preserf_type_id` shadow
    !> attribute is the source of truth for the typed-value contract.
    subroutine put_typed_scalar_attr(grpid, key, nc_type, &
                                     tid, i8_val, i32_val, i64_val, &
                                     r32_val, r64_val, s_val)
        integer, intent(in) :: grpid
        character(len=*), intent(in) :: key
        integer, intent(in) :: nc_type
        integer(int32), intent(in) :: tid
        integer(int8),  intent(in), optional :: i8_val
        integer(int32), intent(in), optional :: i32_val
        integer(int64), intent(in), optional :: i64_val
        real(real32),   intent(in), optional :: r32_val
        real(real64),   intent(in), optional :: r64_val
        character(len=*), intent(in), optional :: s_val

        integer :: ncerr
        character(len=:), allocatable :: shadow

        if (serialisation_enabled == 0) return

        select case (nc_type)
        case (NF90_BYTE)
            ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, i8_val)
        case (NF90_INT)
            ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, i32_val)
        case (NF90_INT64)
            ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, i64_val)
        case (NF90_FLOAT)
            ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, r32_val)
        case (NF90_DOUBLE)
            ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, r64_val)
        case (NF90_STRING)
            ! See block comment above — this lands as NC_CHAR on disk
            ! under netcdf-fortran 4.5.x. Documented in
            ! storage_mapping.md §1.
            ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, trim(s_val))
        case default
            write (*, '(a,i0)') 'preserf: unsupported nc_type ', nc_type
            error stop 1
        end select
        call preserf_check_nf_with_msg(ncerr, 'put_att '//key)

        shadow = key // '__preserf_type_id'
        ncerr = nf90_put_att(grpid, NF90_GLOBAL, shadow, tid)
        call preserf_check_nf_with_msg(ncerr, 'put_att '//shadow)
    end subroutine put_typed_scalar_attr

    !> Ensure per-field dimensions exist on `grpid` and return their dim ids.
    !> Dimensions are named `<fieldname>_dim0`, `<fieldname>_dim1`, … and
    !> are created lazily inside the savepoint group (storage_mapping.md §6).
    subroutine ensure_dims(grpid, fieldname, shp, dimids)
        integer, intent(in) :: grpid
        character(len=*), intent(in) :: fieldname
        integer, intent(in) :: shp(:)
        integer, allocatable, intent(out) :: dimids(:)
        integer :: r, axis, ncerr
        character(len=:), allocatable :: dname
        character(len=8) :: axis_str

        r = size(shp)
        allocate (dimids(r))
        do axis = 1, r
            write (axis_str, '(i0)') axis - 1
            dname = trim(fieldname) // '_dim' // trim(axis_str)
            ncerr = nf90_inq_dimid(grpid, dname, dimids(axis))
            if (ncerr == NF90_EBADDIM) then
                ncerr = nf90_def_dim(grpid, dname, shp(axis), dimids(axis))
                call preserf_check_nf_with_msg(ncerr, 'def_dim '//dname)
            else
                call preserf_check_nf_with_msg(ncerr, 'inq_dimid '//dname)
            end if
        end do
    end subroutine ensure_dims

    subroutine ensure_variable(grpid, fieldname, nc_type, dimids, varid)
        integer, intent(in) :: grpid
        character(len=*), intent(in) :: fieldname
        integer, intent(in) :: nc_type
        integer, intent(in) :: dimids(:)
        integer, intent(out) :: varid
        integer :: ncerr

        ncerr = nf90_inq_varid(grpid, trim(fieldname), varid)
        if (ncerr == NF90_ENOTVAR) then
            ncerr = nf90_def_var(grpid, trim(fieldname), nc_type, dimids, varid)
            call preserf_check_nf_with_msg(ncerr, 'def_var '//trim(fieldname))
        else
            call preserf_check_nf_with_msg(ncerr, 'inq_varid '//trim(fieldname))
        end if
    end subroutine ensure_variable

    !> Abort with a clear message if the serializer hasn't been opened.
    subroutine require_open(s, where)
        type(t_serializer), intent(in) :: s
        character(len=*), intent(in) :: where
        if (s%ncid == -1) then
            write (*, '(a,a,a)') 'preserf: ', trim(where), &
                ' called before ppser_initialize'
            error stop 1
        end if
    end subroutine require_open

    pure function to_lower(s) result(r)
        character(len=*), intent(in) :: s
        character(len=len(s)) :: r
        integer :: i, c
        do i = 1, len(s)
            c = iachar(s(i:i))
            if (c >= iachar('A') .and. c <= iachar('Z')) then
                r(i:i) = achar(c + 32)
            else
                r(i:i) = s(i:i)
            end if
        end do
    end function to_lower

end module m_preserf
