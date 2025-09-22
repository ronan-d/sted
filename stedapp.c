#include <gtk/gtk.h>

#include "stedapp.h"

struct _StedApp {
  GtkApplication parent;
};

G_DEFINE_TYPE(StedApp, sted_app, GTK_TYPE_APPLICATION);

static void sted_app_init(StedApp *app) {}

static void sted_app_class_init(StedAppClass *class) {}

StedApp *sted_app_new(void) {
  return g_object_new(STED_APP_TYPE, "application-id", "org.ronan-d.sted",
                      "flags", G_APPLICATION_HANDLES_OPEN, NULL);
}
