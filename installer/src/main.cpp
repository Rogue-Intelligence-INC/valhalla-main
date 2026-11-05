#include <QApplication>
#include <QCheckBox>
#include <QDir>
#include <QFile>
#include <QFileInfo>
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

const QString kAppTarget = "C:/Ai/VAL-DAL";
const QString kModelTarget = "C:/Ai/models/Qwen2.5-0.5B-Instruct";
const QString kModelName = "Qwen2.5-0.5B-Instruct";

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
    link->SetDescription(L"瓦序 VAL-DAL");
    ComPtr<IPersistFile> file;
    if (FAILED(link.As(&file))) return false;
    return SUCCEEDED(file->Save(linkPath.toStdWString().c_str(), TRUE));
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

        emit log("正在安装瓦序 VAL-DAL 到 " + kAppTarget + " …");
        if (!copyRecursive(appFrom, kAppTarget, done, total, prog, lg, error)) {
            emit finishedAll(false, error);
            return;
        }
        emit log("正在安装小模型（Qwen2.5-0.5B，约 1 GB）到 " + kModelTarget + " …");
        if (!copyRecursive(modelFrom, kModelTarget, done, total, prog, lg, error)) {
            emit finishedAll(false, error);
            return;
        }

        const QString settingsPath = kAppTarget + "/settings.json";
        if (!QFileInfo::exists(settingsPath)) {
            QFile settings(settingsPath);
            if (settings.open(QIODevice::WriteOnly | QIODevice::Text)) {
                settings.write("{\n  \"language\": \"system\",\n  \"model_repo\": \"Qwen/Qwen2.5-0.5B-Instruct\"\n}\n");
            }
        }

        QSettings env("HKEY_CURRENT_USER\\Environment", QSettings::NativeFormat);
        env.setValue("VALHALLA_BASE_EXE", QString(kAppTarget + "/valhalla_base.exe").replace('/', '\\'));
        env.sync();
        DWORD_PTR ignored = 0;
        SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                            reinterpret_cast<LPARAM>(L"Environment"), SMTO_ABORTIFHUNG, 3000, &ignored);

        const QString desktop = QDir::homePath() + "/Desktop";
        if (makeShortcut(desktop + "/瓦序 VAL-DAL.lnk", kAppTarget + "/Valhalla.exe", kAppTarget)) {
            emit log("已创建桌面快捷方式：瓦序 VAL-DAL");
        }
        emit progress(100);
        emit finishedAll(true, "安装完成。模型和 CUDA 运行库都已就位，可以直接打开瓦序。");
    }

private:
    QString payload_;
};

class Window : public QWidget {
    Q_OBJECT
public:
    Window() {
        setWindowTitle("瓦序 VAL-DAL · A测版安装");
        resize(560, 460);
        auto* layout = new QVBoxLayout(this);
        auto* title = new QLabel("瓦序 VAL-DAL（A测版）");
        title->setStyleSheet("font-size:20px;font-weight:bold;");
        auto* intro = new QLabel(
            "Rogue Intelligence Inc.（Delaware, USA）\n"
            "一键安装：主程序 + 本地小模型（Qwen2.5-0.5B）+ CUDA 运行库，装好即可离线使用。\n"
            "安装位置：C:\\Ai\\VAL-DAL，模型装到 C:\\Ai\\models。");
        intro->setWordWrap(true);
        bar_ = new QProgressBar();
        log_ = new QListWidget();
        install_ = new QPushButton("开始安装");
        run_ = new QCheckBox("安装完成后打开瓦序");
        run_->setChecked(true);
        layout->addWidget(title);
        layout->addWidget(intro);
        layout->addWidget(bar_);
        layout->addWidget(log_, 1);
        layout->addWidget(run_);
        layout->addWidget(install_);
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
                    qputenv("VALHALLA_BASE_EXE", QString(kAppTarget + "/valhalla_base.exe").replace('/', '\\').toUtf8());
                    QProcess::startDetached(kAppTarget + "/Valhalla.exe", {}, kAppTarget);
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
    QFont font("SimHei");
    app.setFont(font);
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    Window window;
    window.show();
    return app.exec();
}
