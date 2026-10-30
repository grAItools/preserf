!> Unit test for `ppser_chunk_shape`, the compression chunk derivation.
!>
!> The derivation is pure, so its contract is checked directly against
!> synthetic dims — including dims whose product cannot be written (a
!> >4 GiB variable) — instead of through a store: every result must be a
!> legal chunk (1..extent per dimension), at most
!> `PPSER_MAX_CHUNK_BYTES` of uncompressed data, and never the whole
!> multi-element variable. Single-element variables are the exception the
!> contract names explicitly: their only legal chunk is the whole variable.
!>
!> Prints `preserf-fortran: chunk-shape OK` and exits 0 only when every case
!> passes, so a ctest `PASS_REGULAR_EXPRESSION` on that marker catches a
!> regression.
program test_chunk_shape
   use, intrinsic :: iso_fortran_env, only: int64
   use utils_preserf, only: ppser_chunk_shape, PPSER_CHUNK_TARGET_BYTES, &
                            PPSER_MAX_CHUNK_BYTES
   implicit none

   ! Default integer extents; the largest is max(int32), the largest extent
   ! netCDF can express for a fixed dimension.
   integer, parameter :: huge_dim = 2147483647

   call check_rank0()
   call check_single_element()
   call check_multi_element()
   call check_large_dims()
   call check_synthetic_huge_dims()
   call check_cap()

   write (*, '(a)') 'preserf-fortran: chunk-shape OK'
