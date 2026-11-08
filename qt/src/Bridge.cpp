#include <algorithm>
#include <QVector>
#include "Bridge.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkAccessManager>
#include <QJsonObject>
#include <QJsonDocument>
#include <QJsonArray>
#include <QFileInfo>
#include <QGuiApplication>
#include <QStyleHints>
#include <QClipboard>
#ifdef Q_OS_WIN
#include <dwmapi.h>
#endif
#include <QImage>
#include <QRegularExpression>
#include "ocr.h"
#include <QUrl>
#include <QWindow>

#include <chrono>
#include <thread>

#include "utf.h"

namespace {

struct ModelSpec {
    const char* repo;
    const char* label;
    const char* size;
    const char* noteZh;
    const char* noteEn;
};

constexpr ModelSpec kModels[] = {
    {"Qwen/Qwen2.5-0.5B-Instruct", "Qwen2.5 0.5B", "1 GB", "默认小模型。选择题混合解码约 63%。", "Default small model. Hybrid MCQ is about 63%."},
    {"Qwen/Qwen2.5-1.5B-Instruct", "Qwen2.5 1.5B", "3 GB", "免费 Qwen2 权重，可以直接加载。", "Free Qwen2 weights this decoder can load."},
    {"Qwen/Qwen2.5-3B-Instruct", "Qwen2.5 3B", "6 GB", "对照实验用的 3B。选择题 45/46。", "The 3B used in the paired comparisons. MCQ 45/46."},
    {"Qwen/Qwen2.5-7B-Instruct", "Qwen2.5 7B", "15 GB", "免费 7B。选择题 44/46，没有再高于 3B。", "Free 7B. MCQ 44/46, no further gain over 3B."},
};

const char* kStrategyIds[] = {"open", "mcq", "followup", "multihop"};

int strategyIndexOf(const std::string& id) {
    if (id == "mcq") return 1;
    if (id == "followup") return 2;
    if (id == "multihop") return 3;
    return 0;
}

QString badgeFor(const QString& path, bool zh) {
    if (path.isEmpty()) return {};
    if (path == QStringLiteral("web")) return zh ? QStringLiteral("联网来源") : QStringLiteral("Web sources");
    if (!path.contains('/') && !path.contains("valhalla", Qt::CaseInsensitive)) return path;
    const QString folded = path.toLower();
    if (folded.contains("mcq") || folded.contains("logprob")) return zh ? QStringLiteral("选择题混合") : QStringLiteral("Hybrid choice");
    if (folded.contains("multihop")) return zh ? QStringLiteral("多跳后作答") : QStringLiteral("Multi-hop, then written");
    if (folded.contains("phrase") || folded.contains("native") || folded.contains("retrieval"))
        return zh ? QStringLiteral("检索后作答") : QStringLiteral("Retrieved, then written");
    return zh ? QStringLiteral("续写") : QStringLiteral("Continued");
}

std::wstring resolveDataDir() {
    const QString dir = QCoreApplication::applicationDirPath() + QStringLiteral("/data/main");
    QDir().mkpath(dir);
    if (!QFileInfo::exists(dir + "/settings.json") && !QFileInfo::exists(dir + "/knowledge.json")) {
        const QString app = QCoreApplication::applicationDirPath();
        const QStringList old = {app, QDir::cleanPath(app + "/.."), QDir::cleanPath(app + "/../..")};
        for (const QString& from : old) {
            if (from == dir) continue;
            if (!QFileInfo::exists(from + "/settings.json") && !QFileInfo::exists(from + "/knowledge.json")) continue;
            for (const char* name : {"settings.json", "knowledge.json"}) {
                if (QFileInfo::exists(from + "/" + name)) QFile::copy(from + "/" + name, dir + "/" + name);
            }
            break;
        }
    }
    return QDir::toNativeSeparators(dir).toStdWString();
}

}  // namespace

namespace {
const char* kCudaDlls[] = {"cublas64_12.dll", "cublasLt64_12.dll", "cudart64_12.dll",
                           "curand64_10.dll", "nvrtc-builtins64_128.dll", "nvrtc64_120_0.dll"};

QStringList missingCudaDlls(const QString& dir) {
    QStringList missing;
    if (dir.isEmpty()) return missing;
    for (const char* name : kCudaDlls) {
        if (!QFileInfo::exists(dir + "/" + name)) missing.push_back(name);
    }
    return missing;
}

QString findCudaDllSource() {
    const QString app = QCoreApplication::applicationDirPath();
    const QStringList candidates = {app + "/cuda12-dll", QDir::cleanPath(app + "/../cuda12-dll"),
                                    QDir::cleanPath(app + "/../../cuda12-dll"), QStringLiteral("C:/Ai/cuda12-dll")};
    for (const QString& dir : candidates) {
        if (QFileInfo::exists(dir + "/cudart64_12.dll")) return dir;
    }
    return {};
}

QString findCudaInstaller() {
    const QString app = QCoreApplication::applicationDirPath();
    const QStringList candidates = {app + "/tools/cuda_12.8_network.exe",
                                    QDir::cleanPath(app + "/../tools/cuda_12.8_network.exe"),
                                    QStringLiteral("C:/Ai/Tools/android-build/cuda_12.8_network.exe")};
    for (const QString& file : candidates) {
        if (QFileInfo::exists(file)) return file;
    }
    return {};
}
}  // namespace


