#pragma once

#include <adwaita.h>

#define STED_APP_TYPE (sted_app_get_type())
G_DECLARE_FINAL_TYPE(StedApp, sted_app, STED, APP, AdwApplication)

StedApp *sted_app_new(void);
