!> preserf example: iterated Laplacian of a trigonometric field (time loop).
!>
!> This file is preprocessor *input*: it carries raw `!$SER` directives and
!> is fed through the `preserf` CLI by `run.sh` at build time. The generated
!> Fortran is compiled against the `preserf_fortran` helper (see
!> CMakeLists.txt), run, and its store is read back / verified / plotted by
!> `plot.py`.
!>
!> The initial field is phi(x,y) = sin(2x) * cos(3y) sampled on a 100x100 grid
!> over the periodic domain [0, 2*pi)^2. A short time loop then applies the
!> 5-point Laplacian repeatedly (the output of one step is the input of the
!> next), dumping the input field `phi` and its Laplacian `lap` at every step.
!> `plot.py` reloads the initial field, re-runs the same iteration in numpy,
!> and checks that every dumped step matches.
program preserf_laplacian
   use, intrinsic :: iso_fortran_env, only: real64
   implicit none

   ! Names the `IJ` register shortcut expands into (storage_mapping.md §4
   ! halo convention). nboundlines = 0 keeps the field halo-free.
   integer, parameter :: ie = 100, je = 100, nboundlines = 0
   ! Number of Laplacian iterations when no count is given on the command line.
   integer, parameter :: default_nsteps = 3
   real(real64), parameter :: pi = acos(-1.0_real64)
   real(real64), parameter :: h = 2.0_real64*pi/real(ie, real64)

   character(len=:), allocatable :: outdir
   character(len=32) :: nsteps_arg
   integer :: arg_len, arg_stat, nsteps, t
   real(real64) :: phi(ie, je), lap(ie, je)
   real(real64) :: x, y
   integer :: i, j, ip, im, jp, jm

   ! --- arg 1: output directory (required) ---
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

   ! --- arg 2: number of Laplacian iterations (optional, default 3) ---
   ! Use command_argument_count() to decide presence: a missing argument and a
   ! genuine retrieval error both yield a positive status, so falling back on
   ! any non-zero status would silently mask a real failure (e.g. a value
   ! truncated into nsteps_arg, which reports status -1).
   nsteps = default_nsteps
   if (command_argument_count() >= 2) then
      call get_command_argument(2, value=nsteps_arg, status=arg_stat)
      if (arg_stat /= 0) then
         write (*, '(a)') 'preserf example: failed to read step-count argument'
         error stop 1
      end if
      read (nsteps_arg, *, iostat=arg_stat) nsteps
      if (arg_stat /= 0 .or. nsteps < 1) then
         write (*, '(a)') 'preserf example: invalid step count (expected a positive integer)'
         error stop 1
      end if
   end if

   ! Initialise phi(i,j) = sin(2*x) * cos(3*y) on a periodic [0, 2*pi)^2 grid.
   do j = 1, je
      y = real(j - 1, real64)*h
      do i = 1, ie
         x = real(i - 1, real64)*h
         phi(i, j) = sin(2.0_real64*x)*cos(3.0_real64*y)
      end do
   end do

   ! Serialization setup runs ONCE, above the time loop: open the store and
   ! register the two fields. The loop below only writes savepoints.
   !$SER INIT directory=outdir prefix="laplacian" mode="w"
   !$SER REGISTER phi real IJ
   !$SER REGISTER lap real IJ

   ! Time loop: apply the 5-point Laplacian (periodic wrap on all four
   ! neighbours) repeatedly, dumping the input field and its Laplacian at
   ! each step. The output then becomes the next step's input.
   do t = 1, nsteps
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

      !$SER SAVEPOINT fields step=t
      !$SER DATA phi=phi
      !$SER DATA lap=lap

      ! Apply the operator repeatedly: this step's output is the next input.
      phi = lap
   end do

   !$SER CLEANUP

   write (*, '(a)') 'preserf example: laplacian OK'
end program preserf_laplacian
