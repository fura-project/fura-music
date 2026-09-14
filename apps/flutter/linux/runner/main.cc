#include <glib.h>

#include "my_application.h"

int main(int argc, char** argv) {
  // WebKitGTK's DMA-BUF import path can produce a permanently blank WebView on
  // supported Linux GPU/Wayland combinations. Prefer the measured shared-memory
  // renderer transport while preserving an explicit user override.
  if (g_getenv("WEBKIT_DMABUF_RENDERER_FORCE_SHM") == nullptr) {
    g_setenv("WEBKIT_DMABUF_RENDERER_FORCE_SHM", "1", FALSE);
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
