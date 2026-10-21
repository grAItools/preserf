!> Int8 (64-bit default-integer) variant of the OPTION guard scenario.
!>
!> Compiled with `-fdefault-integer-8` and linked against the int8 build
!> of the helper library (see netcdf_stub_i8.f90 for why that build needs
!> a stub netcdf module). Under the flag a default-kind integer is 8
!> bytes wide, so a verbosity below the int32 lower bound (for example
!> -2**40) is representable and reaches `fs_Option`'s int32 boundary
!> guard — the exact silent int64-to-int32 wrap path onto the wire
!> attribute that the guard exists to reject. Under the normal int4
!> build no default-kind value can exceed huge(0_int32), so this
!> scenario cannot run there (the repo documented that when the wire
!> cast guards landed).
!>
!> The ctest scenario asserts the abort message via
!> PASS_REGULAR_EXPRESSION; a clean exit prints a non-matching line so
!> the test fails, catching a guard that silently accepts.
program test_option_i8
   use, intrinsic :: iso_fortran_env, only: error_unit
   use utils_preserf, only: ppser_serializer, ppser_initialize
   use m_preserf, only: fs_Option
   implicit none
   character(len=:), allocatable :: out_dir
   integer :: arg_len, arg_stat

   call get_command_argument(1, length=arg_len, status=arg_stat)
   if (arg_stat /= 0) then
      write (error_unit, '(a)') &
         'test_option_i8: get_command_argument(1,length) failed'
      error stop 1
   end if
   allocate (character(len=arg_len) :: out_dir)
   call get_command_argument(1, value=out_dir, status=arg_stat)
   if (arg_stat /= 0) then
      write (error_unit, '(a)') &
         'test_option_i8: get_command_argument(1,value) failed'
      error stop 1
   end if

   ! Open a writable session so fs_Option's guard branch (which only
   ! fires on a writable serializer) is live, then call it with a
   ! verbosity below the int32 lower bound. The int8 build's netcdf
   ! layer is the stub, so no real store is created; the abort happens
   ! before any netcdf call.
   call ppser_initialize(out_dir, 'fi8opt', 'w')
   call fs_Option(verbosity=-2**40)

   ! Reached only if the guard regressed: emit a non-matching line so
   ! PASS_REGULAR_EXPRESSION fails.
   write (*, '(a)') &
      'test_option_i8: FAILED (fs_Option accepted an out-of-range verbosity)'
   stop
end program test_option_i8
