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
                            PRESERF_SAVEPOINT_INDEX_LIMIT, &
                            serialisation_enabled
   implicit none
   private

   ! Serialbox TypeID values (storage_mapping.md §1).
   integer(int32), parameter :: TID_BOOLEAN = 1
   integer(int32), parameter :: TID_INT32 = 2
   integer(int32), parameter :: TID_INT64 = 3
   integer(int32), parameter :: TID_FLOAT32 = 4
   integer(int32), parameter :: TID_FLOAT64 = 5
   integer(int32), parameter :: TID_STRING = 6

   ! `serialisation_enabled` is owned by utils_preserf (so that
   ! ppser_initialize can reset it on a fresh session); imported via
   ! the `use utils_preserf, only: ...` at the module top.

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
      module procedure fs_read_field_r8_1d_perturb
      module procedure fs_read_field_r8_2d_perturb
      module procedure fs_read_field_r8_3d_perturb
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
      zero = 0_int32

      ! Create the dummy attribute-carrier scalar variable.
      ncerr = nf90_def_var(s%fields_grpid, trim(fieldname), NF90_INT, varid)
      call preserf_check_nf_with_msg(ncerr, &
                                     'def_var /_fields/'//trim(fieldname))
      ncerr = nf90_put_att(s%fields_grpid, varid, 'type_id', type_id)
      call preserf_check_nf_with_msg(ncerr, 'put_att type_id')
      ncerr = nf90_put_att(s%fields_grpid, varid, 'dims', dims)
      call preserf_check_nf_with_msg(ncerr, 'put_att dims')

      ! Emit only non-zero halos (put_halo_attr skips zeros).
      ! Halos are named by physical direction (i/j/k/l) rather than
      ! storage axis, so a low-rank shortcut like `IK1` (rank-2
      ! storage tuple (ie, ke1, 0, 0) plus kPlusHalo=1) still wants
      ! its physical k-halo emitted. Do NOT gate halo emission by the
      ! storage rank — emit every non-zero halo unconditionally and
      ! let the writer convention (§4) handle the rest.
      call put_halo_attr(s%fields_grpid, varid, 'iminushalo', iMinusHalo)
      call put_halo_attr(s%fields_grpid, varid, 'iplushalo', iPlusHalo)
      call put_halo_attr(s%fields_grpid, varid, 'jminushalo', jMinusHalo)
      call put_halo_attr(s%fields_grpid, varid, 'jplushalo', jPlusHalo)
      call put_halo_attr(s%fields_grpid, varid, 'kminushalo', kMinusHalo)
      call put_halo_attr(s%fields_grpid, varid, 'kplushalo', kPlusHalo)
      call put_halo_attr(s%fields_grpid, varid, 'lminushalo', lMinusHalo)
      call put_halo_attr(s%fields_grpid, varid, 'lplushalo', lPlusHalo)

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
      ! `intent(inout)` (rather than `intent(out)`) so a disabled-mode
      ! early return is a true no-op: the caller's existing savepoint
      ! handle survives intact. With `intent(out)` the actual argument
      ! would be undefined on entry, so a `!$SER OFF` block containing
      ! a SAVEPOINT would discard the previous `ppser_savepoint` and
      ! the first DATA call after `!$SER ON` would abort with
      ! "uninitialised savepoint" instead of resuming the prior one.
      type(t_savepoint), intent(inout) :: savepoint
      type(t_serializer), intent(inout), optional :: s

      if (serialisation_enabled == 0) return

      ! When we DO proceed, overwrite any stale handle the caller may
      ! have passed in — the savepoint we're about to create owns the
      ! field and `create_savepoint_on` populates it.
      savepoint%grpid = -1
      savepoint%idx = -1
      savepoint%owner_ncid = -1

      if (present(s)) then
         call create_savepoint_on(s, name, savepoint)
      else
         call create_savepoint_on(ppser_serializer, name, savepoint)
      end if
   end subroutine fs_create_savepoint

   !> Body of fs_create_savepoint, parameterised on the target serializer.
   !> Pulled out of fs_create_savepoint to avoid taking a pointer to a
   !> non-TARGET optional dummy (which would be undefined per Fortran
   !> 2008 association lifetime rules).
   subroutine create_savepoint_on(ser, name, savepoint)
      type(t_serializer), intent(inout) :: ser
      character(len=*), intent(in) :: name
      type(t_savepoint), intent(inout) :: savepoint
      character(len=9) :: group_name
      integer :: ncerr
      integer(int32) :: idx_attr

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
      ! Record the creating serializer so fs_write_field can reject a
      ! savepoint paired with a different serializer (see t_savepoint).
      savepoint%owner_ncid = ser%ncid

      idx_attr = int(ser%next_sp_index, int32)
      ncerr = nf90_put_att(savepoint%grpid, NF90_GLOBAL, &
                           '_preserf_savepoint_index', idx_attr)
      call preserf_check_nf_with_msg(ncerr, 'put_att _preserf_savepoint_index')
      ! Don't trim() the caller's name — preserve trailing blanks the
      ! same way string metainfo values do (storage_mapping.md §1 +
      ! §5: NC_CHAR string round-trip is lossless).
      ncerr = nf90_put_att(savepoint%grpid, NF90_GLOBAL, 'name', name)
      call preserf_check_nf_with_msg(ncerr, 'put_att name')

      ser%next_sp_index = ser%next_sp_index + 1
   end subroutine create_savepoint_on

   ! ========================================================================
   ! METAINFO — scalar overloads (savepoint)
   ! ========================================================================
   subroutine fs_add_savepoint_metainfo_l(sp, key, value)
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: key
      logical, intent(in) :: value
      integer(int8) :: stored
      if (serialisation_enabled == 0) return
      call require_savepoint(sp, 'fs_add_savepoint_metainfo')
      stored = merge(1_int8, 0_int8, value)
      call put_typed_scalar_attr(sp%grpid, key, NF90_BYTE, &
                                 i8_val=stored, tid=TID_BOOLEAN, &
                                 extra_reserved='name')
   end subroutine

   subroutine fs_add_savepoint_metainfo_i4(sp, key, value)
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: key
      integer(int32), intent(in) :: value
      if (serialisation_enabled == 0) return
      call require_savepoint(sp, 'fs_add_savepoint_metainfo')
      call put_typed_scalar_attr(sp%grpid, key, NF90_INT, &
                                 i32_val=value, tid=TID_INT32, &
                                 extra_reserved='name')
   end subroutine

   subroutine fs_add_savepoint_metainfo_i8(sp, key, value)
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: key
      integer(int64), intent(in) :: value
      if (serialisation_enabled == 0) return
      call require_savepoint(sp, 'fs_add_savepoint_metainfo')
      call put_typed_scalar_attr(sp%grpid, key, NF90_INT64, &
                                 i64_val=value, tid=TID_INT64, &
                                 extra_reserved='name')
   end subroutine

   subroutine fs_add_savepoint_metainfo_r4(sp, key, value)
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: key
      real(real32), intent(in) :: value
      if (serialisation_enabled == 0) return
      call require_savepoint(sp, 'fs_add_savepoint_metainfo')
      call put_typed_scalar_attr(sp%grpid, key, NF90_FLOAT, &
                                 r32_val=value, tid=TID_FLOAT32, &
                                 extra_reserved='name')
   end subroutine

   subroutine fs_add_savepoint_metainfo_r8(sp, key, value)
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: key
      real(real64), intent(in) :: value
      if (serialisation_enabled == 0) return
      call require_savepoint(sp, 'fs_add_savepoint_metainfo')
      call put_typed_scalar_attr(sp%grpid, key, NF90_DOUBLE, &
                                 r64_val=value, tid=TID_FLOAT64, &
                                 extra_reserved='name')
   end subroutine

   subroutine fs_add_savepoint_metainfo_s(sp, key, value)
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: key
      character(len=*), intent(in) :: value
      if (serialisation_enabled == 0) return
      call require_savepoint(sp, 'fs_add_savepoint_metainfo')
      call put_typed_scalar_attr(sp%grpid, key, NF90_STRING, &
                                 s_val=value, tid=TID_STRING, &
                                 extra_reserved='name')
   end subroutine

   ! ========================================================================
   ! METAINFO — scalar overloads (serializer / root group)
   ! ========================================================================
   subroutine fs_add_serializer_metainfo_l(s, key, value)
      type(t_serializer), intent(in) :: s
      character(len=*), intent(in) :: key
      logical, intent(in) :: value
      integer(int8) :: stored
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_add_serializer_metainfo')
      stored = merge(1_int8, 0_int8, value)
      call put_typed_scalar_attr(s%ncid, key, NF90_BYTE, &
                                 i8_val=stored, tid=TID_BOOLEAN)
   end subroutine

   subroutine fs_add_serializer_metainfo_i4(s, key, value)
      type(t_serializer), intent(in) :: s
      character(len=*), intent(in) :: key
      integer(int32), intent(in) :: value
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_add_serializer_metainfo')
      call put_typed_scalar_attr(s%ncid, key, NF90_INT, &
                                 i32_val=value, tid=TID_INT32)
   end subroutine

   subroutine fs_add_serializer_metainfo_i8(s, key, value)
      type(t_serializer), intent(in) :: s
      character(len=*), intent(in) :: key
      integer(int64), intent(in) :: value
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_add_serializer_metainfo')
      call put_typed_scalar_attr(s%ncid, key, NF90_INT64, &
                                 i64_val=value, tid=TID_INT64)
   end subroutine

   subroutine fs_add_serializer_metainfo_r4(s, key, value)
      type(t_serializer), intent(in) :: s
      character(len=*), intent(in) :: key
      real(real32), intent(in) :: value
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_add_serializer_metainfo')
      call put_typed_scalar_attr(s%ncid, key, NF90_FLOAT, &
                                 r32_val=value, tid=TID_FLOAT32)
   end subroutine

   subroutine fs_add_serializer_metainfo_r8(s, key, value)
      type(t_serializer), intent(in) :: s
      character(len=*), intent(in) :: key
      real(real64), intent(in) :: value
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_add_serializer_metainfo')
      call put_typed_scalar_attr(s%ncid, key, NF90_DOUBLE, &
                                 r64_val=value, tid=TID_FLOAT64)
   end subroutine

   subroutine fs_add_serializer_metainfo_s(s, key, value)
      type(t_serializer), intent(in) :: s
      character(len=*), intent(in) :: key
      character(len=*), intent(in) :: value
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_add_serializer_metainfo')
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
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: fieldname
      real(real64), intent(in) :: data(:)
      integer :: ncerr, varid
      integer, allocatable :: dimids(:)

      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_write_field')
      call require_savepoint(sp, 'fs_write_field')
      call require_savepoint_owner(s, sp, 'fs_write_field')
      call validate_field_shape(s, fieldname, shape(data), TID_FLOAT64, 'write')
      call ensure_dims(sp%grpid, fieldname, shape(data), dimids)
      call ensure_variable(sp%grpid, fieldname, NF90_DOUBLE, dimids, varid)
      ncerr = nf90_put_var(sp%grpid, varid, data)
      call preserf_check_nf_with_msg(ncerr, 'put_var '//trim(fieldname)//' (1d)')
   end subroutine

   subroutine fs_write_field_r8_2d(s, sp, fieldname, data)
      type(t_serializer), intent(inout) :: s
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: fieldname
      real(real64), intent(in) :: data(:, :)
      integer :: ncerr, varid
      integer, allocatable :: dimids(:)

      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_write_field')
      call require_savepoint(sp, 'fs_write_field')
      call require_savepoint_owner(s, sp, 'fs_write_field')
      call validate_field_shape(s, fieldname, shape(data), TID_FLOAT64, 'write')
      call ensure_dims(sp%grpid, fieldname, shape(data), dimids)
      call ensure_variable(sp%grpid, fieldname, NF90_DOUBLE, dimids, varid)
      ncerr = nf90_put_var(sp%grpid, varid, data)
      call preserf_check_nf_with_msg(ncerr, 'put_var '//trim(fieldname)//' (2d)')
   end subroutine

   subroutine fs_write_field_r8_3d(s, sp, fieldname, data)
      type(t_serializer), intent(inout) :: s
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: fieldname
      real(real64), intent(in) :: data(:, :, :)
      integer :: ncerr, varid
      integer, allocatable :: dimids(:)

      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_write_field')
      call require_savepoint(sp, 'fs_write_field')
      call require_savepoint_owner(s, sp, 'fs_write_field')
      call validate_field_shape(s, fieldname, shape(data), TID_FLOAT64, 'write')
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
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: fieldname
      real(real64), intent(inout) :: data(:)
      integer :: ncerr, varid
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_read_field')
      call require_savepoint(sp, 'fs_read_field')
      call validate_field_shape(s, fieldname, shape(data), TID_FLOAT64, 'read')
      ncerr = nf90_inq_varid(sp%grpid, trim(fieldname), varid)
      call preserf_check_nf_with_msg(ncerr, 'inq_varid '//trim(fieldname))
      call require_variable_xtype(s, sp%grpid, varid, fieldname, NF90_DOUBLE)
      ncerr = nf90_get_var(sp%grpid, varid, data)
      call preserf_check_nf_with_msg(ncerr, 'get_var '//trim(fieldname)//' (1d)')
   end subroutine

   subroutine fs_read_field_r8_2d(s, sp, fieldname, data)
      type(t_serializer), intent(in) :: s
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: fieldname
      real(real64), intent(inout) :: data(:, :)
      integer :: ncerr, varid
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_read_field')
      call require_savepoint(sp, 'fs_read_field')
      call validate_field_shape(s, fieldname, shape(data), TID_FLOAT64, 'read')
      ncerr = nf90_inq_varid(sp%grpid, trim(fieldname), varid)
      call preserf_check_nf_with_msg(ncerr, 'inq_varid '//trim(fieldname))
      call require_variable_xtype(s, sp%grpid, varid, fieldname, NF90_DOUBLE)
      ncerr = nf90_get_var(sp%grpid, varid, data)
      call preserf_check_nf_with_msg(ncerr, 'get_var '//trim(fieldname)//' (2d)')
   end subroutine

   subroutine fs_read_field_r8_3d(s, sp, fieldname, data)
      type(t_serializer), intent(in) :: s
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: fieldname
      real(real64), intent(inout) :: data(:, :, :)
      integer :: ncerr, varid
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_read_field')
      call require_savepoint(sp, 'fs_read_field')
      call validate_field_shape(s, fieldname, shape(data), TID_FLOAT64, 'read')
      ncerr = nf90_inq_varid(sp%grpid, trim(fieldname), varid)
      call preserf_check_nf_with_msg(ncerr, 'inq_varid '//trim(fieldname))
      call require_variable_xtype(s, sp%grpid, varid, fieldname, NF90_DOUBLE)
      ncerr = nf90_get_var(sp%grpid, varid, data)
      call preserf_check_nf_with_msg(ncerr, 'get_var '//trim(fieldname)//' (3d)')
   end subroutine

   ! ------------------------------------------------------------------------
   ! DATA — read with perturbation magnitude (CASE(2) form)
   !
   ! pp_ser's read-perturb branch emits
   !   call fs_read_field(ppser_serializer_ref, ppser_savepoint,
   !                      '<field>', <expr>, ppser_zrperturb)
   ! so the generic MUST resolve the 5-argument form at compile time
   ! (otherwise generated source containing read-perturb DATA blocks
   ! fails to compile). The actual perturbation algorithm is not yet
   ! implemented, so calling these overloads at runtime aborts with a
   ! clear "not yet implemented" message rather than silently
   ! returning unperturbed data (which would be wire-incompatible with
   ! Serialbox's mode=2 semantics). See src/preserf-fortran/README.md
   ! for the follow-up tracking this.
   ! ------------------------------------------------------------------------
   subroutine fs_read_field_r8_1d_perturb(s, sp, fieldname, data, perturb)
      type(t_serializer), intent(in) :: s
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: fieldname
      real(real64), intent(inout) :: data(:)
      real(real64), intent(in) :: perturb
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_read_field')
      call require_savepoint(sp, 'fs_read_field')
      call read_perturb_not_implemented(fieldname, s, sp, perturb, &
                                        size(data, kind=int64))
   end subroutine

   subroutine fs_read_field_r8_2d_perturb(s, sp, fieldname, data, perturb)
      type(t_serializer), intent(in) :: s
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: fieldname
      real(real64), intent(inout) :: data(:, :)
      real(real64), intent(in) :: perturb
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_read_field')
      call require_savepoint(sp, 'fs_read_field')
      call read_perturb_not_implemented(fieldname, s, sp, perturb, &
                                        size(data, kind=int64))
   end subroutine

   subroutine fs_read_field_r8_3d_perturb(s, sp, fieldname, data, perturb)
      type(t_serializer), intent(in) :: s
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: fieldname
      real(real64), intent(inout) :: data(:, :, :)
      real(real64), intent(in) :: perturb
      if (serialisation_enabled == 0) return
      call require_open(s, 'fs_read_field')
      call require_savepoint(sp, 'fs_read_field')
      call read_perturb_not_implemented(fieldname, s, sp, perturb, &
                                        size(data, kind=int64))
   end subroutine

   subroutine read_perturb_not_implemented(fieldname, s, sp, perturb, n)
      character(len=*), intent(in) :: fieldname
      type(t_serializer), intent(in) :: s
      type(t_savepoint), intent(in) :: sp
      real(real64), intent(in) :: perturb
      integer(int64), intent(in) :: n
      integer :: discard_int
      real(real64) :: discard_real
      ! Reference the dummy args so the compiler doesn't complain
      ! about them — they are part of the API surface even though
      ! the body just aborts.
      discard_int = s%ncid + sp%grpid + int(n)
      discard_real = perturb
      write (*, '(a,a,a)') &
         'preserf: read-perturb (mode 2) for field "', trim(fieldname), &
         '" is not yet implemented in v0.1; the 5-arg fs_read_field '// &
         'overload exists only so pp_ser-emitted source compiles. '// &
         'Set ppser_set_mode(1) for a plain read, or pin the helper '// &
         'to a follow-up PR that implements perturbation.'
      error stop 1
   end subroutine read_perturb_not_implemented

   ! ========================================================================
   ! Internal helpers
   ! ========================================================================

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
         select case (bytes_per_element)
         case (4)
            tid = TID_INT32
         case (8)
            tid = TID_INT64
         case default
            call reject_byte_length(trim(datatype), bytes_per_element, &
                                    '4 or 8')
            tid = TID_INT32  ! unreachable; satisfies compiler
         end select
      case ('int64', 'long')
         call require_byte_length(trim(datatype), bytes_per_element, 8)
         tid = TID_INT64
      case ('float', 'single')
         call require_byte_length(trim(datatype), bytes_per_element, 4)
         tid = TID_FLOAT32
      case ('double')
         call require_byte_length(trim(datatype), bytes_per_element, 8)
         tid = TID_FLOAT64
      case ('real')
         select case (bytes_per_element)
         case (4)
            tid = TID_FLOAT32
         case (8)
            tid = TID_FLOAT64
         case default
            call reject_byte_length(trim(datatype), bytes_per_element, &
                                    '4 or 8')
            tid = TID_FLOAT64  ! unreachable; satisfies compiler
         end select
      case ('string', 'character')
         tid = TID_STRING
      case default
         write (*, '(a,a)') 'preserf: unknown datatype string: ', trim(datatype)
         error stop 1
      end select
   end function type_id_from_datatype

   subroutine reject_byte_length(datatype, got, expected)
      character(len=*), intent(in) :: datatype
      integer, intent(in) :: got
      character(len=*), intent(in) :: expected
      write (*, '(a,a,a,i0,a,a)') &
         'preserf: unsupported byte length for datatype "', &
         datatype, '": got ', got, &
         ' bytes/element, expected ', expected
      error stop 1
   end subroutine reject_byte_length

   !> Require a fixed-width datatype string (e.g. 'double', 'int64') to
   !> be paired with the matching byte length. Catches callers that
   !> pass a fixed-width type name but a mismatched bytes_per_element
   !> (e.g. `datatype='double', bytes_per_element=4`), which would
   !> otherwise silently produce registry metadata that disagrees with
   !> the caller's element size.
   subroutine require_byte_length(datatype, got, expected)
      character(len=*), intent(in) :: datatype
      integer, intent(in) :: got, expected
      character(len=16) :: expected_str
      if (got == expected) return
      write (expected_str, '(i0)') expected
      call reject_byte_length(datatype, got, trim(expected_str))
   end subroutine require_byte_length

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

      ! Reject any negative size up front — both "active" and trailing
      ! positions must be >= 0. Without this check, a negative trailing
      ! size like (iSize=4, jSize=-3, kSize=0, lSize=0) is silently
      ! treated as a 1-D field (because the `> 0` rank check skips
      ! jSize=-3), hiding a clearly bad REGISTER tuple.
      if (iSize < 0 .or. jSize < 0 .or. kSize < 0 .or. lSize < 0) then
         write (*, '(a,4(i0,a))') &
            'preserf: invalid dim tuple (', &
            iSize, ',', jSize, ',', kSize, ',', lSize, &
            '); negative sizes are not allowed'
         error stop 1
      end if

      ! Reject non-contiguous prefixes up front.
      if (jSize > 0 .and. iSize <= 0) call active_dims_inconsistent( &
         iSize, jSize, kSize, lSize)
      if (kSize > 0 .and. jSize <= 0) call active_dims_inconsistent( &
         iSize, jSize, kSize, lSize)
      if (lSize > 0 .and. kSize <= 0) call active_dims_inconsistent( &
         iSize, jSize, kSize, lSize)

      ! At least iSize must be strictly positive — a (0,0,0,0) tuple
      ! would otherwise produce a rank-0 dims attribute, but the
      ! helper API doesn't support 0-D fields.
      if (iSize <= 0) then
         write (*, '(a,4(i0,a))') &
            'preserf: invalid dim tuple (', &
            iSize, ',', jSize, ',', kSize, ',', lSize, &
            '); iSize must be > 0'
         error stop 1
      end if

      ! Bounds-check active dims before the int32 cast: under a
      ! -fdefault-integer-8 build the dummy args are int64-wide and a
      ! bare int(iSize, int32) would silently truncate values past
      ! huge(0_int32) (fortran-helper-roadmap.md §4).
      call require_fits_int32(iSize, 'iSize')
      if (jSize > 0) call require_fits_int32(jSize, 'jSize')
      if (kSize > 0) call require_fits_int32(kSize, 'kSize')
      if (lSize > 0) call require_fits_int32(lSize, 'lSize')

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

   !> Abort if `value` (a default-kind integer) cannot be represented
   !> as int32. storage_mapping.md §1 pins the on-disk `dims` and halo
   !> attributes to NC_INT (int32 on the wire), so widening the on-disk
   !> type is not an option. Under a -fdefault-integer-8 build the
   !> dummy arg can hold values past huge(0_int32) and a bare
   !> int(value, int32) would silently truncate; this guard turns that
   !> into a clean error_stop. Carry-over from PR #4 review
   !> (fortran-helper-roadmap.md §4).
   subroutine require_fits_int32(value, label)
      integer, intent(in) :: value
      character(len=*), intent(in) :: label
      if (int(value, int64) > int(huge(0_int32), int64)) then
         write (*, '(a,a,a,i0,a,i0)') &
            'preserf: ', trim(label), &
            ' exceeds int32 capacity; got ', value, &
            ', max is ', huge(0_int32)
         error stop 1
      end if
   end subroutine require_fits_int32

   subroutine put_halo_attr(grpid, varid, name, value)
      integer, intent(in) :: grpid, varid
      character(len=*), intent(in) :: name
      integer, intent(in) :: value
      integer :: ncerr
      integer(int32) :: v
      ! Halos describe a physical extent (number of ghost cells on
      ! one side of an axis). Reject negative values rather than
      ! writing nonsensical metadata that readers would round-trip
      ! without complaint.
      if (value < 0) then
         write (*, '(a,a,a,i0)') &
            'preserf: negative halo extent for "', name, '": ', value
         error stop 1
      end if
      if (value == 0) return
      call require_fits_int32(value, 'halo "'//trim(name)//'"')
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
   !>   * String  → character(*)   → NC_CHAR
   !>
   !> Both reference writers (Python `netCDF4.Dataset.setncattr` and
   !> the netcdf-fortran F90 `nf90_put_att` with a `character(*)`
   !> argument) produce NC_CHAR for scalar string attributes — see
   !> storage_mapping.md §1. The `__preserf_type_id` shadow attribute
   !> is still the schema's source of truth for the typed-value
   !> contract; readers MUST decode through it rather than the on-disk
   !> netCDF type.
   subroutine put_typed_scalar_attr(grpid, key, nc_type, &
                                    tid, i8_val, i32_val, i64_val, &
                                    r32_val, r64_val, s_val, &
                                    extra_reserved)
      integer, intent(in) :: grpid
      character(len=*), intent(in) :: key
      integer, intent(in) :: nc_type
      integer(int32), intent(in) :: tid
      integer(int8), intent(in), optional :: i8_val
      integer(int32), intent(in), optional :: i32_val
      integer(int64), intent(in), optional :: i64_val
      real(real32), intent(in), optional :: r32_val
      real(real64), intent(in), optional :: r64_val
      character(len=*), intent(in), optional :: s_val
      ! Context-specific reserved attribute name to additionally
      ! reject. Savepoint metainfo callers pass `'name'`; root
      ! callers leave it unset.
      character(len=*), intent(in), optional :: extra_reserved

      integer :: ncerr
      character(len=:), allocatable :: shadow

      if (serialisation_enabled == 0) return

      ! Reject keys colliding with the reserved housekeeping namespace
      ! (`_preserf_*`) or the shadow-tag suffix (`__preserf_type_id`),
      ! per storage_mapping.md §3.2. Matches the Python writer's
      ! _write_metainfo_attrs guard. The optional `extra_reserved`
      ! covers per-context schema attributes (`name` on savepoint
      ! groups; field-registry uses a different code path).
      call reject_reserved_metainfo_key(key, extra_reserved)

      select case (nc_type)
      case (NF90_BYTE)
         if (.not. present(i8_val)) call missing_value_arg(key, 'i8_val')
         ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, i8_val)
      case (NF90_INT)
         if (.not. present(i32_val)) call missing_value_arg(key, 'i32_val')
         ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, i32_val)
      case (NF90_INT64)
         if (.not. present(i64_val)) call missing_value_arg(key, 'i64_val')
         ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, i64_val)
      case (NF90_FLOAT)
         if (.not. present(r32_val)) call missing_value_arg(key, 'r32_val')
         ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, r32_val)
      case (NF90_DOUBLE)
         if (.not. present(r64_val)) call missing_value_arg(key, 'r64_val')
         ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, r64_val)
      case (NF90_STRING)
         ! See block comment above — this lands as NC_CHAR on disk
         ! (the F90 wrapper calls nc_put_att_text under the hood).
         ! The Python reference writer also produces NC_CHAR for
         ! scalar string attributes; documented in
         ! storage_mapping.md §1.
         !
         ! NOTE: pass s_val through *without* trim() so trailing
         ! blanks the caller deliberately included are preserved.
         ! storage_mapping.md §1's lossless-string contract requires
         ! this; key sanitization happens above via trim(key), but
         ! the user value is opaque.
         if (.not. present(s_val)) call missing_value_arg(key, 's_val')
         ncerr = nf90_put_att(grpid, NF90_GLOBAL, key, s_val)
      case default
         write (*, '(a,i0)') 'preserf: unsupported nc_type ', nc_type
         error stop 1
      end select
      call preserf_check_nf_with_msg(ncerr, 'put_att '//key)

      ! Use trim(key) so a fixed-length caller-side key like
      ! `character(len=32) :: key = 'author'` produces the same shadow
      ! tag (`author__preserf_type_id`) the Python reader expects.
      shadow = trim(key)//'__preserf_type_id'
      ncerr = nf90_put_att(grpid, NF90_GLOBAL, shadow, tid)
      call preserf_check_nf_with_msg(ncerr, 'put_att '//shadow)
   end subroutine put_typed_scalar_attr

   subroutine missing_value_arg(key, expected)
      character(len=*), intent(in) :: key, expected
      write (*, '(a,a,a,a,a)') &
         'preserf: put_typed_scalar_attr("', trim(key), &
         '") requires the ', trim(expected), &
         ' optional argument for the requested nc_type'
      error stop 1
   end subroutine missing_value_arg

   subroutine reject_reserved_metainfo_key(key, extra_reserved)
      character(len=*), intent(in) :: key
      character(len=*), intent(in), optional :: extra_reserved
      character(len=*), parameter :: prefix = '_preserf_'
      character(len=*), parameter :: suffix = '__preserf_type_id'
      character(len=:), allocatable :: tkey
      integer :: tlen

      ! Base validation on trim(key) so a fixed-length caller-side
      ! buffer like `character(len=32) :: k = 'foo__preserf_type_id'`
      ! still trips the suffix check despite trailing blanks.
      tkey = trim(key)
      tlen = len(tkey)

      if (tlen >= len(prefix)) then
         if (tkey(1:len(prefix)) == prefix) then
            write (*, '(a,a,a)') 'preserf: metainfo key "', tkey, &
               '" collides with reserved prefix "_preserf_"'
            error stop 1
         end if
      end if
      if (tlen >= len(suffix)) then
         if (tkey(tlen - len(suffix) + 1:tlen) == suffix) then
            write (*, '(a,a,a)') 'preserf: metainfo key "', tkey, &
               '" collides with reserved suffix "__preserf_type_id"'
            error stop 1
         end if
      end if
      if (present(extra_reserved)) then
         if (tkey == trim(extra_reserved)) then
            write (*, '(a,a,a,a,a)') 'preserf: metainfo key "', &
               tkey, '" collides with the schema attribute "', &
               trim(extra_reserved), '" on this target group'
            error stop 1
         end if
      end if
   end subroutine reject_reserved_metainfo_key

   !> Validate that the runtime Fortran shape of a read or write matches
   !> the field's registered dims under `/_fields/<fieldname>` (which are
   !> stored in C-order, so we compare against `reverse(fortran_shape)`).
   !> Aborts with a clear error on type-id mismatch, shape mismatch, or
   !> on accesses to fields that were never registered. `op` is "write"
   !> or "read" and is interpolated into error messages.
   subroutine validate_field_shape(s, fieldname, fortran_shape, &
                                   expected_tid, op)
      type(t_serializer), intent(in) :: s
      character(len=*), intent(in) :: fieldname
      integer, intent(in) :: fortran_shape(:)
      integer(int32), intent(in) :: expected_tid
      character(len=*), intent(in) :: op
      integer :: ncerr, varid, attr_len, axis
      integer(int32), allocatable :: registered_dims(:)
      integer(int32) :: registered_tid

      ncerr = nf90_inq_varid(s%fields_grpid, trim(fieldname), varid)
      if (ncerr == NF90_ENOTVAR) then
         write (*, '(a,a,a,a,a)') &
            'preserf: ', trim(op), ' on unregistered field "', &
            trim(fieldname), '"; call fs_register_field first'
         error stop 1
      end if
      call preserf_check_nf_with_msg(ncerr, &
                                     'inq_varid /_fields/'//trim(fieldname))

      ! Confirm the registered TypeID matches the Fortran overload's
      ! dtype. Without this check the data variable's nc_type and the
      ! registry's type_id can disagree, and Python readers (which
      ! decode through the registry) would silently cast and corrupt
      ! values. On the read side, netCDF's automatic type conversion
      ! could likewise quietly accept a wrong-typed registry.
      ncerr = nf90_get_att(s%fields_grpid, varid, 'type_id', registered_tid)
      call preserf_check_nf_with_msg(ncerr, 'get_att type_id')
      if (registered_tid /= expected_tid) then
         write (*, '(a,a,a,a,a,i0,a,i0,a)') &
            'preserf: ', trim(op), ' on field "', trim(fieldname), &
            '" via type-id=', expected_tid, &
            ' overload but the field was registered with type_id=', &
            registered_tid, '.'
         error stop 1
      end if

      ncerr = nf90_inquire_attribute(s%fields_grpid, varid, 'dims', len=attr_len)
      call preserf_check_nf_with_msg(ncerr, 'inquire_attribute dims')
      allocate (registered_dims(attr_len))
      ncerr = nf90_get_att(s%fields_grpid, varid, 'dims', registered_dims)
      call preserf_check_nf_with_msg(ncerr, 'get_att dims')

      if (size(fortran_shape) /= attr_len) then
         write (*, '(a,a,a,a,a,i0,a,i0,a)') &
            'preserf: ', trim(op), ' on field "', trim(fieldname), &
            '" has Fortran rank ', size(fortran_shape), &
            ' but was registered with C-order rank ', attr_len, '.'
         error stop 1
      end if

      ! registered_dims(i) is C-order axis (i-1); compare against
      ! reverse(fortran_shape): C-axis 0 ↔ last Fortran axis.
      do axis = 1, attr_len
         if (int(registered_dims(axis)) /= &
             fortran_shape(attr_len - axis + 1)) then
            write (*, '(a,a,a,a,a)') &
               'preserf: ', trim(op), ' on field "', &
               trim(fieldname), &
               '" runtime shape disagrees with registered dims.'
            write (*, '(a,*(i0,1x))') &
               '  registered (C-order): ', registered_dims
            write (*, '(a,*(i0,1x))') &
               '  runtime (Fortran):    ', fortran_shape
            error stop 1
         end if
      end do
   end subroutine validate_field_shape

   !> Ensure per-field dimensions exist on `grpid` and return their dim ids.
   !> Dimensions are named `<fieldname>_dim0`, `<fieldname>_dim1`, … in
   !> netCDF C-order (slowest-varying axis first, matching how `dims` is
   !> recorded on `/_fields/<fieldname>`). The returned `dimids` are
   !> ordered in Fortran convention (fastest-varying first), so that
   !> netcdf-fortran's automatic dim reversal yields a variable layout
   !> on disk whose dimension order matches the C-order dim names.
   !> See storage_mapping.md §1.1 + §6.
   subroutine ensure_dims(grpid, fieldname, shp_fortran, dimids)
      integer, intent(in) :: grpid
      character(len=*), intent(in) :: fieldname
      integer, intent(in) :: shp_fortran(:)
      integer, allocatable, intent(out) :: dimids(:)
      integer :: r, c_axis, ncerr
      integer, allocatable :: dim_id_by_c_axis(:)
      character(len=:), allocatable :: dname
      character(len=8) :: axis_str

      r = size(shp_fortran)
      allocate (dim_id_by_c_axis(r))
      ! Create / look up dimensions named by C-order axis. C-axis 0 maps
      ! to the slowest-varying = last Fortran axis (= shp_fortran(r)).
      do c_axis = 1, r
         write (axis_str, '(i0)') c_axis - 1
         dname = trim(fieldname)//'_dim'//trim(axis_str)
         ncerr = nf90_inq_dimid(grpid, dname, dim_id_by_c_axis(c_axis))
         if (ncerr == NF90_EBADDIM) then
            ncerr = nf90_def_dim(grpid, dname, &
                                 shp_fortran(r - c_axis + 1), &
                                 dim_id_by_c_axis(c_axis))
            call preserf_check_nf_with_msg(ncerr, 'def_dim '//dname)
         else
            call preserf_check_nf_with_msg(ncerr, 'inq_dimid '//dname)
         end if
      end do

      ! Return dimids in Fortran order (fastest-varying first): netcdf-
      ! fortran reverses this when calling C, so the on-disk variable
      ! reports its dims in C-order, matching the `dims` attribute.
      allocate (dimids(r))
      do c_axis = 1, r
         dimids(r - c_axis + 1) = dim_id_by_c_axis(c_axis)
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

   !> Abort with a clear message if the savepoint hasn't been created
   !> (or has been cleared by a no-op SAVEPOINT branch). Without this
   !> guard, passing an uninitialised `sp%grpid = -1` into netCDF calls
   !> surfaces as a low-level "NetCDF: Not a valid ID" error rather
   !> than a preserf-level lifecycle diagnostic.
   subroutine require_savepoint(sp, where)
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: where
      if (sp%grpid == -1) then
         write (*, '(a,a,a)') 'preserf: ', trim(where), &
            ' called with an uninitialised savepoint '// &
            '(call fs_create_savepoint first)'
         error stop 1
      end if
   end subroutine require_savepoint

   !> Abort if `sp` was created by a serializer other than `s`.
   !> fs_write_field validates the field registry through
   !> `s%fields_grpid` but creates / writes the data variable under
   !> `sp%grpid`. If the savepoint belongs to a different store the
   !> registry and the data variable would land in different files,
   !> silently producing an internally inconsistent output. The
   !> writable serializer is unique per session, so a mismatch always
   !> signals a caller bug rather than a supported cross-store flow.
   subroutine require_savepoint_owner(s, sp, where)
      type(t_serializer), intent(in) :: s
      type(t_savepoint), intent(in) :: sp
      character(len=*), intent(in) :: where
      if (sp%owner_ncid /= s%ncid) then
         write (*, '(a,a,a)') 'preserf: ', trim(where), &
            ' was passed a savepoint created by a different '// &
            'serializer; the field registry and the data variable '// &
            'would belong to different stores'
         error stop 1
      end if
   end subroutine require_savepoint_owner

   !> Confirm the on-disk netCDF variable matches what the Fortran
   !> read overload + the `/_fields/<name>` registry entry expect:
   !> both the variable's `xtype` AND its actual dimension lengths.
   !>
   !> `validate_field_shape` already checks the registry's `type_id`
   !> and `dims` against the caller's runtime shape; this helper
   !> additionally cross-checks the *savepoint variable* on disk
   !> against the same registry, so a store whose registry and
   !> variable disagree (e.g. mutated by a third-party tool) is
   !> rejected up-front instead of being silently coerced by
   !> nf90_get_var or hitting a low-level netCDF error mid-read.
   subroutine require_variable_xtype(s, sp_grpid, varid, fieldname, &
                                     expected_xtype)
      type(t_serializer), intent(in) :: s
      integer, intent(in) :: sp_grpid, varid
      character(len=*), intent(in) :: fieldname
      integer, intent(in) :: expected_xtype
      integer :: ncerr, actual_xtype, actual_ndims, axis, registry_varid, &
                 attr_len
      integer(int32), allocatable :: expected_dims_c(:)
      integer, allocatable :: dimids(:)
      integer :: actual_len

      ! Re-fetch the registry's `dims` attribute so the on-disk variable
      ! comparison uses exactly the same reference values that
      ! `validate_field_shape` checked the caller against.
      ncerr = nf90_inq_varid(s%fields_grpid, trim(fieldname), registry_varid)
      call preserf_check_nf_with_msg(ncerr, &
                                     'inq_varid /_fields/'//trim(fieldname))
      ncerr = nf90_inquire_attribute(s%fields_grpid, registry_varid, 'dims', &
                                     len=attr_len)
      call preserf_check_nf_with_msg(ncerr, &
                                     'inquire_attribute dims (for variable check)')
      allocate (expected_dims_c(attr_len))
      ncerr = nf90_get_att(s%fields_grpid, registry_varid, 'dims', &
                           expected_dims_c)
      call preserf_check_nf_with_msg(ncerr, 'get_att dims (for variable check)')

      ncerr = nf90_inquire_variable(sp_grpid, varid, xtype=actual_xtype, &
                                    ndims=actual_ndims)
      call preserf_check_nf_with_msg(ncerr, &
                                     'inquire_variable '//trim(fieldname))
      if (actual_xtype /= expected_xtype) then
         write (*, '(a,a,a,i0,a,i0,a)') &
            'preserf: read of field "', trim(fieldname), &
            '" expects on-disk nc_type ', expected_xtype, &
            ' but the variable has nc_type ', actual_xtype, &
            '. Registry / variable mismatch in the store.'
         error stop 1
      end if
      if (actual_ndims /= size(expected_dims_c)) then
         write (*, '(a,a,a,i0,a,i0,a)') &
            'preserf: read of field "', trim(fieldname), &
            '" expects rank ', size(expected_dims_c), &
            ' but the on-disk variable has rank ', actual_ndims, '.'
         error stop 1
      end if
      if (actual_ndims > 0) then
         allocate (dimids(actual_ndims))
         ncerr = nf90_inquire_variable(sp_grpid, varid, dimids=dimids)
         call preserf_check_nf_with_msg(ncerr, &
                                        'inquire_variable dimids '//trim(fieldname))
         ! netcdf-fortran returns dimids in Fortran order
         ! (fastest-varying first). The expected_dims_c vector is
         ! C-order (slowest-first), so we compare dimids(k) against
         ! expected_dims_c(rank - k + 1).
         do axis = 1, actual_ndims
            ncerr = nf90_inquire_dimension(sp_grpid, dimids(axis), &
                                           len=actual_len)
            call preserf_check_nf_with_msg(ncerr, &
                                           'inquire_dimension '//trim(fieldname))
            if (actual_len /= &
                int(expected_dims_c(actual_ndims - axis + 1))) then
               write (*, '(a,a,a)') &
                  'preserf: read of field "', trim(fieldname), &
                  '" on-disk variable dimension lengths disagree '// &
                  'with registry dims.'
               write (*, '(a,*(i0,1x))') &
                  '  registered (C-order):    ', expected_dims_c
               write (*, '(a,*(i0,1x))') &
                  '  variable axis (Fortran): ', axis, actual_len
               error stop 1
            end if
         end do
         deallocate (dimids)
      end if
   end subroutine require_variable_xtype

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