namespace {
// Built-in model catalog (JSON). Remote update replaces it via data/models_catalog_cache.json.
// TODO: formal catalog URL to be decided by Rogue Intelligence (placeholder below).
const char* kCatalogUrl = "https://example.com/valdal/models_catalog.json"; // placeholder, formal address TBD
const char* kBuiltinCatalog = R"JSON([{"repo":"Qwen/Qwen2.5-0.5B-Instruct","label":"Qwen2.5 0.5B","family":"Qwen","paramsB":0.5,"size":"约 1 GB"},{"repo":"Qwen/Qwen2.5-1.5B-Instruct","label":"Qwen2.5 1.5B","family":"Qwen","paramsB":1.5,"size":"约 3 GB"},{"repo":"Qwen/Qwen2.5-3B-Instruct","label":"Qwen2.5 3B","family":"Qwen","paramsB":3,"size":"约 6 GB"},{"repo":"Qwen/Qwen2.5-7B-Instruct","label":"Qwen2.5 7B","family":"Qwen","paramsB":7,"size":"约 15 GB"},{"repo":"mistralai/Mistral-7B-Instruct-v0.3","label":"Mistral 7B Instruct","family":"Mistral","paramsB":7,"size":"约 14 GB"},{"repo":"mistralai/Mistral-Nemo-Instruct-2407","label":"Mistral Nemo 12B","family":"Mistral","paramsB":12,"size":"约 24 GB"},{"repo":"mistralai/Mistral-Small-24B-Instruct-2501","label":"Mistral Small 24B","family":"Mistral","paramsB":24,"size":"约 48 GB"},{"repo":"meta-llama/Llama-3.2-1B-Instruct","label":"Llama 3.2 1B","family":"Llama","paramsB":1,"size":"约 2.5 GB"},{"repo":"meta-llama/Llama-3.2-3B-Instruct","label":"Llama 3.2 3B","family":"Llama","paramsB":3,"size":"约 6 GB"},{"repo":"meta-llama/Llama-3.1-8B-Instruct","label":"Llama 3.1 8B","family":"Llama","paramsB":8,"size":"约 16 GB"},{"repo":"microsoft/Phi-3-mini-4k-instruct","label":"Phi-3 mini","family":"Phi","paramsB":3.8,"size":"约 8 GB"},{"repo":"google/gemma-2-2b-it","label":"Gemma 2 2B","family":"Gemma","paramsB":2,"size":"约 5 GB"},{"repo":"google/gemma-2-9b-it","label":"Gemma 2 9B","family":"Gemma","paramsB":9,"size":"约 18 GB"}])JSON";
bool parseCatalog(const QByteArray& raw, QJsonArray& out) {
    QJsonParseError err; QJsonDocument doc = QJsonDocument::fromJson(raw, &err);
    if (err.error != QJsonParseError::NoError) return false;
    if (doc.isArray()) out = doc.array();
    else if (doc.isObject()) out = doc.object().value("models").toArray();
    return !out.isEmpty();
}
} // namespace

Bridge::Bridge(QObject* parent) : QObject(parent) {
    data_dir_ = resolveDataDir();
    settings_path_ = dataFile(L"settings.json");
    kb_path_ = dataFile(L"knowledge.json");
    settings_ = load_settings(settings_path_);
    lang_ = settings_.language == "zh" || settings_.language == "en"
                ? QString::fromStdString(settings_.language)
                : ((GetUserDefaultUILanguage() & 0x3FF) == 0x04 ? "zh" : "en");
    load_knowledge(kb_path_, kb_);
    sync_notes(kb_, settings_.knowledge);
    save_knowledge(kb_path_, kb_);
    library_.root = dataFile(L"conversations");
    if (!load_library(library_)) import_legacy(library_, dataFile(L"conversation.json"));
    transcript_path_ = conversation_file(library_, library_.active);
    loadActive();
    framework_note_ = L("正在启动 Valhalla，模型只载入这一次…", "Starting Valhalla. The model loads once…");
    refreshConversations();
    refreshModels();
    emit settingsChanged();

    const std::wstring model = model_directory(settings_.model_repo);
    if (weights_present(model)) {
        std::thread([this, model]() {
            const std::wstring error = ensure_framework(model);
            QMetaObject::invokeMethod(this, [this, error]() {
                framework_note_ = error.empty()
                                      ? L("模型已常驻，后续对话不再重新加载。", "The model is resident. Later turns will not load it again.")
                                      : QString::fromStdWString(error);
                if (!busy_) setStatus(framework_note_);
                emit runtimeChanged();
            }, Qt::QueuedConnection);
        }).detach();
    }
}

Bridge::~Bridge() { storeTranscript(); }

std::wstring Bridge::dataFile(const wchar_t* name) const {
    return data_dir_ + L"\\" + name;
}

void Bridge::claimWindow() {
    const auto windows = QGuiApplication::topLevelWindows();
    if (!windows.isEmpty()) {
        window_ = reinterpret_cast<void*>(windows.first()->winId());
        set_desktop_owner(window_);
    }
}

int Bridge::strategyIndex() const { return strategyIndexOf(settings_.strategy); }

QString Bridge::strategyDelta() const {
    static const char* zh[] = {"RAGTruth 34/40，对照 0/40", "0.5B 约 +48 个百分点", "30 轮追问 96.7%", "MultiHop 9/15，对照 8/15"};
    static const char* en[] = {"RAGTruth 34/40 versus 0/40", "About +48 pp at 0.5B", "96.7% on 30-turn follow-up", "MultiHop 9/15 versus 8/15"};
    const int index = strategyIndex();
    return lang_ == "zh" ? QString::fromUtf8(zh[index]) : QString::fromUtf8(en[index]);
}

int Bridge::languageIndex() const {
    if (settings_.language == "zh") return 1;
    if (settings_.language == "en") return 2;
    return 0;
}

