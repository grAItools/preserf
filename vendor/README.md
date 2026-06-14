# vendor/

This directory contains upstream source files kept for **reference only**.
They are not part of the preserf distribution and are not included in the
wheel or sdist.

## Contents

| File        | Origin                                                         | License | Purpose                                                                                                                                             |
| ----------- | -------------------------------------------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pp_ser.py` | [MeteoSwiss/serialbox](https://github.com/GridTools/serialbox) | GPL     | Reference implementation of the pp_ser preprocessor. Kept so the preserf preprocessor can be validated against the upstream behaviour. Not shipped. |

The GPL license of `pp_ser.py` applies only to this file and does not
affect preserf (MIT). Do not import or include this file in any
distributed artifact.
