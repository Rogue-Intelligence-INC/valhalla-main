#include <QApplication>
#include <QCheckBox>
#include <QHBoxLayout>
#include <QPainter>
#include <QPixmap>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLabel>
#include <QListWidget>
#include <QMessageBox>
#include <QProcess>
#include <QProgressBar>
#include <QPushButton>
#include <QSettings>
#include <QThread>
#include <QVBoxLayout>
#include <QWidget>

#include <windows.h>
#include <objbase.h>
#include <shlobj.h>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace {

const QString kModelName = "Qwen2.5-0.5B-Instruct";

// One installer binary serves all editions; the package drops a setup.json
// next to the installer exe to say which app this package installs.
struct SetupConfig {
    QString label = QStringLiteral("瓦序 VAL-DAL");
    QString target = QStringLiteral("C:/Ai/VAL-DAL");
    QString exe = QStringLiteral("Valhalla.exe");
    QString shortcut = QStringLiteral("瓦序 VAL-DAL");
    QString dataSub = QStringLiteral("main");
};

SetupConfig g_cfg;

void loadConfig() {
    QFile f(QCoreApplication::applicationDirPath() + "/setup.json");
    if (!f.open(QIODevice::ReadOnly)) return;
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    if (o.contains("label")) g_cfg.label = o.value("label").toString();
    if (o.contains("target")) g_cfg.target = o.value("target").toString();
    if (o.contains("exe")) g_cfg.exe = o.value("exe").toString();
    if (o.contains("shortcut")) g_cfg.shortcut = o.value("shortcut").toString();
    if (o.contains("dataSub")) g_cfg.dataSub = o.value("dataSub").toString();
}

qint64 dirSize(const QString& path) {
    qint64 total = 0;
    const QFileInfo info(path);
    if (info.isFile()) return info.size();
    if (!info.isDir()) return 0;
    for (const QFileInfo& child : QDir(path).entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot)) {
        total += child.isFile() ? child.size() : dirSize(child.absoluteFilePath());
    }
    return total;
}

bool copyRecursive(const QString& from, const QString& to, qint64& done, qint64 total,
                   const std::function<void(int)>& progress, const std::function<void(const QString&)>& log,
                   QString& error) {
    QDir dir(from);
    if (!dir.exists()) {
        error = "找不到安装文件：" + from;
        return false;
    }
    QDir().mkpath(to);
    for (const QFileInfo& child : dir.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot)) {
        const QString dest = to + "/" + child.fileName();
        if (child.isDir()) {
            if (!copyRecursive(child.absoluteFilePath(), dest, done, total, progress, log, error)) return false;
        } else {
            QFile::remove(dest);
            if (!QFile::copy(child.absoluteFilePath(), dest)) {
                error = "复制失败：" + child.absoluteFilePath();
                return false;
            }
            done += child.size();
            if (total > 0) progress(static_cast<int>(done * 100 / total));
        }
    }
    return true;
}

bool makeShortcut(const QString& linkPath, const QString& target, const QString& workDir) {
    ComPtr<IShellLinkW> link;
    if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) return false;
    link->SetPath(target.toStdWString().c_str());
    link->SetWorkingDirectory(workDir.toStdWString().c_str());
    link->SetDescription(g_cfg.shortcut.toStdWString().c_str());
    ComPtr<IPersistFile> file;
    if (FAILED(link.As(&file))) return false;
    return SUCCEEDED(file->Save(linkPath.toStdWString().c_str(), TRUE));
}

