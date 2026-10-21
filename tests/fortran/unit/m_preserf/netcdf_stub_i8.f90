!> Test-only stub of the `netcdf` module surface, compiled with
!> `-fdefault-integer-8` so the int8 variant build of the helper library
!> has a module interface whose default-integer dummies are 8 bytes wide.
!>
!> The int8 (64-bit default-integer) variant exists to exercise the int32
!> boundary guards (`require_fits_int32`) end to end: under the normal
!> int4 build no default-kind value can exceed `huge(0_int32)`, so the
!> guard paths are unreachable there (the repo documented this when the
!> guards landed; see CHANGELOG for the wire-cast guard change). The
!> conda-forge netcdf-fortran is compiled with 4-byte default integers,
!> so the library sources cannot compile against its `netcdf.mod` with
!> the flag set — this stub provides the same names with 8-byte
!> default-integer dummies instead.
!>
!> The routines are deliberate no-ops returning NF90_NOERR: the scenario
!> that runs under this build (`option-bad-verbosity-i8`) aborts inside
!> `fs_Option`'s guard *before* any netcdf call, so no real store is
!> needed. Value-carrying dummies use unlimited-polymorphic assumed-rank
!> (`class(*), dimension(..)`) so one specific per routine matches every
!> (kind x rank) combination the library's overload matrix instantiates.
!> The `dimension(..)` form needs Fortran 2018, so this file compiles
!> with `-std=f2018` (the library proper stays `-std=f2008`).
module netcdf
   use, intrinsic :: iso_c_binding, only: c_char, c_int, c_ptr, c_size_t
   implicit none
   integer, parameter :: NF90_NOERR = 0
   integer, parameter :: NF90_GLOBAL = 0
   integer, parameter :: NF90_NETCDF4 = 4
   integer, parameter :: NF90_NOWRITE = 1
   integer, parameter :: NF90_BYTE = 1
   integer, parameter :: NF90_INT = 4
   integer, parameter :: NF90_INT64 = 10
   integer, parameter :: NF90_FLOAT = 5
   integer, parameter :: NF90_DOUBLE = 6
   integer, parameter :: NF90_STRING = 12
   integer, parameter :: NF90_UNLIMITED = -1
   integer, parameter :: NF90_EBADDIM = -6054
   integer, parameter :: NF90_EINDEFINE = -6045
   integer, parameter :: NF90_ENOTATT = -6043
   integer, parameter :: NF90_ENOTVAR = -601314
   interface nf90_def_var
      module procedure def_var_scalar
      module procedure def_var_array
   end interface nf90_def_var
   public :: nf90_def_var
