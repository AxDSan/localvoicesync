#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <gdk/gdk.h>
#include <string.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

// Include the desktop_multi_window header to access the callback registration
#include <desktop_multi_window/desktop_multi_window_plugin.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// ============================================================================
// GHOST WINDOW STRATEGY FOR KDE/WAYLAND
// ============================================================================
// The desktop_multi_window package creates windows IN THE SAME PROCESS,
// not as separate processes. It also adds a header bar by default.
// 
// Our strategy:
// 1. Register a window-created callback with desktop_multi_window
// 2. When a secondary window is created, remove its header bar
// 3. Apply ghost window settings: no decorations, click-through, always on top
// ============================================================================

static void find_and_set_view_transparent(GtkWidget* widget) {
  if (FL_IS_VIEW(widget)) {
    GdkRGBA transparent = {0.0, 0.0, 0.0, 0.0};
    fl_view_set_background_color(FL_VIEW(widget), &transparent);
    return;
  }
  if (GTK_IS_CONTAINER(widget)) {
    GList* children = gtk_container_get_children(GTK_CONTAINER(widget));
    for (GList* l = children; l != nullptr; l = l->next) {
      find_and_set_view_transparent(GTK_WIDGET(l->data));
    }
    g_list_free(children);
  }
}

// Called after the window is mapped (visible on screen)
static gboolean on_overlay_map_event(GtkWidget* widget, GdkEvent* event, gpointer data) {
  g_printerr("DEBUG: [on_overlay_map_event] Ghost window enforcement for %p\n", widget);
  
  GdkWindow* gdk_window = gtk_widget_get_window(widget);
  if (gdk_window == nullptr) {
    g_printerr("DEBUG: [on_overlay_map_event] No GdkWindow yet\n");
    return FALSE;
  }

  // === Strip decorations and functions at GDK level ===
  gdk_window_set_decorations(gdk_window, (GdkWMDecoration)0);
  gdk_window_set_functions(gdk_window, (GdkWMFunction)0);
  gdk_window_set_keep_above(gdk_window, TRUE);
  
  // === Click-through: empty input region ===
  cairo_region_t* empty_region = cairo_region_create();
  gtk_widget_input_shape_combine_region(widget, empty_region);
  cairo_region_destroy(empty_region);
  
  cairo_region_t* gdk_empty = cairo_region_create();
  gdk_window_input_shape_combine_region(gdk_window, gdk_empty, 0, 0);
  cairo_region_destroy(gdk_empty);
  
  // === X11-specific: override redirect ===
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_WINDOW(gdk_window)) {
    g_printerr("DEBUG: [on_overlay_map_event] X11 detected, using override-redirect\n");
    gdk_window_set_override_redirect(gdk_window, TRUE);
  }
#endif

  // === Position window at bottom-center of screen ===
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == nullptr) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor != nullptr) {
    GdkRectangle geometry;
    gdk_monitor_get_geometry(monitor, &geometry);
    
    int window_width = 460;
    int window_height = 80;
    int x = geometry.x + (geometry.width - window_width) / 2;
    int y = geometry.y + geometry.height - window_height - 120;
    
    gtk_window_move(GTK_WINDOW(widget), x, y);
    gtk_window_resize(GTK_WINDOW(widget), window_width, window_height);
    
    g_printerr("DEBUG: [on_overlay_map_event] Positioned at (%d, %d)\n", x, y);
  }
  
  return FALSE;
}

// Called when GTK widget is realized
static void on_overlay_realize(GtkWidget* widget, gpointer data) {
  g_printerr("DEBUG: [on_overlay_realize] Setting up ghost window %p\n", widget);
  
  GdkWindow* gdk_window = gtk_widget_get_window(widget);
  if (gdk_window != nullptr) {
    // Set type hint at GDK level
    gdk_window_set_type_hint(gdk_window, GDK_WINDOW_TYPE_HINT_DOCK);
    gdk_window_set_decorations(gdk_window, (GdkWMDecoration)0);
    gdk_window_set_functions(gdk_window, (GdkWMFunction)0);
    gdk_window_set_keep_above(gdk_window, TRUE);
  }
}

