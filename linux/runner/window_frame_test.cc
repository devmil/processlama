// Run in a Linux GUI session. See linux/runner/WINDOW_FRAME_TEST.md.
#include <epoxy/gl.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <cstdio>
#include <initializer_list>
#include <utility>

#include "rounded_window.h"

static int renders = 0;
static gboolean render(GtkGLArea*, GdkGLContext*, gpointer) {
  glClearColor(0, 0, 1, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  ++renders;
  return TRUE;
}

static void settle() {
  const auto deadline = g_get_monotonic_time() + 300000;
  while (g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {
    }
    g_usleep(1000);
  }
}

static bool blue(uint32_t pixel) {
  return (pixel & 0xFF) > 200 && (pixel & 0xFF) > ((pixel >> 16) & 0xFF) + 100;
}

static void check_pixels(GtkWidget* window, GtkWidget* content, bool rounded) {
  gint x, y;
  g_assert(gtk_widget_translate_coordinates(content, window, 0, 0, &x, &y));
  const int width = gtk_widget_get_allocated_width(window);
  const int height = gtk_widget_get_allocated_height(window);
  const int cw = gtk_widget_get_allocated_width(content);
  const int ch = gtk_widget_get_allocated_height(content);
  const int scale = gtk_widget_get_scale_factor(window);
  auto* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width * scale,
                                             height * scale);
  cairo_surface_set_device_scale(surface, scale, scale);
  auto* cr = cairo_create(surface);
  gtk_widget_draw(window, cr);
  cairo_surface_flush(surface);
  const auto* pixels =
      reinterpret_cast<const uint32_t*>(cairo_image_surface_get_data(surface));
  auto pixel = [&](int px, int py) {
    return pixels[py * scale * width * scale + px * scale];
  };
  g_assert(blue(pixel(x + cw / 2, y + ch / 2)));
  for (const auto& point : {std::pair<int, int>{x, y},
                            {x + cw - 1, y},
                            {x, y + ch - 1},
                            {x + cw - 1, y + ch - 1}}) {
    // GL stays rectangular; the native border carries the outer curve.
    g_assert(blue(pixel(point.first, point.second)));
  }
  g_assert_cmpint(gtk_widget_get_margin_start(content), ==, rounded ? 2 : 0);
  g_assert_cmpint(gtk_widget_get_margin_end(content), ==, rounded ? 2 : 0);
  g_assert_cmpint(gtk_widget_get_margin_top(content), ==, rounded ? 3 : 0);
  g_assert_cmpint(gtk_widget_get_margin_bottom(content), ==, rounded ? 3 : 0);
  if (rounded) {
    for (const auto& point : {std::pair<int, int>{x - 2, y - 3},
                              {x + cw + 1, y - 3},
                              {x - 2, y + ch + 2},
                              {x + cw + 1, y + ch + 2}}) {
      const uint32_t corner = pixel(point.first, point.second);
      g_assert(!blue(corner));
      g_assert_cmpint(corner >> 24, <, 200);
    }
  }
  const char* output = g_getenv("FRAME_CAPTURE");
  if (output) cairo_surface_write_to_png(surface, output);
  cairo_destroy(cr);
  cairo_surface_destroy(surface);
}

int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  const char* theme = g_getenv("GTK_THEME");
  if (theme)
    g_object_set(gtk_settings_get_default(), "gtk-theme-name", theme, nullptr);
  auto* app =
      gtk_application_new("devmil.corner.test", G_APPLICATION_NON_UNIQUE);
  g_assert(g_application_register(G_APPLICATION(app), nullptr, nullptr));
  auto* window = create_rounded_application_window(app);
  auto* content = gtk_gl_area_new();
  gtk_gl_area_set_required_version(GTK_GL_AREA(content), 3, 2);
  g_signal_connect(content, "render", G_CALLBACK(render), nullptr);
  add_rounded_window_content(window, content);
  gtk_window_set_default_size(window, 320, 180);
  gtk_widget_show(content);
  gtk_widget_show(GTK_WIDGET(window));
  settle();
  g_assert_no_error(gtk_gl_area_get_error(GTK_GL_AREA(content)));
  g_assert_cmpint(renders, >, 0);
  g_assert(gtk_window_get_decorated(window));
  g_assert(gtk_window_get_resizable(window));
  g_assert(!gtk_widget_get_visible(gtk_window_get_titlebar(window)));
  GtkStyleContext* context = gtk_widget_get_style_context(GTK_WIDGET(window));
  int radius = 0;
  gtk_style_context_get(context, gtk_style_context_get_state(context),
                        "border-radius", &radius, nullptr);
  const bool composited =
      gdk_screen_is_composited(gtk_widget_get_screen(GTK_WIDGET(window)));
  const bool rounded = composited &&
                       !gtk_style_context_has_class(context, "solid-csd") &&
                       radius > 0;
  check_pixels(GTK_WIDGET(window), content, rounded);
  gtk_window_resize(window, 460, 260);
  settle();
  check_pixels(GTK_WIDGET(window), content, rounded);
  // Native compositor transitions are checked when it acknowledges maximize.
  gtk_window_maximize(window);
  settle();
  const bool maximized = gtk_window_is_maximized(window);
  if (maximized) check_pixels(GTK_WIDGET(window), content, false);
  gtk_window_unmaximize(window);
  settle();
  check_pixels(GTK_WIDGET(window), content, rounded);
  for (const char* state :
       {"tiled", "tiled-top", "tiled-bottom", "tiled-left", "tiled-right"}) {
    gtk_style_context_add_class(context, state);
    settle();
    check_pixels(GTK_WIDGET(window), content, false);
    gtk_style_context_remove_class(context, state);
    settle();
    check_pixels(GTK_WIDGET(window), content, rounded);
  }
  gtk_style_context_add_class(context, "solid-csd");
  settle();
  check_pixels(GTK_WIDGET(window), content, false);
  gtk_style_context_remove_class(context, "solid-csd");
  settle();
  check_pixels(GTK_WIDGET(window), content, rounded);
  gtk_window_fullscreen(window);
  settle();
  if (gdk_window_get_state(gtk_widget_get_window(GTK_WIDGET(window))) &
      GDK_WINDOW_STATE_FULLSCREEN) {
    check_pixels(GTK_WIDGET(window), content, false);
  }
  gtk_window_unfullscreen(window);
  settle();
  check_pixels(GTK_WIDGET(window), content, rounded);
  gtk_widget_destroy(GTK_WIDGET(window));
  settle();
  std::printf(
      "PASS rectangular GL/rounded native corners, resize, tiled, solid, fullscreen, restore; rounded=%d "
      "native-maximize=%d radius=%d\n",
      rounded, maximized, radius);
  g_object_unref(app);
}
