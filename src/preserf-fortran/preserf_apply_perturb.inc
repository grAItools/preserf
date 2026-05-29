! Template body for an apply_perturb_* helper (read-perturb math). Applies
! symmetric multiplicative noise  data = data * (1 + scale*(2*r - 1)),
! r ~ U[0,1)  elementwise; a zero scale is the identity. Instantiated for
! the two floating dtypes x ranks 0-4 via PRESERF_SUB / PRESERF_DTYPE /
! PRESERF_DIMS / PRESERF_RANK.
!
! A single scalar random value is held at a time (rank-specific in-place
! loops), so peak memory is the field itself — no full-size scratch
! array. The arithmetic is carried out in the field's own kind (scale, a
! real64 argument, is converted down for a real32 field) so the result
! needs no implicit narrowing on assignment.
subroutine PRESERF_SUB(data, scale)
   PRESERF_DTYPE, intent(inout) PRESERF_DIMS :: data
   real(real64), intent(in) :: scale
   PRESERF_DTYPE :: rv
#if PRESERF_RANK >= 1
   integer :: i1
#endif
#if PRESERF_RANK >= 2
   integer :: i2
#endif
#if PRESERF_RANK >= 3
   integer :: i3
#endif
#if PRESERF_RANK >= 4
   integer :: i4
#endif
   if (scale == 0.0_real64) return
#if PRESERF_RANK == 0
   call random_number(rv)
   data = data*(1 + real(scale, kind(data))*(2*rv - 1))
#elif PRESERF_RANK == 1
   do i1 = 1, size(data, 1)
      call random_number(rv)
      data(i1) = data(i1)*(1 + real(scale, kind(data))*(2*rv - 1))
   end do
#elif PRESERF_RANK == 2
   do i2 = 1, size(data, 2)
      do i1 = 1, size(data, 1)
         call random_number(rv)
         data(i1, i2) = data(i1, i2)*(1 + real(scale, kind(data))*(2*rv - 1))
      end do
   end do
#elif PRESERF_RANK == 3
   do i3 = 1, size(data, 3)
      do i2 = 1, size(data, 2)
         do i1 = 1, size(data, 1)
            call random_number(rv)
            data(i1, i2, i3) = data(i1, i2, i3)* &
                               (1 + real(scale, kind(data))*(2*rv - 1))
         end do
      end do
   end do
#elif PRESERF_RANK == 4
   do i4 = 1, size(data, 4)
      do i3 = 1, size(data, 3)
         do i2 = 1, size(data, 2)
            do i1 = 1, size(data, 1)
               call random_number(rv)
               data(i1, i2, i3, i4) = data(i1, i2, i3, i4)* &
                                      (1 + real(scale, kind(data))*(2*rv - 1))
            end do
         end do
      end do
   end do
#endif
end subroutine PRESERF_SUB
