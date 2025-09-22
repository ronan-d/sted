#include <gtk/gtk.h>
#include <gtksourceview/gtksource.h>

#include <assert.h>
#include <stdlib.h>

#include "functions.h"
#include "structs.h"

static void *srcprg;

struct renderer {
  GtkTextBuffer *buffer;
  GtkTextTag *tag;
};

static struct renderer renderer;

static void render_frame(struct renderer renderer, struct frame frame) {
  gtk_text_buffer_set_text(renderer.buffer, frame.text, frame.len);

  GtkTextIter start, end;
  gtk_text_buffer_get_iter_at_line_index(renderer.buffer, &start, 0,
                                         frame.start_offset);
  gtk_text_buffer_get_iter_at_line_index(renderer.buffer, &end, 0,
                                         frame.end_offset);

  gtk_text_buffer_apply_tag(renderer.buffer, renderer.tag, &start, &end);
}

#define declare_cb(cmd)                                                        \
  static void cmd##_cb(GSimpleAction *action, GVariant *parameter,             \
                       gpointer ptr) {                                         \
    const struct frame frame = execute(srcprg, cmd);                           \
    render_frame(renderer, frame);                                             \
  }

declare_cb(go_left);
declare_cb(go_down);
declare_cb(go_up);
declare_cb(go_right);
declare_cb(make_into_hole);
declare_cb(insert_before);
declare_cb(insert_after);

static void register_accel(GtkApplication *app, const char *name,
                           guint key_code) {

  char *accel = gtk_accelerator_name(key_code, 0);
  const char *accels[] = {accel, NULL};

  const char *prefix = "app.";

  char *qualified_name = malloc(strlen(prefix) + strlen(name) + 1);
  assert(qualified_name != NULL);

  char *cursor = qualified_name;

  cursor = stpcpy(cursor, prefix);
  cursor = stpcpy(cursor, name);

  gtk_application_set_accels_for_action(app, qualified_name, accels);

  free(qualified_name);
}

const static GActionEntry app_entries[] = {
    {"go-left", go_left_cb, NULL, NULL, NULL},
    {"go-down", go_down_cb, NULL, NULL, NULL},
    {"go-up", go_up_cb, NULL, NULL, NULL},
    {"go-right", go_right_cb, NULL, NULL, NULL},
    {"make-into-hole", make_into_hole_cb, NULL, NULL, NULL},
    {"insert-before", insert_before_cb, NULL, NULL, NULL},
    {"insert-after", insert_after_cb, NULL, NULL, NULL}};

static void activate(GtkApplication *app, gpointer user_data) {
  GtkWidget *window;
  GtkWidget *button;

  window = gtk_application_window_new(app);
  gtk_window_set_title(GTK_WINDOW(window), "Hello");
  gtk_window_set_default_size(GTK_WINDOW(window), 200, 200);

  GtkWidget *text_view = gtk_source_view_new();
  gtk_text_view_set_editable(GTK_TEXT_VIEW(text_view), false);
  gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(text_view), false);
  gtk_text_view_set_monospace(GTK_TEXT_VIEW(text_view), true);

  GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));

  GtkTextTag *tag = gtk_text_buffer_create_tag(
      buffer, "cursor-tag", "underline", PANGO_UNDERLINE_SINGLE, NULL);

  renderer = (struct renderer){.buffer = buffer, .tag = tag};

  gtk_window_set_child(GTK_WINDOW(window), text_view);

  gtk_window_present(GTK_WINDOW(window));

  srcprg = create_srcprg();
  if (srcprg == NULL) {
    exit(EXIT_FAILURE);
  }

  const struct frame frame = execute(srcprg, do_nothing);

  render_frame(renderer, frame);

  g_action_map_add_action_entries(G_ACTION_MAP(app), app_entries,
                                  G_N_ELEMENTS(app_entries), app);

  register_accel(app, "go-left", GDK_KEY_h);
  register_accel(app, "go-down", GDK_KEY_j);
  register_accel(app, "go-up", GDK_KEY_k);
  register_accel(app, "go-right", GDK_KEY_l);
  register_accel(app, "make-into-hole", GDK_KEY_f);
  register_accel(app, "insert-before", GDK_KEY_s);
  register_accel(app, "insert-after", GDK_KEY_d);
}

int main(int argc, char **argv) {
  GtkApplication *app;
  int status;

  app = gtk_application_new("org.ronan-d.sted", G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
  status = g_application_run(G_APPLICATION(app), argc, argv);
  g_object_unref(app);

  return status;
}
