! Template body for an apply_perturb_* helper (read-perturb math). Applies
! symmetric multiplicative noise  data = data * (1 + scale*(2*r - 1)),
! r ~ U[0,1)  elementwise; a zero scale is the identity. Instantiated for
! the two floating dtypes x ranks 0-4 via PRESERF_SUB / PRESERF_DTYPE /
! PRESERF_DIMS / PRESERF_RANK. The arithmetic is carried out in real64
! (scale is real64) and converted back to the field's kind on assignment.
subroutine PRESERF_SUB(data, scale)
   PRESERF_DTYPE, intent(inout) PRESERF_DIMS :: data
   real(real64), intent(in) :: scale
#if PRESERF_RANK == 0
   PRESERF_DTYPE :: noise
#else
   PRESERF_DTYPE, allocatable PRESERF_DIMS :: noise
#endif
   if (scale == 0.0_real64) return
#if PRESERF_RANK == 0
   call random_number(noise)
#else
   allocate (noise, mold=data)
   call random_number(noise)
#endif
   ! Carry the arithmetic in the field's own kind (scale, a real64
   ! argument, is converted down for a real32 field) so the result needs
   ! no implicit narrowing on assignment.
   data = data*(1 + real(scale, kind(data))*(2*noise - 1))
end subroutine PRESERF_SUB
