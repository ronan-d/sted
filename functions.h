#pragma once

#include "structs.h"

void *create_srcprg(void);

struct frame execute(void *srcprg, enum instruction instr);

struct frame replace_cursor_with_number(void *srcprg, unsigned num);

struct frame replace_cursor_with_addition(void *srcprg);

struct frame replace_cursor_with_multiplication(void *srcprg);

char *get_offers(void *srcprg);