QString Bridge::knowledgeStats() const {
    int notes = 0;
    std::string current;
    auto flush = [&]() {
        if (!trim_utf8(current).empty()) ++notes;
        current.clear();
    };
    for (char ch : settings_.knowledge) {
        if (ch == '\n') flush();
        else current += ch;
    }
    flush();
    return L("手写 %1 条 · 已导入 %2 个行业、%3 条", "%1 notes · %2 industries, %3 imported")
        .arg(notes)
        .arg(industry_domains(kb_))
        .arg(industry_records(kb_));
}

QString Bridge::runtimeText() const {
    QString text = QString::fromStdWString(gpu_status());
    const QString binary = QString::fromStdWString(find_binary());
    if (!probe_text_.isEmpty()) text = probe_text_;
    if (!text.isEmpty()) text += "\n";
    text += binary.isEmpty() ? L("找不到 valhalla_base.exe", "valhalla_base.exe was not found")
                             : L("运行时  ", "Runtime  ") + binary;
    if (!framework_note_.isEmpty()) text += "\n" + framework_note_;
    return text;
}

QString Bridge::screenMeta() const {
    if (reading_.window.empty() && reading_.ocr_lines == 0) return L("未识别", "Not read");
    return QString("%1 · OCR %2 · %3")
        .arg(QString::fromStdWString(reading_.window))
        .arg(L("%1 行", "%1 lines").arg(reading_.ocr_lines))
        .arg(L("%1 个控件", "%1 controls").arg(reading_.controls));
}

QString Bridge::chatTitle() const {
    for (const auto& item : library_.items) {
        if (item.id == library_.active && !item.title.empty()) return QString::fromStdString(item.title);
    }
    return L("新对话", "New chat");
}

QString Bridge::lastBadge() const { return badgeFor(last_path_, lang_ == "zh"); }

QString Bridge::lastElapsed() const {
    return last_seconds_ < 0 ? QString() : QString::number(last_seconds_, 'f', 1) + " s";
}

void Bridge::setBusy(bool value) {
    if (busy_ == value) return;
    busy_ = value;
    emit busyChanged();
}

void Bridge::setStatus(const QString& text) {
    status_ = text;
    emit statusChanged();
}

void Bridge::saveSettings() { save_settings(settings_path_, settings_); }

void Bridge::refreshConversations() {
    conversations_.clear();
    const QString needle = search_.trimmed().toLower();
    for (const auto& item : library_.items) {
        const QString title = item.title.empty() ? L("新对话", "New chat") : QString::fromStdString(item.title);
        if (!needle.isEmpty() && !title.toLower().contains(needle)) continue;
        QVariantMap row;
        row["id"] = QString::fromStdString(item.id);
        row["title"] = title;
        row["project"] = vallocal::projectFor(valDir(), QString::fromStdString(item.id), currentProject());
        row["active"] = item.id == library_.active;
        conversations_.push_back(row);
    }
    emit conversationsChanged();
}

void Bridge::refreshMessages() {
    messages_.clear();
    for (const auto& line : lines_) {
        QVariantMap row;
        row["user"] = line.user;
        row["text"] = line.text;
        row["path"] = line.path;
        row["badge"] = badgeFor(line.path, lang_ == "zh");
        row["error"] = line.error;
        messages_.push_back(row);
    }
    emit messagesChanged();
}


void Bridge::refreshModels() {
    QJsonArray arr;
    bool fromCache = false;
    const QString cachePath = QString::fromStdWString(data_dir_) + QStringLiteral("/models_catalog_cache.json");
    QFile cacheFile(cachePath);
    if (cacheFile.open(QIODevice::ReadOnly)) { fromCache = parseCatalog(cacheFile.readAll(), arr); }
    if (!fromCache) parseCatalog(QByteArray(kBuiltinCatalog), arr);
    // group by family, params ascending inside family (stable: family first appearance order preserved by sort key family+params)
    QVector<QJsonObject> objs;
    for (const auto& v : arr) if (v.isObject()) objs.push_back(v.toObject());
    std::sort(objs.begin(), objs.end(), [](const QJsonObject& a, const QJsonObject& b){
        const QString fa=a.value("family").toString(), fb=b.value("family").toString();
        if (fa!=fb) return fa<fb;
        return a.value("paramsB").toDouble()<b.value("paramsB").toDouble();
    });
    models_.clear();
    for (const auto& o : objs) {
        const QString repo = o.value("repo").toString();
        if (repo.isEmpty()) continue;
        QVariantMap row;
        row["repo"]=repo; row["label"]=o.value("label").toString(repo); row["size"]=o.value("size").toString();
        row["family"]=o.value("family").toString(); row["paramsB"]=o.value("paramsB").toDouble();
        row["note"]=o.value("family").toString()+QStringLiteral(" · ")+QString::number(o.value("paramsB").toDouble(),'f', o.value("paramsB").toDouble()<1?1:0)+QStringLiteral("B · 可选解码头");
        row["installed"]=weights_present(model_directory(repo.toStdString()));
        row["current"]=settings_.model_repo==repo.toStdString();
        models_.push_back(row);
    }
    catalog_status_ = fromCache ? L("列表来源：本地缓存（可点更新列表刷新）", "List: local cache (use Update list)")
                                : L("列表来源：内置目录", "List: built-in catalog");
    emit modelsChanged();
}
void Bridge::updateModelCatalog() {
    auto* nam = new QNetworkAccessManager(this);
    QNetworkRequest req{QUrl(QString::fromLatin1(kCatalogUrl))};
    QNetworkReply* reply = nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, nam]() {
        reply->deleteLater(); nam->deleteLater();
        const QByteArray raw = reply->readAll();
        QJsonArray arr;
        if (reply->error()==QNetworkReply::NoError && parseCatalog(raw, arr)) {
            const QString cachePath = QString::fromStdWString(data_dir_) + QStringLiteral("/models_catalog_cache.json");
            QFile f(cachePath); if (f.open(QIODevice::WriteOnly)) f.write(raw);
            catalog_status_ = L("模型列表已更新并缓存", "Model list updated and cached");
        } else {
            catalog_status_ = L("更新失败，已回退内置/缓存列表", "Update failed; using built-in/cache list");
        }
        refreshModels(); emit pipelineChanged();
    });
}
void Bridge::setDarkTheme(bool dark) {
    // FluentWinUI3 palette follows the application color scheme; the native
    // title bar is synced explicitly through DWM so caption color always
    // matches the in-app theme (light and dark screenshots prove this).
    if (auto* hints = QGuiApplication::styleHints())
        hints->setColorScheme(dark ? Qt::ColorScheme::Dark : Qt::ColorScheme::Light);
#ifdef Q_OS_WIN
    for (QWindow* w : QGuiApplication::topLevelWindows()) {
        const HWND hwnd = reinterpret_cast<HWND>(w->winId());
        if (!hwnd) continue;
        const BOOL immersive = dark ? TRUE : FALSE;
        DwmSetWindowAttribute(hwnd, 20 /*DWMWA_USE_IMMERSIVE_DARK_MODE*/, &immersive, sizeof(immersive));
        const COLORREF caption = dark ? 0x00202020 : 0x00F9F9F9;
        DwmSetWindowAttribute(hwnd, 35 /*DWMWA_CAPTION_COLOR*/, &caption, sizeof(caption));
        const COLORREF text = dark ? 0x00FFFFFF : 0x00000000;
        DwmSetWindowAttribute(hwnd, 36 /*DWMWA_TEXT_COLOR*/, &text, sizeof(text));
    }
#endif
}

