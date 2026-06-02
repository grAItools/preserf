!> preserf example: Laplacian of a trigonometric field on a periodic grid.
!>
!> This file is preprocessor *input*: it carries raw `!$SER` directives and
!> is fed through the `preserf` CLI by `run.sh` at build time. The generated
!> Fortran is compiled against the `preserf_fortran` helper (see
!> CMakeLists.txt), run, and its store is read back / plotted by `plot.py`.
!>
!> The field is phi(x,y) = sin(2x) * cos(3y) sampled on a 100x100 grid over
!> the periodic domain [0, 2*pi)^2. Its continuous Laplacian is
!>   d2/dx2 + d2/dy2 = (-4 - 9) * phi = -13 * phi,
!> so the discrete 5-point result should match -13*phi to O(h^2). `plot.py`
!> reports that error as a sanity check on the round-trip.
program preserf_laplacian
   use, intrinsic :: iso_fortran_env, only: real64
   implicit none

   ! Names the `IJ` register shortcut expands into (storage_mapping.md §4
   ! halo convention). nboundlines = 0 keeps the field halo-free.
   integer, parameter :: ie = 100, je = 100, nboundlines = 0
   real(real64), parameter :: pi = acos(-1.0_real64)
   real(real64), parameter :: h = 2.0_real64*pi/real(ie, real64)

   character(len=:), allocatable :: outdir
   integer :: arg_len, arg_stat
   real(real64) :: phi(ie, je), lap(ie, je)
   real(real64) :: x, y
   integer :: i, j, ip, im, jp, jm

   ! Query the argument length first, then allocate exactly that size, so a
   ! deep tmp path cannot truncate into a fixed buffer and abort with a
   ! misleading "missing argument" error (mirrors the e2e fixture).
   call get_command_argument(1, length=arg_len, status=arg_stat)
   if (arg_stat /= 0) then
      write (*, '(a)') 'preserf example: missing output directory argument'
      error stop 1
   end if
   allocate (character(len=arg_len) :: outdir)
   call get_command_argument(1, value=outdir, status=arg_stat)
   if (arg_stat /= 0) then
      write (*, '(a)') 'preserf example: failed to read output directory argument'
      error stop 1
   end if

   ! Initialise phi(i,j) = sin(2*x) * cos(3*y) on a periodic [0, 2*pi)^2 grid.
   do j = 1, je
      y = real(j - 1, real64)*h
      do i = 1, ie
         x = real(i - 1, real64)*h
         phi(i, j) = sin(2.0_real64*x)*cos(3.0_real64*y)
      end do
   end do

   ! 5-point stencil Laplacian with periodic wrap on all four neighbours.
   do j = 1, je
      jp = merge(1, j + 1, j == je)
      jm = merge(je, j - 1, j == 1)
      do i = 1, ie
         ip = merge(1, i + 1, i == ie)
         im = merge(ie, i - 1, i == 1)
         lap(i, j) = (phi(ip, j) + phi(im, j) + phi(i, jp) + phi(i, jm) &
                      - 4.0_real64*phi(i, j))/h**2
      end do
   end do

   !$SER INIT directory=outdir prefix="laplacian" mode="w"
   !$SER REGISTER phi real IJ
   !$SER REGISTER lap real IJ
   !$SER SAVEPOINT fields step=0
   !$SER DATA phi=phi
   !$SER DATA lap=lap
   !$SER CLEANUP

   write (*, '(a)') 'preserf example: laplacian OK'
end program preserf_laplacian