contains
   integer function nf90_close(ncid)
      integer, intent(in) :: ncid
      nf90_close = NF90_NOERR
   end function nf90_close
   integer function nf90_create(path, cmode, ncid)
      character(len=*), intent(in) :: path
      integer, intent(in) :: cmode
      integer, intent(out) :: ncid
      ncid = 1
      nf90_create = NF90_NOERR
   end function nf90_create
   integer function nf90_open(path, mode, ncid)
      character(len=*), intent(in) :: path
      integer, intent(in) :: mode
      integer, intent(out) :: ncid
      ncid = 1
      nf90_open = NF90_NOERR
   end function nf90_open
   integer function nf90_redef(ncid)
      integer, intent(in) :: ncid
      nf90_redef = NF90_NOERR
   end function nf90_redef
   integer function nf90_enddef(ncid)
      integer, intent(in) :: ncid
      nf90_enddef = NF90_NOERR
   end function nf90_enddef
   integer function nf90_def_grp(parent_ncid, name, grp)
      integer, intent(in) :: parent_ncid
      character(len=*), intent(in) :: name
      integer, intent(out) :: grp
      grp = 2
      nf90_def_grp = NF90_NOERR
   end function nf90_def_grp
   integer function nf90_inq_ncid(ncid, name, grp)
      integer, intent(in) :: ncid
      character(len=*), intent(in) :: name
      integer, intent(out) :: grp
      grp = 2
      nf90_inq_ncid = NF90_NOERR
   end function nf90_inq_ncid
   integer function nf90_inq_grps(ncid, ncids, start)
      integer, intent(in) :: ncid
      integer, intent(out) :: ncids(:)
      integer, intent(in), optional :: start
      ncids = 2
      nf90_inq_grps = NF90_NOERR
   end function nf90_inq_grps
   integer function nf90_put_att(ncid, varid, name, values)
      integer, intent(in) :: ncid, varid
      character(len=*), intent(in) :: name
      class(*), intent(in), dimension(..) :: values
      nf90_put_att = NF90_NOERR
   end function nf90_put_att
   integer function nf90_get_att(ncid, varid, name, values)
      integer, intent(in) :: ncid, varid
      character(len=*), intent(in) :: name
      class(*), intent(inout), dimension(..) :: values
      nf90_get_att = NF90_NOERR
   end function nf90_get_att
   integer function nf90_del_att(ncid, varid, name)
      integer, intent(in) :: ncid, varid
      character(len=*), intent(in) :: name
      nf90_del_att = NF90_NOERR
   end function nf90_del_att
   integer function nf90_def_dim(ncid, name, len, dimid)
      integer, intent(in) :: ncid
      character(len=*), intent(in) :: name
      integer, intent(in) :: len
      integer, intent(out) :: dimid
      dimid = 3
      nf90_def_dim = NF90_NOERR
   end function nf90_def_dim
   integer function nf90_inq_dimid(ncid, name, dimid)
      integer, intent(in) :: ncid
      character(len=*), intent(in) :: name
      integer, intent(out) :: dimid
      dimid = 3
      nf90_inq_dimid = NF90_NOERR
   end function nf90_inq_dimid
   integer function def_var_scalar(ncid, name, xtype, varid)
      integer, intent(in) :: ncid
      character(len=*), intent(in) :: name
      integer, intent(in) :: xtype
      integer, intent(out) :: varid
      varid = 4
      def_var_scalar = NF90_NOERR
   end function def_var_scalar
   integer function def_var_array(ncid, name, xtype, dimids, varid)
      integer, intent(in) :: ncid
      character(len=*), intent(in) :: name
      integer, intent(in) :: xtype
      integer, intent(in) :: dimids(:)
      integer, intent(out) :: varid
      varid = 4
      def_var_array = NF90_NOERR
   end function def_var_array
   integer function nf90_inq_varid(ncid, name, varid)
      integer, intent(in) :: ncid
      character(len=*), intent(in) :: name
      integer, intent(out) :: varid
      varid = 4
      nf90_inq_varid = NF90_NOERR
   end function nf90_inq_varid
   integer function nf90_put_var(ncid, varid, values)
      integer, intent(in) :: ncid, varid
      class(*), intent(in), dimension(..) :: values
      nf90_put_var = NF90_NOERR
   end function nf90_put_var
   integer function nf90_get_var(ncid, varid, values)
      integer, intent(in) :: ncid, varid
      class(*), intent(inout), dimension(..) :: values
      nf90_get_var = NF90_NOERR
   end function nf90_get_var
   integer function nf90_inquire_variable(grpid, varid, xtype, ndims, dimids)
      integer, intent(in) :: grpid, varid
      integer, intent(out), optional :: xtype, ndims
      integer, intent(out), optional :: dimids(:)
      if (present(xtype)) xtype = NF90_INT
      if (present(ndims)) ndims = 1
      if (present(dimids)) dimids = 3
      nf90_inquire_variable = NF90_NOERR
   end function nf90_inquire_variable
   integer function nf90_inquire_dimension(grpid, dimid, name, len)
      integer, intent(in) :: grpid, dimid
      character(len=*), intent(out), optional :: name
      integer, intent(out), optional :: len
      if (present(name)) name = 'x'
      if (present(len)) len = 1
      nf90_inquire_dimension = NF90_NOERR
   end function nf90_inquire_dimension
   integer function nf90_inquire_attribute(grpid, varid, name, len, xtype)
      integer, intent(in) :: grpid, varid
      character(len=*), intent(in) :: name
      integer, intent(out), optional :: len, xtype
      if (present(len)) len = 1
      if (present(xtype)) xtype = NF90_INT
      nf90_inquire_attribute = NF90_NOERR
   end function nf90_inquire_attribute
    function nf90_strerror(ncerr)
       integer, intent(in) :: ncerr
       character(len=80) :: nf90_strerror
       nf90_strerror = 'stub'
    end function nf90_strerror

    ! C-interop stand-ins for the netcdf-c vector-of-strings attribute
    ! functions m_preserf's iso_c_binding interface block references (the
    ! NC_STRING-vector metainfo writer). The int8 variant build never
    ! calls them (its scenario aborts inside fs_Option's guard before
    ! any netcdf call), but the linker must find the symbols: the linux
    ! ld prunes their uncalled relocations via --gc-sections, whereas
    ! the macOS linker keeps every relocation from a pulled archive
    ! member and would fail with undefined references. Carrying no-op
    ! definitions with the same binding names resolves them on BOTH
    ! platforms without adding real netcdf-c to the variant's link line
    ! (the stub is deliberately netcdf-free).
    function stub_put_att_string(ncid, varid, name, nelems, op) &
       bind(C, name='nc_put_att_string') result(cerr)
       integer(c_int), value, intent(in) :: ncid, varid
       character(kind=c_char), intent(in) :: name(*)
       integer(c_size_t), value, intent(in) :: nelems
       type(c_ptr), intent(in) :: op(*)
       integer(c_int) :: cerr
       cerr = 0_c_int
    end function stub_put_att_string
    function stub_get_att_string(ncid, varid, name, ip) &
       bind(C, name='nc_get_att_string') result(cerr)
       integer(c_int), value, intent(in) :: ncid, varid
       character(kind=c_char), intent(in) :: name(*)
       type(c_ptr), intent(out) :: ip(*)
       integer(c_int) :: cerr
       cerr = 0_c_int
    end function stub_get_att_string
    function stub_free_string(nelems, data) &
       bind(C, name='nc_free_string') result(cerr)
       integer(c_size_t), value, intent(in) :: nelems
       type(c_ptr), intent(in) :: data(*)
       integer(c_int) :: cerr
       cerr = 0_c_int
    end function stub_free_string
end module netcdf