// Brand mark shared with the apps: a 3x3 tile grid rotated -18 degrees.
QPixmap brandMark(int size) {
    const qreal dpr = 2.0;
    QPixmap pm(int(size * dpr), int(size * dpr));
    pm.setDevicePixelRatio(dpr);
    pm.fill(Qt::transparent);
    QPainter p(&pm);
    p.setRenderHint(QPainter::Antialiasing);
    const qreal u = size / 6.2, gap = u * 0.75, grid = u * 3 + gap * 2;
    p.translate(size / 2.0, size / 2.0);
    p.rotate(-18);
    p.translate(-grid / 2, -grid / 2);
    const qreal alpha[9] = {1, 0.3, 1, 1, 0, 0.3, 1, 1, 1};
    for (int i = 0; i < 9; ++i) {
        if (alpha[i] == 0) continue;
        QColor c(0xd8, 0xdb, 0xd4);
        c.setAlphaF(alpha[i]);
        p.setPen(Qt::NoPen);
        p.setBrush(c);
        p.drawRoundedRect(QRectF((i % 3) * (u + gap), (i / 3) * (u + gap), u, u), u * 0.22, u * 0.22);
    }
    return pm;
}

}  // namespace

class Worker : public QThread {
    Q_OBJECT
public:
    explicit Worker(QString payload) : payload_(std::move(payload)) {}

signals:
    void progress(int value);
    void log(const QString& line);
    void finishedAll(bool ok, const QString& message);

protected:
    void run() override {
        QString error;
        const QString appFrom = payload_ + "/app";
        const QString modelFrom = payload_ + "/models/" + kModelName;
        const qint64 total = dirSize(appFrom) + dirSize(modelFrom);
        qint64 done = 0;
        auto prog = [this](int v) { emit progress(v); };
        auto lg = [this](const QString& s) { emit log(s); };

        const QString appTarget = g_cfg.target;
        const QString modelTarget = appTarget + "/models/" + kModelName;
        emit log("正在安装 " + g_cfg.label + " 到 " + appTarget + " …");
        if (!copyRecursive(appFrom, appTarget, done, total, prog, lg, error)) {
            emit finishedAll(false, error);
            return;
        }
        emit log("正在安装小模型（Qwen2.5-0.5B，约 1 GB）到 " + modelTarget + " …");
        if (!copyRecursive(modelFrom, modelTarget, done, total, prog, lg, error)) {
            emit finishedAll(false, error);
            return;
        }

        QDir().mkpath(appTarget + "/data/" + g_cfg.dataSub);
        const QString settingsPath = appTarget + "/data/" + g_cfg.dataSub + "/settings.json";
        if (!QFileInfo::exists(settingsPath)) {
            QFile settings(settingsPath);
            if (settings.open(QIODevice::WriteOnly | QIODevice::Text)) {
                settings.write("{\n  \"language\": \"system\",\n  \"model_repo\": \"Qwen/Qwen2.5-0.5B-Instruct\"\n}\n");
            }
        }

        QSettings env("HKEY_CURRENT_USER\\Environment", QSettings::NativeFormat);
        env.setValue("VALHALLA_BASE_EXE", QString(appTarget + "/valhalla_base.exe").replace('/', '\\'));
        env.sync();
        DWORD_PTR ignored = 0;
        SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                            reinterpret_cast<LPARAM>(L"Environment"), SMTO_ABORTIFHUNG, 3000, &ignored);

        const QString desktop = QDir::homePath() + "/Desktop";
        if (makeShortcut(desktop + "/" + g_cfg.shortcut + ".lnk", appTarget + "/" + g_cfg.exe, appTarget)) {
            emit log("已创建桌面快捷方式：" + g_cfg.shortcut);
        }
        emit progress(100);
        emit finishedAll(true, "安装完成。模型和 CUDA 运行库都已就位，可以直接打开 " + g_cfg.label + "。");
    }

private:
    QString payload_;
};