void Bridge::repairPipeline() {
    if (pipeline_busy_ || busy_) return;
    pipeline_busy_ = true; pipeline_report_ = L("正在自检 Valhalla 管线…", "Checking the Valhalla pipeline...");
    emit pipelineChanged();
    const bool zh = lang_ == "zh";
    std::thread([this, zh]() {
        QStringList lines;
        const QString binary = QString::fromStdWString(find_binary());
        lines << (binary.isEmpty() ? L("引擎：未找到 valhalla_base.exe / .enc", "Engine: valhalla_base.exe / .enc not found")
                                   : L("引擎：已找到（含 .enc 解密路径） ", "Engine: found (incl. .enc decrypt path) ") + binary);
        lines << (L("CUDA：", "CUDA: ") + QString::fromStdWString(format_cuda(zh)));
        const bool installed = weights_present(model_directory(settings_.model_repo));
        lines << (L("模型：", "Model: ") + QString::fromStdString(settings_.model_repo) + (installed ? L(" 已就位", " present") : L(" 未下载", " not downloaded")));
        std::wstring cerr; const bool cacheOk = clear_model_decrypt_cache(cerr);
        lines << (cacheOk ? L("初始化：已清模型解密缓存 .cache", "Init: cleared model decrypt cache .cache")
                          : L("初始化：清缓存失败 ", "Init: clear cache failed ") + QString::fromStdWString(cerr));
        stop_warm_process();
        lines << L("初始化：已停 warm 进程", "Init: stopped warm process");
        QString feat;
        if (installed) {
            const std::wstring werr = ensure_framework(model_directory(settings_.model_repo));
            lines << (werr.empty() ? L("预热：引擎已预热，weights 常驻状态见模型状态", "Warm-up: engine warmed; see Model status for residency")
                                   : L("预热失败：", "Warm-up failed: ") + QString::fromStdWString(werr));
            FeatureReport rep = run_feature_probe(zh);
            feat = QString::fromStdWString(rep.text);
        } else {
            feat = L("未下载当前模型，跳过预热与 feature check（先在模型与下载中下载）", "No current model downloaded; skipped warm-up/feature check (download one first)");
        }
        const QString report = lines.join("\n") + "\n" + feat;
        QMetaObject::invokeMethod(this, [this, report]() {
            pipeline_busy_ = false; pipeline_report_ = report;
            emit pipelineChanged(); emit runtimeChanged(); refreshModels();
            setStatus(L("Valhalla 管线修复/初始化完成，详见设置页", "Pipeline repair/init done; see Settings"));
        }, Qt::QueuedConnection);
    }).detach();
}

void Bridge::loadActive() {
    lines_.clear();
    history_.clear();
    session_json_.clear();
    last_path_.clear();
    last_seconds_ = -1;
    const Transcript transcript = load_transcript(transcript_path_);
    for (const auto& line : transcript.lines) {
        lines_.push_back(Line{line.user, QString::fromStdString(line.text), QString::fromStdString(line.path)});
    }
    history_ = transcript.history;
    session_json_ = transcript.session_json;
    refreshMessages();
    emit turnChanged();
}

void Bridge::storeTranscript() {
    if (transcript_path_.empty()) return;
    Transcript transcript;
    for (const auto& line : lines_) {
        transcript.lines.push_back(TranscriptLine{line.user, line.text.toStdString(), line.path.toStdString()});
    }
    transcript.history = history_;
    transcript.session_json = session_json_;
    save_transcript(transcript_path_, transcript);
    if (!library_.active.empty()) {
        QString title = L("新对话", "New chat");
        for (const auto& line : lines_) {
            if (!line.user) continue;
            QString text = line.text.trimmed();
            if (text.isEmpty()) continue;
            const int cut = text.indexOf('\n');
            if (cut >= 0) text = text.left(cut);
            if (text.size() > 32) text = text.left(32);
            title = text;
            break;
        }
        note_conversation(library_, library_.active, title.toStdString());
    }
    refreshConversations();
}