static void configure_overlay_window(GtkWindow* window) {
  g_printerr("DEBUG: [configure_overlay_window] Configuring window %p\n", (void*)window);
  
  // === STEP 1: Remove any existing titlebar/header bar ===
  GtkWidget* current_titlebar = gtk_window_get_titlebar(window);
  if (current_titlebar != nullptr) {
    g_printerr("DEBUG: [configure_overlay_window] Removing existing titlebar\n");
    // Setting titlebar to NULL doesn't work well, use empty widget instead
    GtkWidget* empty = gtk_fixed_new();
    gtk_widget_set_size_request(empty, 0, 0);
    gtk_widget_show(empty);
    gtk_window_set_titlebar(window, empty);
  }
  
  // === STEP 2: Window Type Hint ===
  // DOCK type is usually frameless on KDE
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_DOCK);
  
  // === STEP 3: Disable decorations ===
  gtk_window_set_decorated(window, FALSE);
  
  // === STEP 4: Interaction stripping ===
  gtk_window_set_accept_focus(window, FALSE);
  gtk_window_set_focus_on_map(window, FALSE);
  gtk_window_set_deletable(window, FALSE);
  gtk_window_set_resizable(window, FALSE);
  
  // === STEP 5: Shell integration ===
  gtk_window_set_keep_above(window, TRUE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  
  // === STEP 6: Fixed size ===
  gtk_widget_set_size_request(GTK_WIDGET(window), 460, 80);
  gtk_window_set_default_size(window, 460, 80);
  
  // === STEP 7: RGBA visual for transparency ===
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
    g_printerr("DEBUG: [configure_overlay_window] RGBA visual set\n");
  }
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
  
  // === STEP 8: Connect to lifecycle events ===
  g_signal_connect(window, "realize", G_CALLBACK(on_overlay_realize), nullptr);
  g_signal_connect(window, "map-event", G_CALLBACK(on_overlay_map_event), nullptr);
  
  // If already realized, trigger immediately
  if (gtk_widget_get_realized(GTK_WIDGET(window))) {
    on_overlay_realize(GTK_WIDGET(window), nullptr);
  }
  
  // Transparent FlView background
  g_signal_connect(window, "show", G_CALLBACK(+[](GtkWidget* widget, gpointer) {
    find_and_set_view_transparent(widget);
  }), nullptr);
  
  g_printerr("DEBUG: [configure_overlay_window] Configuration complete\n");
}

// Callback from desktop_multi_window when a secondary window is created
static void on_multi_window_created(FlPluginRegistry* registry) {
  g_printerr("DEBUG: [on_multi_window_created] Secondary window created\n");
  
  // The registry is actually an FlView cast to FlPluginRegistry
  if (!FL_IS_VIEW(registry)) {
    g_printerr("DEBUG: [on_multi_window_created] Registry is not an FlView\n");
    return;
  }
  
  FlView* view = FL_VIEW(registry);
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  
  if (!GTK_IS_WINDOW(toplevel)) {
    g_printerr("DEBUG: [on_multi_window_created] Toplevel is not a GtkWindow\n");
    return;
  }
  
  GtkWindow* window = GTK_WINDOW(toplevel);
  g_printerr("DEBUG: [on_multi_window_created] Got window %p, configuring as overlay\n", (void*)window);
  
  // Set transparent background on the FlView
  GdkRGBA transparent = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(view, &transparent);
  
  // Configure the window as a ghost overlay
  configure_overlay_window(window);
}

static void on_main_window_added(GtkApplication* app, GtkWindow* window, gpointer user_data) {
  g_printerr("DEBUG: [on_main_window_added] Main window added\n");
  
  // Enable RGBA visual for transparency on main window too
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(GTK_WIDGET(window), visual);
  }
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
}

static void first_frame_cb(MyApplication* self, FlView* view) {
  GtkWindow* window = GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  gtk_widget_show(GTK_WIDGET(window));
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  
  g_printerr("DEBUG: [activate] Starting main application activation\n");
  
  // Register callback for secondary windows created by desktop_multi_window
  desktop_multi_window_plugin_set_window_created_callback(on_multi_window_created);
  g_printerr("DEBUG: [activate] Registered multi-window callback\n");
  
  g_signal_connect(application, "window-added", G_CALLBACK(on_main_window_added), nullptr);

  // Create main application window
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  gtk_window_set_title(window, "LocalVoiceSync");
  gtk_window_set_default_size(window, 1280, 720);
  
  on_main_window_added(GTK_APPLICATION(application), window, nullptr);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color = {0.0, 0.0, 0.0, 0.0};
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  
  g_printerr("DEBUG: [local_command_line] Parsing arguments\n");
  
  // Skip the program name (arguments[0]) when storing Dart args
  if (*arguments != nullptr && (*arguments)[0] != nullptr) {
    self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  } else {
    self->dart_entrypoint_arguments = nullptr;
  }
  
  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }
  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(), 
                                      "application-id", APPLICATION_ID, 
                                      "flags", G_APPLICATION_NON_UNIQUE, 
                                      nullptr));
}
