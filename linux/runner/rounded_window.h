#ifndef DEVMIL_ROUNDED_WINDOW_H_
#define DEVMIL_ROUNDED_WINDOW_H_

#include <gtk/gtk.h>
#include <initializer_list>

// Keep the accelerated child rectangular. A curved Cairo clip or libhandy's
// offscreen surface forces GTK3 to read the entire GL texture back to the CPU.
// The small native border instead carries the rounded corners and shadows.
inline bool rounded_window_is_floating(GtkWidget* window) {
  GtkStyleContext* style = gtk_widget_get_style_context(window);
  if (!gdk_screen_is_composited(gtk_widget_get_screen(window)) ||
      !gtk_style_context_has_class(style, "csd") ||
      gtk_style_context_has_class(style, "solid-csd")) return false;
  for (const char* state : {"maximized", "fullscreen", "tiled", "tiled-top",
                            "tiled-bottom", "tiled-left", "tiled-right"}) {
    if (gtk_style_context_has_class(style, state)) return false;
  }
  GdkWindow* native = gtk_widget_get_window(window);
  return !native || !(gdk_window_get_state(native) &
                     (GDK_WINDOW_STATE_MAXIMIZED | GDK_WINDOW_STATE_FULLSCREEN |
                      GDK_WINDOW_STATE_TILED));
}

inline void update_rounded_window_insets(GtkWidget* window, GtkWidget* content) {
  const bool floating = rounded_window_is_floating(window);
  // For an 8px circle, (2,3) lies inside the curve at every corner.
  gtk_widget_set_margin_start(content, floating ? 2 : 0);
  gtk_widget_set_margin_end(content, floating ? 2 : 0);
  gtk_widget_set_margin_top(content, floating ? 3 : 0);
  gtk_widget_set_margin_bottom(content, floating ? 3 : 0);
}

inline gboolean rounded_window_state_changed(GtkWidget* window,
                                             GdkEventWindowState*,
                                             GtkWidget* content) {
  update_rounded_window_insets(window, content);
  return FALSE;
}

inline GtkWindow* create_rounded_application_window(GtkApplication* application) {
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(application));
  // An explicitly hidden titlebar enables native CSD without a second toolbar.
  gtk_window_set_titlebar(window, gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0));
  GtkStyleContext* context = gtk_widget_get_style_context(GTK_WIDGET(window));
  gtk_style_context_add_class(context, "devmil-rounded-window");
  constexpr const char* floating =
      "window.devmil-rounded-window.csd:not(.solid-csd):not(.maximized)"
      ":not(.fullscreen):not(.tiled):not(.tiled-top):not(.tiled-bottom)"
      ":not(.tiled-left):not(.tiled-right)";
  g_autoptr(GString) css = g_string_new(
      "window.devmil-rounded-window.csd, "
      "window.devmil-rounded-window.csd > decoration "
      "{ border-radius: 0; }");
  g_string_append_printf(css, "%s, %s > decoration { border-radius: 8px; }",
                         floating, floating);
  g_autoptr(GtkCssProvider) provider = gtk_css_provider_new();
  gtk_css_provider_load_from_data(provider, css->str, -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      gtk_widget_get_screen(GTK_WIDGET(window)), GTK_STYLE_PROVIDER(provider),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  return window;
}

inline void add_rounded_window_content(GtkWindow* window, GtkWidget* content) {
  gtk_container_add(GTK_CONTAINER(window), content);
  g_signal_connect_object(window, "style-updated",
                          G_CALLBACK(update_rounded_window_insets), content,
                          G_CONNECT_DEFAULT);
  g_signal_connect_object(window, "window-state-event",
                          G_CALLBACK(rounded_window_state_changed), content,
                          G_CONNECT_DEFAULT);
  update_rounded_window_insets(GTK_WIDGET(window), content);
}

#endif  // DEVMIL_ROUNDED_WINDOW_H_