void Bridge::pullKnowledge(const QString& text) {
    const std::string value = trim_utf8(text.toStdString());
    if (value != settings_.knowledge) {
        settings_.knowledge = value;
        saveSettings();
        session_json_.clear();
        history_.clear();
        storeTranscript();
        emit turnChanged();
    }
    sync_notes(kb_, value);
    if (!kb_path_.empty()) save_knowledge(kb_path_, kb_);
    emit knowledgeChanged();
}

void Bridge::speakText(const QString& raw) {
    const QString body = raw.trimmed();
    if (body.isEmpty()) return;
    int latin = 0, total = 0;
    for (const QChar ch : body) {
        if (ch.isLetter()) {
            ++total;
            if (ch.unicode() < 128) ++latin;
        }
    }
    const bool english = total > 0 && latin * 5 >= total * 3;
    if (!tts_.speak(body.left(1200), english, false))
        setStatus(L("这台电脑没有可用的语音，朗读没能启动。", "No speech voice is available on this PC."));
}

void Bridge::stopSpeak() { tts_.stop(); }

void Bridge::askSelection(const QString& action, const QString& raw) {
    const QString text = raw.trimmed();
    if (text.isEmpty() || busy_) return;
    const QString excerpt = QString(text.left(36)).replace('\n', ' ');
    QString asked;
    if (action == QStringLiteral("translate")) {
        display_override_ = L("翻译这段：", "Translate: ") + excerpt + QStringLiteral("…");
        asked = L("请把下面这段话翻译成英文，只输出译文；如果原文已经是英文，就翻译成中文：\n",
                  "Translate the following into English, output only the translation (into Chinese if it is already English):\n") + text.left(3000);
    } else if (action == QStringLiteral("explain")) {
        display_override_ = L("解释这段：", "Explain: ") + excerpt + QStringLiteral("…");
        asked = L("请解释下面这段内容：先一句话概括它在讲什么，再分段讲清关键概念、背景和它为什么重要：\n",
                  "Explain the following: one-line gist first, then the key concepts, background, and why it matters:\n") + text.left(3000);
    } else {
        return;
    }
    send(asked);
    display_override_.clear();
}

void Bridge::send(const QString& raw) {
    if (busy_) return;
    const QString question = raw.trimmed();
    if (question.isEmpty()) return;
    if (trim_utf8(settings_.knowledge).empty() && !has_industry(kb_)) {
        lines_.push_back(Line{false, L("知识库是空的。打开设置，写上语料，或导入行业资料。",
                                        "The knowledge base is empty. Add notes under Settings, or import industry files."),
                                {}});
        refreshMessages();
        return;
    }
    const std::wstring folder = model_directory(settings_.model_repo);
    if (!weights_present(folder)) {
        lines_.push_back(Line{false, L("这个模型还没有权重。到设置的「模型」页下载。",
                                        "That model has no weights yet. Download it under Settings, Models."),
                                {}});
        refreshMessages();
        return;
    }
    lines_.push_back(Line{true, display_override_.isEmpty() ? question : display_override_, {}});
    refreshMessages();
    setBusy(true);
    setStatus({});

    const std::string knowledge = compose_corpus(kb_, settings_.knowledge, question.toStdString());
    const std::string mode = "open"; // Fixed Valhalla mode: engine decode is hybrid; no UI strategy switch.
    last_question_ = question;
    const std::string session = settings_.keep_session ? session_json_ : std::string();
    const auto history = history_;
    const std::string screen = web_context_.isEmpty() ? screen_context_
        : (web_context_.toStdString() + (screen_context_.empty() ? std::string() : "\n\n" + screen_context_));
    const bool allow_control = settings_.allow_control;
    QString asked = question;
    if (task_mode_) asked = L("这是一项要完成的任务。直接做完，并给出结果。\n", "This is a task to finish. Do it and report the result.\n") + question;
    const auto started = std::chrono::steady_clock::now();

    std::thread([this, knowledge, mode, folder, session, history, screen, allow_control, asked, question, started]() {
        TurnResult result = run_chat(knowledge, asked.toStdString(), mode, folder, session, history, screen, allow_control);
        QMetaObject::invokeMethod(this, [this, result, question, started]() {
            setBusy(false);
            if (!result.error.empty()) {
                Line errLine; errLine.user=false; errLine.error=true; errLine.text=QString::fromStdString(result.error); lines_.push_back(errLine);
            } else {
                if (settings_.keep_session) session_json_ = result.session_json;
                else session_json_.clear();
                std::wstring script;
                std::wstring visible = strip_actions(utf8_to_wide(result.answer), script);
                std::wstring report;
                std::wstring screen;
                if (!script.empty()) {
                    run_actions(script, settings_.allow_control, report, screen);
                    if (!screen.empty()) {
                        screen_context_ = wide_to_utf8(screen);
                        reading_ = last_screen();
                        emit screenChanged();
                    }
                    if (!report.empty()) {
                        if (!visible.empty()) visible += L"\n";
                        visible += report;
                    }
                }
                if (visible.empty()) visible = utf8_to_wide(result.answer);
                last_path_ = QString::fromStdString(result.decode_path);
                last_seconds_ = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
                if (!result.decode_path.empty()) {
                    history_.emplace_back(question.toStdString(), wide_to_utf8(visible));
                }
                lines_.push_back(Line{false, QString::fromStdWString(visible), last_path_});
                emit turnChanged();
            }
            refreshMessages();
            setStatus(framework_note_);
            storeTranscript();
        }, Qt::QueuedConnection);
    }).detach();
}

