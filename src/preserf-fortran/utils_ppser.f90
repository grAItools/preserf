!> Drop-in re-export of utils_preserf under Serialbox's historical name.
!>
!> pp_ser hard-codes `USE utils_ppser` in its generated output. This
!> module exists so that pp_ser output targeting Serialbox naming
!> compiles unchanged against preserf.
module utils_ppser
    use utils_preserf
    implicit none
end module utils_ppser
