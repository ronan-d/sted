#pragma once

#include <adwaita.h>

#include "structs.h"

G_BEGIN_DECLS

#define STED_WINDOW_TYPE (sted_window_get_type())

G_DECLARE_FINAL_TYPE(StedWindow, sted_window, STED, WINDOW,
                     AdwApplicationWindow)

StedWindow *sted_window_new(GtkApplication *application);

void sted_window_execute(StedWindow *self, enum instruction instr);

G_END_DECLS