class Window : public QWidget {
    Q_OBJECT
public:
    Window() {
        setWindowTitle(g_cfg.label + " · A测版安装");
        resize(600, 500);
        setStyleSheet(
            "QWidget{background:#101112;color:#e6e7e5;}"
            "QLabel#title{font-size:22px;font-weight:600;color:#f1f1ed;}"
            "QLabel#eyebrow{font-size:11px;color:#808485;letter-spacing:1px;}"
            "QLabel#intro{color:#b7b9b7;line-height:150%;}"
            "QProgressBar{background:#171819;border:1px solid #303233;border-radius:5px;height:10px;text-align:center;color:#808485;font-size:10px;}"
            "QProgressBar::chunk{background:#d8dbd4;border-radius:4px;}"
            "QListWidget{background:#171819;border:1px solid #303233;border-radius:8px;padding:6px;color:#b7b9b7;}"
            "QCheckBox{color:#b7b9b7;spacing:8px;}"
            "QPushButton{background:#d8dbd4;color:#151716;border:none;border-radius:8px;padding:10px 18px;font-weight:600;}"
            "QPushButton:hover{background:#e6e8e2;}"
            "QPushButton:disabled{background:#262829;color:#808485;}");
        auto* layout = new QVBoxLayout(this);
        layout->setContentsMargins(28, 24, 28, 24);
        layout->setSpacing(12);
        auto* head = new QHBoxLayout();
        auto* mark = new QLabel();
        mark->setPixmap(brandMark(40));
        auto* titles = new QVBoxLayout();
        auto* eyebrow = new QLabel("ROGUE INTELLIGENCE · A测版");
        eyebrow->setObjectName("eyebrow");
        auto* title = new QLabel(g_cfg.label);
        title->setObjectName("title");
        titles->addWidget(eyebrow);
        titles->addWidget(title);
        head->addWidget(mark);
        head->addSpacing(12);
        head->addLayout(titles, 1);
        auto* intro = new QLabel(
            "一键安装：程序 + 本地小模型（Qwen2.5-0.5B）+ CUDA 运行库，装好即可离线使用，不需要联网和管理员权限。\n"
            "安装位置 " + QString(g_cfg.target).replace('/', '\\') + "：程序、小模型和各版本数据分开存放，重装不会覆盖你的数据。");
        intro->setObjectName("intro");
        intro->setWordWrap(true);
        bar_ = new QProgressBar();
        log_ = new QListWidget();
        install_ = new QPushButton("开始安装");
        install_->setCursor(Qt::PointingHandCursor);
        run_ = new QCheckBox("安装完成后打开 " + g_cfg.label);
        run_->setChecked(true);
        layout->addLayout(head);
        layout->addWidget(intro);
        layout->addWidget(bar_);
        layout->addWidget(log_, 1);
        auto* foot = new QHBoxLayout();
        foot->addWidget(run_, 1);
        foot->addWidget(install_);
        layout->addLayout(foot);
        connect(install_, &QPushButton::clicked, this, &Window::start);
    }

private:
    void start() {
        install_->setEnabled(false);
        const QString payload = QCoreApplication::applicationDirPath() + "/payload";
        worker_ = new Worker(payload);
        connect(worker_, &Worker::progress, bar_, &QProgressBar::setValue);
        connect(worker_, &Worker::log, this, [this](const QString& s) { log_->addItem(s); });
        connect(worker_, &Worker::finishedAll, this, [this](bool ok, const QString& message) {
            log_->addItem(message);
            if (ok) {
                install_->setText("安装完成");
                if (run_->isChecked()) {
                    qputenv("VALHALLA_BASE_EXE", QString(g_cfg.target + "/valhalla_base.exe").replace('/', '\\').toUtf8());
                    QProcess::startDetached(g_cfg.target + "/" + g_cfg.exe, {}, g_cfg.target);
                }
            } else {
                install_->setText("安装失败，点重试");
                install_->setEnabled(true);
                QMessageBox::warning(this, "安装失败", message);
            }
        });
        worker_->start();
    }

    QProgressBar* bar_ = nullptr;
    QListWidget* log_ = nullptr;
    QPushButton* install_ = nullptr;
    QCheckBox* run_ = nullptr;
    Worker* worker_ = nullptr;
};

#include "main.moc"

int main(int argc, char* argv[]) {
    QApplication app(argc, argv);
    app.setApplicationName("VAL-DAL Setup");
    app.setOrganizationName("Rogue Intelligence");
    loadConfig();
    QFont font("Microsoft YaHei UI", 10);
    app.setFont(font);
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    Window window;
    window.show();
    return app.exec();
}