contains

   !> A rank-0 variable has no chunkable dimension: the caller must keep the
   !> backend's default layout.
   subroutine check_rank0()
      integer, allocatable :: chunks(:)
      integer :: empty(0)

      chunks = ppser_chunk_shape(empty, 8)
      if (size(chunks) /= 0) error stop &
         'chunk-shape: rank-0 must return an empty shape'
   end subroutine check_rank0

   !> A single-element variable returns the whole variable, whatever its rank.
   subroutine check_single_element()
      call expect_whole([1], 8, '1-D single element')
      call expect_whole([1, 1], 4, '2-D single element')
      call expect_whole([1, 1, 1, 1], 8, '4-D single element')
   end subroutine check_single_element

   !> Multi-element variables are chunked with a shape strictly smaller than
   !> the variable, made of whole fastest-varying rows.
   subroutine check_multi_element()
      ! 4096 doubles fit the target whole; the fastest extent is halved so the
      ! variable is not one chunk.
      call expect([4096], 8, [2048], '1-D ramp')

      ! 2 elements: the fastest extent halves to the only smaller legal chunk.
      call expect([2], 4, [1], '1-D pair')

      ! A trailing extent-1 axis keeps the whole-shape check honest: the
      ! derivable shape is [1,5], halved along the extent > 1.
      call expect([1, 5], 8, [1, 2], 'leading extent-1 axis')

      ! Small rank-2 variable: the whole shape fits the target, and halving
      ! the fastest extent (3 -> 1) keeps it from being one chunk.
      call expect([3, 4], 8, [1, 4], 'small rank-2')

      ! 1024 x 1024 doubles (8 MiB): fastest rows in full, then the slower
      ! extent truncated to the target.
      call expect([1024, 1024], 8, [1024, 512], '8 MiB rank-2')
   end subroutine check_multi_element

   !> Extents beyond the target on the fastest axis alone truncate that axis.
   subroutine check_large_dims()
      ! One row of 10^9 doubles is far past the target, so the fastest axis is
      ! the one truncated (target / 8 bytes = 524288 elements).
      call expect([1000000000], 8, [524288], '1-D 10^9 extents')

      ! The fastest axis (1000 doubles = 8000 bytes) fits whole; the 10^9 slow
      ! axis is truncated to 4194304 / 8000 = 524 rows.
      call expect([1000, 1000000000], 8, [1000, 524], &
                  'rank-2 with a 10^9 slow axis')
   end subroutine check_large_dims

   !> Dimensional shapes whose element count overflows an int32 (and, for the
   !> 3-D case, an int64) never write anything, but the derivation still has
   !> to stay inside the per-chunk byte cap.
   subroutine check_synthetic_huge_dims()
      call expect([huge_dim], 8, [524288], 'huge 1-D')

      call expect([huge_dim, huge_dim], 8, [524288, 1], 'huge 2-D')

      call expect([huge_dim, huge_dim, huge_dim], 8, [524288, 1, 1], &
                  'huge 3-D')

      ! A byte per element fills the target with more elements.
      call expect([huge_dim, huge_dim], 1, [4194304, 1], &
                  'huge 2-D, byte elements')
   end subroutine check_synthetic_huge_dims

   !> The target is the operative bound and must sit below the HDF5 per-chunk
   !> ceiling the contract requires.
   subroutine check_cap()
      if (PPSER_CHUNK_TARGET_BYTES > PPSER_MAX_CHUNK_BYTES) error stop &
         'chunk-shape: target exceeds the per-chunk byte cap'
      if (PPSER_MAX_CHUNK_BYTES /= 4_int64 * 1024_int64**3) error stop &
         'chunk-shape: per-chunk cap must be 4 GiB'
   end subroutine check_cap

   !> Assert the exact derived shape for one case, then the contract every
   !> result must satisfy.
   subroutine expect(dims, elem_bytes, wanted, label)
      integer, intent(in) :: dims(:), elem_bytes, wanted(:)
      character(len=*), intent(in) :: label
      integer, allocatable :: chunks(:)
      integer :: i

      chunks = ppser_chunk_shape(dims, elem_bytes)
      if (size(chunks) /= size(wanted)) call fail(label, 'rank mismatch')
      do i = 1, size(wanted)
         if (chunks(i) /= wanted(i)) then
            write (*, '(a,a,a,i0,a,i0)') 'chunk-shape: ', label, &
               ' mismatch at axis ', i, ': got ', chunks(i)
            error stop 'chunk-shape: derived shape differs'
         end if
      end do
      call expect_legal(chunks, dims, elem_bytes, label)
   end subroutine expect

   !> `expect_whole`: the single-element case, whose chunk is the variable.
   subroutine expect_whole(dims, elem_bytes, label)
      integer, intent(in) :: dims(:), elem_bytes
      character(len=*), intent(in) :: label
      integer, allocatable :: chunks(:)
      integer :: i

      chunks = ppser_chunk_shape(dims, elem_bytes)
      if (size(chunks) /= size(dims)) call fail(label, 'rank mismatch')
      do i = 1, size(dims)
         if (chunks(i) /= dims(i)) call fail( &
            label, 'must chunk the whole variable')
      end do
      call expect_legal(chunks, dims, elem_bytes, label)
   end subroutine expect_whole

   !> Every derived shape stays inside the dims and the per-chunk byte cap.
   subroutine expect_legal(chunks, dims, elem_bytes, label)
      integer, intent(in) :: chunks(:), dims(:), elem_bytes
      character(len=*), intent(in) :: label
      integer :: i
      integer(int64) :: bytes

      if (size(chunks) /= size(dims)) call fail(label, 'rank mismatch')
      if (size(chunks) == 0) call fail( &
         label, 'returned no shape for a ranked variable')
      bytes = max(elem_bytes, 1)
      do i = 1, size(chunks)
         if (chunks(i) < 1 .or. chunks(i) > dims(i)) call fail( &
            label, 'chunk extent outside the variable')
         bytes = bytes*int(chunks(i), int64)
      end do
      if (bytes > PPSER_MAX_CHUNK_BYTES) call fail( &
         label, 'chunk exceeds the per-chunk byte cap')
   end subroutine expect_legal

   !> Report a failed case and abort; `error stop` needs a constant code, so
   !> the diagnostic naming the case is written first.
   subroutine fail(label, what)
      character(len=*), intent(in) :: label, what
      write (*, '(a,a,a)') 'chunk-shape: '//label//' ', what
      error stop 1
   end subroutine fail

end program test_chunk_shape
