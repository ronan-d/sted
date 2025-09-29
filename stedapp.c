#include <adwaita.h>

#include <assert.h>
#include <stdlib.h>

#include "functions.h"
#include "structs.h"

#include "stedapp.h"
#include "stedwindow.h"

struct _StedApp {
  AdwApplication parent;
};

G_DEFINE_TYPE(StedApp, sted_app, ADW_TYPE_APPLICATION)

static void sted_app_init(StedApp *app) {}

static void register_accel(GtkApplication *app, const char *name,
                           guint key_code) {

  char *accel = gtk_accelerator_name(key_code, 0);
  const char *accels[] = {accel, NULL};

  const char *prefix = "win.";

  char *qualified_name = malloc(strlen(prefix) + strlen(name) + 1);
  assert(qualified_name != NULL);

  char *cursor = qualified_name;

  cursor = stpcpy(cursor, prefix);
  cursor = stpcpy(cursor, name);

  gtk_application_set_accels_for_action(app, qualified_name, accels);

  free(qualified_name);
}

static void sted_app_activate(GApplication *app) {
  StedWindow *win = sted_window_new(GTK_APPLICATION(app));

  register_accel(GTK_APPLICATION(app), "open-num-dialog", GDK_KEY_a);
  register_accel(GTK_APPLICATION(app), "go-left", GDK_KEY_h);
  register_accel(GTK_APPLICATION(app), "go-down", GDK_KEY_j);
  register_accel(GTK_APPLICATION(app), "go-up", GDK_KEY_k);
  register_accel(GTK_APPLICATION(app), "go-right", GDK_KEY_l);
  register_accel(GTK_APPLICATION(app), "make-into-hole", GDK_KEY_f);
  register_accel(GTK_APPLICATION(app), "insert-before", GDK_KEY_s);
  register_accel(GTK_APPLICATION(app), "insert-after", GDK_KEY_d);
  register_accel(GTK_APPLICATION(app), "remove-cursor-node", GDK_KEY_r);

  gtk_window_present(GTK_WINDOW(win));
}

static void sted_app_class_init(StedAppClass *class) {
  G_APPLICATION_CLASS(class)->activate = sted_app_activate;
}

StedApp *sted_app_new(void) {
  return g_object_new(STED_APP_TYPE, "application-id", "org.ronan-d.sted",
                      "flags", G_APPLICATION_NON_UNIQUE, NULL);
}