void Bridge::newChat() {
    if (busy_) return;
    storeTranscript();
    create_conversation(library_);
    vallocal::setProjectFor(valDir(), QString::fromStdString(library_.active), currentProject());
    transcript_path_ = conversation_file(library_, library_.active);
    screen_context_.clear();
    web_context_.clear();
    web_sources_.clear();
    loadActive();
    storeTranscript();
    setStatus(framework_note_);
}

void Bridge::openChat(const QString& id) {
    if (busy_ || id.toStdString() == library_.active) return;
    storeTranscript();
    if (!select_conversation(library_, id.toStdString())) return;
    transcript_path_ = conversation_file(library_, library_.active);
    loadActive();
    setStatus(framework_note_);
}

void Bridge::deleteChat(const QString& id) {
    if (busy_) return;
    if (id.toStdString() == library_.active) storeTranscript();
    delete_conversation(library_, id.toStdString());
    transcript_path_ = conversation_file(library_, library_.active);
    loadActive();
}

void Bridge::setSearch(const QString& text) {
    search_ = text;
    refreshConversations();
}

void Bridge::saveKnowledge(const QString& text) { pullKnowledge(text); }

void Bridge::importFiles(const QString& domain, const QVariantList& urls) {
    if (busy_) return;
    pullKnowledge(knowledgeText());
    const std::string domain_utf8 = domain.trimmed().isEmpty() ? "industry" : domain.trimmed().toStdString();
    ImportReport total;
    for (const QVariant& value : urls) {
        const QString path = QUrl(value.toString()).toLocalFile();
        if (path.isEmpty()) continue;
        const ImportReport one = import_industry_file(kb_, path.toStdWString(), domain_utf8);
        total.added += one.added;
        total.recognized += one.recognized;
        total.failed += one.failed;
    }
    save_knowledge(kb_path_, kb_);
    session_json_.clear();
    emit knowledgeChanged();
    setStatus(L("导入完成：新增 %1 条，库中已有 %2 条，%3 个文件没有读出。",
                 "Import finished: %1 added, %2 already stored, %3 files unread.")
                  .arg(total.added)
                  .arg(total.recognized)
                  .arg(total.failed));
}


void Bridge::useOrDownloadModel(int index) {
    if (busy_ || index < 0 || index >= models_.size()) return;
    const QString repo = models_.at(index).toMap().value("repo").toString();
    if (repo.isEmpty()) return;
    if (weights_present(model_directory(repo.toStdString()))) {
        settings_.model_repo = repo.toStdString();
        save_settings(data_dir_ + L"\\settings.json", settings_);
        refreshModels(); emit pipelineChanged(); return;
    }
    setBusy(true);
    const std::string repoStd = repo.toStdString();
    std::thread([this, repoStd]() {
        std::wstring error; const bool ok = download_model(repoStd, nullptr, nullptr, error);
        QMetaObject::invokeMethod(this, [this, ok, error, repoStd]() {
            setBusy(false);
            if (ok) { settings_.model_repo = repoStd; save_settings(data_dir_ + L"\\settings.json", settings_); }
            else if (!error.empty()) setStatus(QString::fromStdWString(error));
            refreshModels(); emit pipelineChanged();
        }, Qt::QueuedConnection);
    }).detach();
}

void Bridge::setStrategy(int index) {
    if (index < 0 || index > 3) return;
    settings_.strategy = kStrategyIds[index];
    if (settings_.strategy == "followup") settings_.keep_session = true;
    saveSettings();
    session_json_.clear();
    emit settingsChanged();
}

void Bridge::setKeepSession(bool value) {
    settings_.keep_session = value;
    saveSettings();
    if (!value) session_json_.clear();
    emit settingsChanged();
}

void Bridge::setAllowControl(bool value) {
    settings_.allow_control = value;
    saveSettings();
    emit settingsChanged();
    emit screenChanged();
}

void Bridge::setTaskMode(bool value) {
    task_mode_ = value;
    emit settingsChanged();
}

void Bridge::setLanguage(int index) {
    settings_.language = index == 1 ? "zh" : index == 2 ? "en" : "system";
    saveSettings();
    lang_ = settings_.language == "system"
                ? ((GetUserDefaultUILanguage() & 0x3FF) == 0x04 ? "zh" : "en")
                : QString::fromStdString(settings_.language);
    emit langChanged();
    emit settingsChanged();
    refreshConversations();
    refreshMessages();
    refreshModels();
    emit knowledgeChanged();
    emit runtimeChanged();
    emit screenChanged();
    emit turnChanged();
}

void Bridge::recognize() {
    if (busy_) return;
    setStatus(L("正在识别屏幕…", "Reading the screen…"));
    reading_ = recognize_screen(window_);
    screen_context_ = wide_to_utf8(reading_.text);
    if (!reading_.error.empty() && reading_.ocr_lines == 0) {
        setStatus(L("识别未完成：", "Recognize failed: ") + QString::fromStdWString(reading_.error));
    } else {
        setStatus(L("OCR %1 行，控件 %2 个", "OCR %1 lines, %2 controls").arg(reading_.ocr_lines).arg(reading_.controls));
    }
    emit screenChanged();
}

