#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

#if defined(NDEBUG) && defined(_WIN32)
#include <windows.h>
#endif
#include "Bridge.h"

int main(int argc, char* argv[]) {
    QGuiApplication app(argc, argv);
#if defined(NDEBUG) && defined(_WIN32)
    if (IsDebuggerPresent()) return 0;
#endif

    app.setApplicationName(QStringLiteral("VAL-DAL"));
    app.setOrganizationName("Rogue Intelligence");
    // Basic is the lightest Quick Controls style; the scene graph still
    // renders with Direct3D 11 on Windows 10/11 when a GPU is present.
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    Bridge bridge;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.loadFromModule("Valhalla", "Main");
    if (engine.rootObjects().isEmpty()) return 1;
    bridge.claimWindow();
    return app.exec();
}
