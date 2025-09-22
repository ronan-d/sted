#pragma once

#include "structs.h"

void *create_srcprg(void);

struct frame execute(void *srcprg, enum instruction instr);
