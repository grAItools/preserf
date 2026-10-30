!> Perf-smoke fixtures for the store-efficiency work.
!>
!> `baseline` writes one representative large `real(real64)` field through
!> both supported backends (netcdf4 and nczarr-v2) with no compression
!> request, re-reads it, and reports the raw field bytes, the netcdf4 store
!> size, and the write / read wall times. `compressed` repeats the netcdf4
!> run with the store-wide compression knob (the nczarr-v2 combination is
!> rejected at initialization until its codec support lands, issue #111).
!> The nczarr-v2 directory size is summed by
!> `tests/integration_tests/test_perf_smoke.py`, which also asserts the
!> reported read wall times against a budget — a Fortran `inquire` cannot
!> size a directory store portably.
!>
!> `perturb-timing` measures the read-perturb path on the same field and
!> compares its RNG-and-formula overhead with an in-fixture per-element
!> pass, so per-element versus batched drawing is distinguishable on the
!> same machine and in the same run.
!>
!> Prints machine-readable `preserf-perf: ...` metric lines followed by the
!> scenario's `... OK` marker; a ctest `PASS_REGULAR_EXPRESSION` on the
!> marker catches a regression in the fixture or the runtime.
program test_perf_smoke
   use, intrinsic :: iso_fortran_env, only: int64, real64, error_unit
   use utils_ppser
   use m_serialize
   implicit none

   ! Representative large field: 2**24 doubles (128 MiB) as 16384 x 1024.
   ! The fastest extent is larger than the perturb chunk (8192), so the
   ! batched path draws two chunks per row.
   integer, parameter :: perf_ni = 16384
   integer, parameter :: perf_nj = 1024
   integer, parameter :: perf_n = perf_ni*perf_nj
   integer, parameter :: perf_perturb_chunk = 8192
   integer, parameter :: timing_reps = 5

   character(len=:), allocatable :: out_dir, scenario
   real(real64), allocatable :: data(:, :), back(:, :)
   real(real64) :: write_s, read_s

   call parse_args(out_dir, scenario)
   allocate (data(perf_ni, perf_nj), back(perf_ni, perf_nj))

   select case (scenario)
   case ('baseline')
      call fill_ramp(data)
      call run_store('netcdf4', 'fperf4', .false., data, back, &
                     write_s, read_s)
      call report_store('baseline', 'netcdf4', 'fperf4', .false., &
                        write_s, read_s)
      call run_store('nczarr-v2', 'fperfz', .false., data, back, &
                     write_s, read_s)
      call report_store('baseline', 'nczarr-v2', 'fperfz', .false., &
                        write_s, read_s)
      write (*, '(a)') 'preserf-perf: baseline OK'
   case ('compressed')
      ! A repeating ramp is highly compressible, so the deflated store's
      ! size is a meaningful contrast against the raw field bytes.
      call fill_pattern(data)
      call run_store('netcdf4', 'fpcomp', .true., data, back, &
                     write_s, read_s)
      call report_store('compressed', 'netcdf4', 'fpcomp', .true., &
                        write_s, read_s)
      write (*, '(a)') 'preserf-perf: compressed OK'
   case ('perturb-timing')
      call fill_ramp(data)
      call time_perturb(data, back)
      write (*, '(a)') 'preserf-perf: perturb-timing OK'
   case default
      write (error_unit, '(a,a,a)') "preserf-perf: unknown scenario '", &
         scenario, "' (expected baseline, compressed, or perturb-timing)"
      error stop 1
   end select
contains

   !> Read the output directory and scenario from argv.
   subroutine parse_args(dir, name)
      character(len=:), allocatable, intent(out) :: dir, name
      integer :: arg_len, arg_stat
      character(len=:), allocatable :: buf

      if (command_argument_count() /= 2) then
         write (error_unit, '(a)') &
            'usage: test_perf_smoke <output_dir> <scenario>'
         error stop 1
      end if
      call get_command_argument(1, length=arg_len, status=arg_stat)
      if (arg_stat /= 0) error stop 'preserf-perf: argv(1) length failed'
      allocate (character(len=arg_len) :: buf)
      call get_command_argument(1, value=buf, status=arg_stat)
      if (arg_stat /= 0) error stop 'preserf-perf: argv(1) value failed'
      dir = buf
      call get_command_argument(2, length=arg_len, status=arg_stat)
      if (arg_stat /= 0) error stop 'preserf-perf: argv(2) length failed'
      deallocate (buf)
      allocate (character(len=arg_len) :: buf)
      call get_command_argument(2, value=buf, status=arg_stat)
      if (arg_stat /= 0) error stop 'preserf-perf: argv(2) value failed'
      name = buf
   end subroutine parse_args

   !> Exact, strictly increasing values (1..N) so a lossy or misordered
   !> round-trip changes at least one element.
   subroutine fill_ramp(field)
      real(real64), intent(out) :: field(:, :)
      integer :: i, j
      do j = 1, perf_nj
         do i = 1, perf_ni
            field(i, j) = real(i + perf_ni*(j - 1), real64)
         end do
      end do
   end subroutine fill_ramp

   !> Repeating 0..127 pattern: exactly representable doubles whose bit
   !> patterns recur every 128 elements, so deflate compresses visibly.
   subroutine fill_pattern(field)
      real(real64), intent(out) :: field(:, :)
      integer :: i, j
      do j = 1, perf_nj
         do i = 1, perf_ni
            field(i, j) = real(mod(i + perf_ni*(j - 1), 128), real64)
         end do
      end do
   end subroutine fill_pattern

   !> Write the field through one backend, then read it back and assert it
   !> round-trips exactly. Timings cover the write session and a single
   !> read session; allocation and verification are outside the timed
   !> regions.
   subroutine run_store(backend, prefix, compress, field, readback, &
                        write_s, read_s)
      character(len=*), intent(in) :: backend, prefix
      logical, intent(in) :: compress
      real(real64), intent(in) :: field(:, :)
      real(real64), intent(out) :: readback(:, :)
      real(real64), intent(out) :: write_s, read_s
      integer(int64) :: c0, c1
      integer :: rate

      call system_clock(c0, rate)
      if (compress) then
         call ppser_initialize(out_dir, prefix, 'w', backend=backend, &
                               compression=1)
      else
         call ppser_initialize(out_dir, prefix, 'w', backend=backend)
      end if
      call fs_register_field(ppser_serializer, 'perf', 'double', &
                             ppser_reallength, perf_ni, perf_nj, 0, 0, &
                             0, 0, 0, 0, 0, 0, 0, 0)
      call fs_create_savepoint('step', ppser_savepoint)
      call fs_write_field(ppser_serializer, ppser_savepoint, 'perf', field)
      call ppser_finalize()
      call system_clock(c1, rate)
      write_s = elapsed(c0, c1, rate)

      call system_clock(c0, rate)
      call ppser_initialize(out_dir, prefix, 'r', backend=backend)
      call fs_register_field(ppser_serializer, 'perf', 'double', &
                             ppser_reallength, perf_ni, perf_nj, 0, 0, &
                             0, 0, 0, 0, 0, 0, 0, 0)
      call fs_create_savepoint('step', ppser_savepoint)
      call fs_read_field(ppser_serializer, ppser_savepoint, 'perf', readback)
      call ppser_finalize()
      call system_clock(c1, rate)
      read_s = elapsed(c0, c1, rate)

      if (any(readback /= field)) then
         write (error_unit, '(a,a,a)') 'preserf-perf: ', backend, &
            ' read-back mismatch'
         error stop 1
      end if
   end subroutine run_store

   !> Print one metric line for the store just measured, asserting the
   !> netcdf4 store size: the default-off baseline is the uncompressed raw
   !> payload plus a small header, and the compressed store is at most half
   !> the raw payload for the repeating-ramp field. A directory store
   !> reports -1; the Python perf test sums its files.
   subroutine report_store(scenario_name, backend, prefix, compress, &
                           write_s, read_s)
      character(len=*), intent(in) :: scenario_name, backend, prefix
      logical, intent(in) :: compress
      real(real64), intent(in) :: write_s, read_s
      integer(int64) :: store_bytes, raw_bytes, with_header
      character(len=:), allocatable :: path
      integer :: ios

      raw_bytes = int(perf_n, int64)*8_int64
      if (backend == 'netcdf4') then
         path = trim(out_dir)//'/'//trim(prefix)//'.nc'
         inquire (file=path, size=store_bytes, iostat=ios)
         if (ios /= 0) error stop 'preserf-perf: inquire store failed'
         if (compress) then
            ! Deflate must earn its keep: the pattern field's repeated bit
            ! patterns shrink well below the raw payload.
            if (store_bytes >= raw_bytes/2_int64) error stop &
               'preserf-perf: compressed store is not smaller than raw/2'
         else
            ! Contiguous default layout: the payload is exactly the raw
            ! bytes, so anything beyond a 1 MiB header allowance means the
            ! default path started padding or compressing.
            with_header = raw_bytes + 1048576_int64
            if (store_bytes < raw_bytes) error stop &
               'preserf-perf: default store smaller than the raw field'
            if (store_bytes > with_header) error stop &
               'preserf-perf: default store exceeds raw field + header'
         end if
      else
         store_bytes = -1_int64
      end if
      write (*, '(a,a,a,a,a,i0,a,i0,a,i0,a,f0.4,a,f0.4)') &
         'preserf-perf: scenario=', scenario_name, ' backend=', backend, &
         ' elements=', perf_n, ' raw_bytes=', raw_bytes, &
         ' store_bytes=', store_bytes, &
         ' write_s=', write_s, ' read_s=', read_s
   end subroutine report_store

   !> Time the read-perturb path against a per-element RNG-and-formula pass
   !> on the same field. The production apply step receives one uniform per
   !> element either way, so the only difference is RNG call overhead: a
   !> batched implementation must cost less than 90% of the per-element
   !> pass, while an element-at-a-time helper lands at roughly 100%.
   subroutine time_perturb(field, readback)
      real(real64), intent(in) :: field(:, :)
      real(real64), intent(out) :: readback(:, :)
      real(real64), allocatable :: work(:, :)
      real(real64) :: per_element_s, batched_s, plain_s, perturb_s
      real(real64) :: overhead_s, scale, warm_write_s, warm_read_s

      allocate (work(perf_ni, perf_nj))
      scale = 0.1_real64

      ! Write the store once, then warm the page cache so the timed reads
      ! measure the runtime path rather than first-touch disk I/O.
      call run_store('netcdf4', 'fpertperf', .false., field, readback, &
                     warm_write_s, warm_read_s)
      call ppser_initialize(out_dir, 'fpertperf', 'r')
      call fs_register_field(ppser_serializer, 'perf', 'double', &
                             ppser_reallength, perf_ni, perf_nj, 0, 0, &
                             0, 0, 0, 0, 0, 0, 0, 0)
      call fs_create_savepoint('step', ppser_savepoint)
      call fs_read_field(ppser_serializer, ppser_savepoint, 'perf', readback)
      plain_s = min_read_s(0.0_real64)
      perturb_s = min_read_s(scale)
      if (any(readback < field*0.9_real64 .or. readback > field*1.1_real64)) &
         error stop 'preserf-perf: perturbed read left the bounds'
      call ppser_finalize()
      overhead_s = perturb_s - plain_s

      per_element_s = min_per_element_s(field, work, scale)
      batched_s = min_batched_s(field, work, scale)

      write (*, '(a,i0,a,f0.4,a,f0.4,a,f0.4,a,f0.4,a,f0.4)') &
         'preserf-perf: scenario=perturb-timing backend=netcdf4 elements=', &
         perf_n, ' per_element_s=', per_element_s, &
         ' batched_reference_s=', batched_s, ' plain_read_s=', plain_s, &
         ' perturb_read_s=', perturb_s, ' apply_overhead_s=', overhead_s

      if (batched_s >= 0.9_real64*per_element_s) error stop &
         'preserf-perf: batched reference is not faster than per-element'
      if (overhead_s >= 0.9_real64*per_element_s) error stop &
         'preserf-perf: perturb read applies draws per element (not batched)'
   end subroutine time_perturb

   !> Smallest wall time over `timing_reps` read-perturb passes at `scale`;
   !> `scale` 0.0 measures the plain read. Assumes the read-mode session is
   !> already open with the field registered and the savepoint created.
   function min_read_s(scale) result(best)
      real(real64), intent(in) :: scale
      real(real64) :: best, t
      integer(int64) :: c0, c1
      integer :: rate, rep

      best = huge(1.0_real64)
      do rep = 1, timing_reps
         call system_clock(c0, rate)
         if (scale == 0.0_real64) then
            call fs_read_field(ppser_serializer, ppser_savepoint, 'perf', &
                               back)
         else
            call fs_read_field(ppser_serializer, ppser_savepoint, 'perf', &
                               back, scale)
         end if
         call system_clock(c1, rate)
         t = elapsed(c0, c1, rate)
         best = min(best, t)
      end do
   end function min_read_s

   !> Smallest wall time of one element-at-a-time RNG + formula pass over
   !> `field`. One `random_number` call per element reproduces the shape of
   !> the per-element implementation the batching replaces.
   function min_per_element_s(field, work, scale) result(best)
      real(real64), intent(in) :: field(:, :), scale
      real(real64), intent(inout) :: work(:, :)
      real(real64) :: best, t, draw
      integer(int64) :: c0, c1
      integer :: rate, rep, i, j

      best = huge(1.0_real64)
      do rep = 1, timing_reps
         work = field
         call system_clock(c0, rate)
         do j = 1, perf_nj
            do i = 1, perf_ni
               call random_number(draw)
               work(i, j) = work(i, j)*(1 + scale*(2*draw - 1))
            end do
         end do
         call system_clock(c1, rate)
         t = elapsed(c0, c1, rate)
         best = min(best, t)
      end do
      if (work(1, 1) == field(1, 1)) error stop &
         'preserf-perf: per-element reference did not perturb'
   end function min_per_element_s

   !> Smallest wall time of a batched RNG + formula pass over `field`,
   !> drawn along the fastest dimension in `perf_perturb_chunk` chunks —
   !> the shape of the runtime's batched helper.
   function min_batched_s(field, work, scale) result(best)
      real(real64), intent(in) :: field(:, :), scale
      real(real64), intent(inout) :: work(:, :)
      real(real64) :: best, t, rbuf(perf_perturb_chunk)
      integer(int64) :: c0, c1
      integer :: rate, rep, i, j, k, n

      best = huge(1.0_real64)
      do rep = 1, timing_reps
         work = field
         call system_clock(c0, rate)
         do j = 1, perf_nj
            do i = 1, perf_ni, perf_perturb_chunk
               n = min(perf_perturb_chunk, perf_ni - i + 1)
               call random_number(rbuf(1:n))
               do k = 1, n
                  work(i + k - 1, j) = work(i + k - 1, j)* &
                                       (1 + scale*(2*rbuf(k) - 1))
               end do
            end do
         end do
         call system_clock(c1, rate)
         t = elapsed(c0, c1, rate)
         best = min(best, t)
      end do
      if (work(1, 1) == field(1, 1)) error stop &
         'preserf-perf: batched reference did not perturb'
   end function min_batched_s

   !> Elapsed seconds between two `system_clock` ticks.
   function elapsed(c0, c1, rate) result(seconds)
      integer(int64), intent(in) :: c0, c1
      integer, intent(in) :: rate
      real(real64) :: seconds

      seconds = real(c1 - c0, real64)/real(rate, real64)
   end function elapsed
end program test_perf_smoke