void Bridge::ocrImport(const QVariantList& urls) {
    if (busy_ || urls.isEmpty()) return;
    QStringList chunks;
    for (const QVariant& value : urls) {
        const QString path = QUrl(value.toString()).toLocalFile();
        if (path.isEmpty()) continue;
        QImage image(path);
        if (image.isNull()) { chunks.push_back(QFileInfo(path).fileName() + QStringLiteral(": ") + L("图片打不开", "Cannot open image")); continue; }
        const QImage bgra = image.convertToFormat(QImage::Format_ARGB32);
        const OcrPass pass = recognize_bgra(bgra.bits(), bgra.width(), bgra.height(), static_cast<int>(bgra.bytesPerLine()));
        QStringList lines;
        static const QRegularExpression cjkSpace(QStringLiteral("([\\x{4e00}-\\x{9fff}])\\s+(?=[\\x{4e00}-\\x{9fff}])"));
        for (const auto& line : pass.lines) { QString s = QString::fromStdWString(line.text); s.replace(cjkSpace, "\\1"); lines.push_back(s); }
        chunks.push_back(lines.join("\n"));
    }
    ocr_import_text_ = chunks.join("\n\n");
    screen_context_ = ocr_import_text_.toStdString();
    setStatus(ocr_import_text_.isEmpty() ? L("OCR 导入未读出文字", "OCR import read no text") : L("OCR 导入完成，已带入对话上下文", "OCR import done; added to chat context"));
    emit screenChanged();
}
void Bridge::retryLast() {
    if (busy_ || last_question_.isEmpty()) return;
    send(last_question_);
}
void Bridge::probe() {
    if (busy_) return;
    setBusy(true);
    const bool zh = lang_ == "zh";
    std::thread([this, zh]() {
        FeatureReport report = run_feature_probe(zh);
        QMetaObject::invokeMethod(this, [this, report]() {
            setBusy(false);
            probe_text_ = QString::fromStdWString(report.text);
            emit runtimeChanged();
        }, Qt::QueuedConnection);
    }).detach();
}

// ---------------- agent tools: web search, copy, export, context ----------------
namespace {
QString htmlToText(QString s) {
    static const QRegularExpression tags(QStringLiteral("<[^>]+>"));
    static const QRegularExpression spaces(QStringLiteral("\\s+"));
    s.remove(tags);
    s.replace(QStringLiteral("&amp;"), QStringLiteral("&")).replace(QStringLiteral("&quot;"), QStringLiteral("\""))
     .replace(QStringLiteral("&#39;"), QStringLiteral("'")).replace(QStringLiteral("&#x27;"), QStringLiteral("'"))
     .replace(QStringLiteral("&lt;"), QStringLiteral("<")).replace(QStringLiteral("&gt;"), QStringLiteral(">"))
     .replace(QStringLiteral("&nbsp;"), QStringLiteral(" ")).replace(QStringLiteral("&ensp;"), QStringLiteral(" "))
     .replace(QStringLiteral("&#0183;"), QStringLiteral("·"));
    return s.replace(spaces, QStringLiteral(" ")).trimmed();
}

QVariantList parseBing(const QString& html) {
    QVariantList out;
    static const QRegularExpression title(QStringLiteral("<h2[^>]*>\\s*<a[^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>"),
                                          QRegularExpression::DotMatchesEverythingOption);
    static const QRegularExpression snippet(QStringLiteral("<p[^>]*>(.*?)</p>"), QRegularExpression::DotMatchesEverythingOption);
    static const QRegularExpression cite(QStringLiteral("<cite[^>]*>(.*?)</cite>"), QRegularExpression::DotMatchesEverythingOption);
    const QStringList blocks = html.split(QStringLiteral("<li class=\"b_algo\""));
    for (int i = 1; i < blocks.size() && out.size() < 5; ++i) {
        const QString& b = blocks[i];
        const auto t = title.match(b);
        if (!t.hasMatch()) continue;
        QString url = t.captured(1);
        if (url.contains(QStringLiteral("bing.com/ck/"))) {
            const auto c = cite.match(b);
            if (c.hasMatch()) url = htmlToText(c.captured(1));
        }
        const auto p = snippet.match(b);
        QVariantMap row;
        row["title"] = htmlToText(t.captured(2));
        row["url"] = htmlToText(url);
        row["snippet"] = p.hasMatch() ? htmlToText(p.captured(1)).left(240) : QString();
        out.push_back(row);
    }
    return out;
}
}

void Bridge::webSearch(const QString& raw, bool thenAsk) {
    const QString query = raw.trimmed();
    if (query.isEmpty() || busy_ || web_busy_) return;
    web_busy_ = true;
    emit busyChanged();
    setStatus(L("正在联网查找…", "Searching the web…"));
    QUrl url(QStringLiteral("https://cn.bing.com/search"));
    url.setQuery(QStringLiteral("q=") + QString::fromLatin1(QUrl::toPercentEncoding(query)) +
                 (lang_ == "zh" ? QStringLiteral("&setlang=zh-Hans") : QStringLiteral("&setlang=en")));
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"));
    req.setTransferTimeout(12000);
    auto* nam = new QNetworkAccessManager(this);
    QNetworkReply* reply = nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, nam, query, thenAsk]() {
        reply->deleteLater(); nam->deleteLater();
        web_busy_ = false;
        emit busyChanged();
        const bool ok = reply->error() == QNetworkReply::NoError;
        web_sources_ = ok ? parseBing(QString::fromUtf8(reply->readAll())) : QVariantList{};
        QString block;
        for (int i = 0; i < web_sources_.size(); ++i) {
            const QVariantMap r = web_sources_[i].toMap();
            block += QStringLiteral("[%1] %2\n%3\n%4\n").arg(i + 1).arg(r["title"].toString(), r["snippet"].toString(), r["url"].toString());
        }
        web_context_ = block.isEmpty() ? QString() : (L("联网查找结果（", "Web results (") + query + QStringLiteral(")：\n") + block);
        emit screenChanged();
        const QString note = web_sources_.isEmpty()
            ? (ok ? L("联网查找没有找到结果。", "Web search returned no results.")
                  : L("联网查找失败：网络不可用或被拦截。", "Web search failed: network unavailable or blocked."))
            : L("联网查找：找到 %1 条来源，已带入上下文。", "Web search: %1 sources added to context.").arg(web_sources_.size());
        setStatus(note);
        if (thenAsk) send(query);
        if (!web_sources_.isEmpty()) {
            lines_.push_back(Line{false, block.trimmed(), QStringLiteral("web")});
            refreshMessages();
        }
    });
}

