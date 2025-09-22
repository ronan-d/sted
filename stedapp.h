#pragma once

#include <gtk/gtk.h>

#define STED_APP_TYPE (sted_app_get_type())
G_DECLARE_FINAL_TYPE(StedApp, sted_app, STED, APP, GtkApplication)

StedApp *sted_app_new(void);
