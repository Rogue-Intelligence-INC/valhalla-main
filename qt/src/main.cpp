#include <QDir>
#include <QFont>
#include <QFontDatabase>
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

    // Latin text in the bundled Inter; CJK glyphs fall through to YaHei UI. Variable CJK fonts
    // (Noto Sans SC VF) lose strokes at DemiBold under Qt's DirectWrite engine, so they are not used.
    const QDir fonts(QCoreApplication::applicationDirPath() + QStringLiteral("/fonts"));
    for (const QString& file : fonts.entryList({QStringLiteral("*.ttf"), QStringLiteral("*.otf")}, QDir::Files))
        QFontDatabase::addApplicationFont(fonts.filePath(file));
    QFont::insertSubstitutions(QStringLiteral("Inter"), {QStringLiteral("Microsoft YaHei UI"), QStringLiteral("Microsoft YaHei")});
    QFont ui(QStringList{QStringLiteral("Inter"), QStringLiteral("Microsoft YaHei UI")}, 10);
    ui.setHintingPreference(QFont::PreferNoHinting);
    ui.setStyleStrategy(QFont::PreferAntialias);
    QGuiApplication::setFont(ui);

    Bridge bridge;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("bridge", &bridge);
    engine.loadFromModule("Valhalla", "Main");
    if (engine.rootObjects().isEmpty()) return 1;
    bridge.claimWindow();
    return app.exec();
}
