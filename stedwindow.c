#include <string.h>

#include "functions.h"
#include "stedwindow.h"
#include "structs.h"

#include <gtksourceview/gtksource.h>
#include <stdlib.h>

struct renderer {
  GtkTextBuffer *buffer;
  GtkTextTag *tag;
};

struct _StedWindow {
  AdwApplicationWindow parent;

  struct renderer renderer;
  void *srcprg;
  AdwDialog *dialog;
};

static void render_frame(struct renderer renderer, struct frame frame) {
  gtk_text_buffer_set_text(renderer.buffer, frame.text, frame.len);

  GtkTextIter start, end;
  gtk_text_buffer_get_iter_at_line_index(renderer.buffer, &start, 0,
                                         frame.start_offset);
  gtk_text_buffer_get_iter_at_line_index(renderer.buffer, &end, 0,
                                         frame.end_offset);

  gtk_text_buffer_apply_tag(renderer.buffer, renderer.tag, &start, &end);
}

G_DEFINE_TYPE(StedWindow, sted_window, ADW_TYPE_APPLICATION_WINDOW)

static void sted_window_class_init(StedWindowClass *class) {}

static void process_dialog_input(GtkEntry *entry, gpointer ptr) {
  StedWindow *win = ptr;

  const char *text = gtk_entry_buffer_get_text(gtk_entry_get_buffer(entry));

  char *tailptr;
  errno = 0;
  const unsigned num = strtoul(text, &tailptr, 10);

  if (errno == 0 && tailptr != text && *tailptr == 0) {
    struct frame frame = replace_cursor_with_number(win->srcprg, num);
    render_frame(win->renderer, frame);
  }

  adw_dialog_close(win->dialog);
}

#define declare_cb(cmd)                                                        \
  static void cmd##_cb(GSimpleAction *action, GVariant *parameter,             \
                       gpointer ptr) {                                         \
    StedWindow *win = ptr;                                                     \
    sted_window_execute(win, cmd);                                             \
  }

declare_cb(go_left);
declare_cb(go_down);
declare_cb(go_up);
declare_cb(go_right);
declare_cb(make_into_hole);
declare_cb(insert_before);
declare_cb(insert_after);
declare_cb(remove_cursor_node);

static AdwDialog *create_input_dialog(StedWindow *win);

static void open_num_dialog(GSimpleAction *action, GVariant *parameter,
                            gpointer ptr) {
  StedWindow *win = ptr;

  win->dialog = create_input_dialog(win);
  adw_dialog_present(win->dialog, GTK_WIDGET(win));
}

const static GActionEntry app_entries[] = {
    {"open-num-dialog", open_num_dialog, NULL, NULL, NULL},
    {"go-left", go_left_cb, NULL, NULL, NULL},
    {"go-down", go_down_cb, NULL, NULL, NULL},
    {"go-up", go_up_cb, NULL, NULL, NULL},
    {"go-right", go_right_cb, NULL, NULL, NULL},
    {"make-into-hole", make_into_hole_cb, NULL, NULL, NULL},
    {"insert-before", insert_before_cb, NULL, NULL, NULL},
    {"insert-after", insert_after_cb, NULL, NULL, NULL},
    {"remove-cursor-node", remove_cursor_node_cb, NULL, NULL, NULL}};

static void addition_cb(GtkButton *button, gpointer ptr) {
  StedWindow *win = ptr;

  struct frame frame = replace_cursor_with_addition(win->srcprg);
  render_frame(win->renderer, frame);
  adw_dialog_close(win->dialog);
}

static void multiplication_cb(GtkButton *button, gpointer ptr) {
  StedWindow *win = ptr;

  struct frame frame = replace_cursor_with_multiplication(win->srcprg);
  render_frame(win->renderer, frame);
  adw_dialog_close(win->dialog);
}

static void number_cb(GtkButton *button, gpointer ptr) {
  StedWindow *win = ptr;

  GtkWidget *entry = gtk_entry_new();
  g_signal_connect(entry, "activate", G_CALLBACK(process_dialog_input), win);

  adw_dialog_set_child(win->dialog, entry);
  gtk_widget_grab_focus(entry);
}

static AdwDialog *create_input_dialog(StedWindow *win) {
  GtkBox *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);

  char *const offers = get_offers(win->srcprg);

  const char *cursor = offers;

  while (strlen(cursor) > 0) {
    GtkWidget *button = gtk_button_new_with_mnemonic(cursor);
    g_signal_connect(GTK_BUTTON(button), "clicked", G_CALLBACK(number_cb),
                     win); // TODO change callback
    gtk_box_append(box, button);

    cursor += strlen(cursor) + 1;
  }

  free (offers);

  AdwDialog *dialog = adw_dialog_new();

  adw_dialog_set_child(dialog, box);
  adw_dialog_set_follows_content_size(dialog, TRUE);
  adw_dialog_set_presentation_mode(dialog, ADW_DIALOG_FLOATING);

  return dialog;
}

static void sted_window_init(StedWindow *self) {
  gtk_window_set_title(GTK_WINDOW(self), "Hello");
  gtk_window_set_default_size(GTK_WINDOW(self), 200, 200);

  GtkWidget *text_view = gtk_source_view_new();
  gtk_text_view_set_editable(GTK_TEXT_VIEW(text_view), false);
  gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(text_view), false);
  gtk_text_view_set_monospace(GTK_TEXT_VIEW(text_view), true);

  GtkWidget *toolbar_view = adw_toolbar_view_new();
  GtkWidget *header_bar = adw_header_bar_new();

  adw_toolbar_view_add_top_bar(ADW_TOOLBAR_VIEW(toolbar_view), header_bar);
  adw_toolbar_view_set_content(ADW_TOOLBAR_VIEW(toolbar_view), text_view);

  adw_application_window_set_content(ADW_APPLICATION_WINDOW(self),
                                     toolbar_view);

  {
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(text_view));

    GtkTextTag *tag = gtk_text_buffer_create_tag(
        buffer, "cursor-tag", "underline", PANGO_UNDERLINE_SINGLE, NULL);

    self->renderer = (struct renderer){.buffer = buffer, .tag = tag};
  }

  self->srcprg = create_srcprg();
  if (self->srcprg == NULL) {
    exit(EXIT_FAILURE);
  }

  const struct frame frame = execute(self->srcprg, do_nothing);

  render_frame(self->renderer, frame);

  g_action_map_add_action_entries(G_ACTION_MAP(self), app_entries,
                                  G_N_ELEMENTS(app_entries), self);
}

StedWindow *sted_window_new(GtkApplication *application) {
  return g_object_new(STED_WINDOW_TYPE, "application", application, NULL);
}

void sted_window_execute(StedWindow *self, enum instruction instr) {
  const struct frame frame = execute(self->srcprg, instr);
  render_frame(self->renderer, frame);
}
