! Template body for an apply_perturb_* helper (read-perturb math). Applies
! symmetric multiplicative noise  data = data * (1 + scale*(2*r - 1)),
! r ~ U[0,1)  elementwise; a zero scale is the identity. Instantiated for
! the two floating dtypes x ranks 0-4 via PRESERF_SUB / PRESERF_DTYPE /
! PRESERF_DIMS / PRESERF_RANK.
!
! Random values are drawn in chunks of at most PERTURB_CHUNK elements —
! one `random_number(chunk)` call per chunk, along the fastest-varying
! dimension — and combined elementwise within the chunk. Every element
! still receives its own uniform draw, so the distribution and the
! multiplicative bounds match per-element drawing; the call overhead is
! amortized instead. Peak memory is the field plus the bounded scratch.
!
! The arithmetic is carried out in the field's own kind (scale, a real64
! argument, is converted down for a real32 field) so the result needs no
! implicit narrowing on assignment.
subroutine PRESERF_SUB(data, scale)
   integer, parameter :: PERTURB_CHUNK = 8192
   PRESERF_DTYPE, intent(inout) PRESERF_DIMS :: data
   real(real64), intent(in) :: scale
   PRESERF_DTYPE :: sc
#if PRESERF_RANK == 0
   PRESERF_DTYPE :: draw
#elif PRESERF_RANK == 1
   PRESERF_DTYPE :: rbuf(PERTURB_CHUNK)
   integer :: n, i1, k
#elif PRESERF_RANK == 2
   PRESERF_DTYPE :: rbuf(PERTURB_CHUNK)
   integer :: n, i1, i2, k
#elif PRESERF_RANK == 3
   PRESERF_DTYPE :: rbuf(PERTURB_CHUNK)
   integer :: n, i1, i2, i3, k
#elif PRESERF_RANK == 4
   PRESERF_DTYPE :: rbuf(PERTURB_CHUNK)
   integer :: n, i1, i2, i3, i4, k
#endif
   if (scale == 0.0_real64) return
   sc = real(scale, kind(data))
#if PRESERF_RANK == 0
   call random_number(draw)
   data = data*(1 + sc*(2*draw - 1))
#elif PRESERF_RANK == 1
   do i1 = 1, size(data, 1), PERTURB_CHUNK
      n = min(PERTURB_CHUNK, size(data, 1) - i1 + 1)
      call random_number(rbuf(1:n))
      do k = 1, n
         data(i1 + k - 1) = data(i1 + k - 1)*(1 + sc*(2*rbuf(k) - 1))
      end do
   end do
#elif PRESERF_RANK == 2
   do i2 = 1, size(data, 2)
      do i1 = 1, size(data, 1), PERTURB_CHUNK
         n = min(PERTURB_CHUNK, size(data, 1) - i1 + 1)
         call random_number(rbuf(1:n))
         do k = 1, n
            data(i1 + k - 1, i2) = data(i1 + k - 1, i2)* &
                                   (1 + sc*(2*rbuf(k) - 1))
         end do
      end do
   end do
#elif PRESERF_RANK == 3
   do i3 = 1, size(data, 3)
      do i2 = 1, size(data, 2)
         do i1 = 1, size(data, 1), PERTURB_CHUNK
            n = min(PERTURB_CHUNK, size(data, 1) - i1 + 1)
            call random_number(rbuf(1:n))
            do k = 1, n
               data(i1 + k - 1, i2, i3) = data(i1 + k - 1, i2, i3)* &
                                          (1 + sc*(2*rbuf(k) - 1))
            end do
         end do
      end do
   end do
#elif PRESERF_RANK == 4
   do i4 = 1, size(data, 4)
      do i3 = 1, size(data, 3)
         do i2 = 1, size(data, 2)
            do i1 = 1, size(data, 1), PERTURB_CHUNK
               n = min(PERTURB_CHUNK, size(data, 1) - i1 + 1)
               call random_number(rbuf(1:n))
               do k = 1, n
                  data(i1 + k - 1, i2, i3, i4) = data(i1 + k - 1, i2, i3, i4)* &
                                                 (1 + sc*(2*rbuf(k) - 1))
               end do
            end do
         end do
      end do
   end do
#endif
end subroutine PRESERF_SUB