void Bridge::copyText(const QString& text) {
    if (auto* cb = QGuiApplication::clipboard()) cb->setText(text);
    setStatus(L("已复制", "Copied"));
}

bool Bridge::exportChat(const QUrl& target) {
    const QString path = target.isLocalFile() ? target.toLocalFile() : target.toString();
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) { setStatus(L("导出失败：无法写入文件", "Export failed: cannot write file")); return false; }
    QString md = QStringLiteral("# ") + chatTitle() + QStringLiteral("\n\n");
    for (const auto& line : lines_)
        md += (line.user ? QStringLiteral("**") + currentUser() + QStringLiteral("**") : QStringLiteral("**VAL-DAL**")) + QStringLiteral("\n\n") + line.text + QStringLiteral("\n\n");
    f.write(md.toUtf8());
    setStatus(L("已导出：", "Exported: ") + QFileInfo(path).fileName());
    return true;
}

void Bridge::clearContext() {
    screen_context_.clear();
    reading_ = ScreenReading{};
    ocr_import_text_.clear();
    web_context_.clear();
    web_sources_.clear();
    setStatus(L("已清空本轮上下文", "Context cleared"));
    emit screenChanged();
}

// ---------------- environment (CUDA etc.) ----------------
bool Bridge::envReady() {
    const QString binary = QString::fromStdWString(find_binary());
    const QString binDir = binary.isEmpty() ? QString() : QFileInfo(binary).absolutePath();
    const QString app = QCoreApplication::applicationDirPath();
    return missingCudaDlls(binDir).isEmpty() && missingCudaDlls(app).isEmpty() &&
           !binary.isEmpty();
}

QString Bridge::envReport() {
    const QString binary = QString::fromStdWString(find_binary());
    const QString binDir = binary.isEmpty() ? QString() : QFileInfo(binary).absolutePath();
    const QString app = QCoreApplication::applicationDirPath();
    const QStringList missingBin = missingCudaDlls(binDir);
    const QStringList missingApp = missingCudaDlls(app);
    const bool model = weights_present(model_directory(settings_.model_repo));
    QStringList lines;
    lines.push_back(L("运行时：", "Runtime: ") + (binary.isEmpty() ? L("未找到", "not found") : binary));
    lines.push_back(QString::fromStdWString(gpu_status()));
    lines.push_back(L("CUDA 运行库：", "CUDA runtime: ") +
                    (missingBin.isEmpty() && missingApp.isEmpty()
                         ? L("已就位", "ready")
                         : L("缺少 ", "missing ") + QString::number(missingBin.size() + missingApp.size()) + L(" 个文件", " files")));
    lines.push_back(L("本地模型：", "Local model: ") + (model ? L("已下载", "downloaded") : L("未下载（在模型页下载）", "not downloaded (Models page)")));
    if (!findCudaDllSource().isEmpty()) lines.push_back(L("本地 CUDA 安装包：已找到，可一键配置", "Local CUDA bundle: found, one-click setup available"));
    return lines.join("\n");
}

bool Bridge::envDismissed() {
    return QFileInfo::exists(QString::fromStdWString(dataFile(L"envsetup.done")));
}

void Bridge::dismissEnvSetup() {
    QFile file(QString::fromStdWString(dataFile(L"envsetup.done")));
    if (file.open(QIODevice::WriteOnly)) file.write("ok");
    emit envChanged();
}

void Bridge::setupEnvironment() {
    const QString source = findCudaDllSource();
    if (source.isEmpty()) {
        installCudaOfficial();
        return;
    }
    const QString binary = QString::fromStdWString(find_binary());
    QStringList targets;
    if (!binary.isEmpty()) targets.push_back(QFileInfo(binary).absolutePath());
    targets.push_back(QCoreApplication::applicationDirPath());
    targets.removeDuplicates();
    setStatus(L("正在配置 CUDA 运行环境（约 700 MB，稍等）…", "Setting up the CUDA runtime (~700 MB)..."));
    std::thread([this, source, targets]() {
        int copied = 0;
        for (const QString& dir : targets) {
            for (const char* name : kCudaDlls) {
                const QString to = dir + "/" + name;
                if (QFileInfo::exists(to)) continue;
                if (QFile::copy(source + "/" + name, to)) ++copied;
            }
        }
        QMetaObject::invokeMethod(this, [this, copied]() {
            emit envChanged();
            if (envReady()) {
                dismissEnvSetup();
                setStatus(L("环境配置完成，CUDA 已就位。", "Environment ready. CUDA is in place."));
            } else {
                setStatus(L("已复制 ", "Copied ") + QString::number(copied) +
                          L(" 个文件，但仍有缺失，检查目录权限。", " files, but some are still missing. Check folder permissions."));
            }
        }, Qt::QueuedConnection);
    }).detach();
}

void Bridge::installCudaOfficial() {
    const QString installer = findCudaInstaller();
    if (installer.isEmpty()) {
        setStatus(L("没找到 CUDA 安装包。装好 NVIDIA 驱动后，到 NVIDIA 官网下载 CUDA Toolkit 12.x 即可；没有英伟达显卡则走 CPU 模式，不用装。", "No CUDA installer found. Install the NVIDIA driver, then CUDA Toolkit 12.x from NVIDIA. Without an NVIDIA GPU the CPU path needs none of this."));
        return;
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(installer));
    setStatus(L("已打开 CUDA 官方安装程序，按提示装完后重启本软件。", "The official CUDA installer is open. Restart this app when it finishes."));
}
