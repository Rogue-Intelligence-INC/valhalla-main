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
    // Windows 11 native Fluent style (Qt 6.8 FluentWinUI3): system accent,
    // native title-bar integration, light/dark follows Bridge::setDarkTheme.
    QQuickStyle::setStyle(QStringLiteral("FluentWinUI3"));

    Bridge bridge;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.loadFromModule("Valhalla", "Main");
    if (engine.rootObjects().isEmpty()) return 1;
    bridge.claimWindow();
    return app.exec();
}
