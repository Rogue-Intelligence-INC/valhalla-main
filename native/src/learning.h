#pragma once

// Learning records shared by the student and teacher editions: rule grading against an answer key,
// knowledge points mapped to the 中考 / 高考 syllabus, gaps, ability level and the score curve.
// Same JSON layout ("valdal-learning/1") as the Android education app, so records move between them.

#include <QDateTime>
#include <QFile>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMap>
#include <QPair>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

#include <algorithm>
#include <cmath>

namespace learn {

inline const QString kFormat = QStringLiteral("valdal-learning/1");
inline const QString kKeyHeader = QStringLiteral("【参考答案与解析】");
inline const QString kKeyHeaderEn = QStringLiteral("[Answer key]");
inline const QString kOther = QStringLiteral("其他");

struct Item {
    int n = 0;
    QString topic;
    double full = 0;
    double got = 0;
    bool known = false;  // false: a person must judge this question
};

struct Record {
    qint64 id = 0;
    QString studentId, name, subject, stage;
    qint64 time = 0;
    double score = 0;
    bool scored = false;
    double total = 0;
    QString title, source;
    QVector<Item> items;
    double rate() const { return scored && total > 0 ? score / total : -1; }
};

inline QString fmt(double v) {
    if (std::floor(v) == v) return QString::number(static_cast<qlonglong>(v));
    return QString::number(v, 'f', 1);
}

inline QString pct(double x) { return fmt(std::round(x * 1000) / 10.0) + "%"; }

// ---------- paper text ----------

inline int keyCut(const QString& paper) {
    const int a = paper.indexOf(kKeyHeader);
    return a >= 0 ? a : paper.indexOf(kKeyHeaderEn);
}

inline QString answerKeyOf(const QString& paper) {
    const int cut = keyCut(paper);
    return cut >= 0 ? paper.mid(cut).trimmed() : QString();
}

inline QString studentCopy(const QString& paper) {
    const int cut = keyCut(paper);
    return cut >= 0 ? paper.left(cut).trimmed() : paper.trimmed();
}

inline const QRegularExpression& marker() {
    static const QRegularExpression re(QStringLiteral("(^|\\n)\\s*(\\d{1,3})\\s*[.、．)·：:]"));
    return re;
}

// Text after each "N." marker up to the next one; the first occurrence of a number wins.
inline QMap<int, QString> numbered(const QString& text) {
    QMap<int, QString> out;
    QVector<QRegularExpressionMatch> hits;
    for (auto it = marker().globalMatch(text); it.hasNext();) hits.push_back(it.next());
    for (int i = 0; i < hits.size(); ++i) {
        const int n = hits[i].captured(2).toInt();
        const int start = hits[i].capturedEnd(0);
        const int end = i + 1 < hits.size() ? hits[i + 1].capturedStart(0) : text.size();
        if (!out.contains(n)) out[n] = text.mid(start, end - start).trimmed();
    }
    return out;
}

inline QMap<int, QString> questions(const QString& text) {
    const QString body = studentCopy(text);
    return numbered(body.isEmpty() ? text : body);
}

inline const QRegularExpression& pointsRe() {
    static const QRegularExpression re(QStringLiteral("[(（]\\s*(\\d+(?:\\.\\d+)?)\\s*[分S]\\s*[)）]|[(（]\\s*(\\d+(?:\\.\\d+)?)\\s*(?:points?|pts?)\\s*[)）]"),
                                       QRegularExpression::CaseInsensitiveOption);
    return re;
}

inline QMap<int, double> questionPoints(const QString& paper) {
    QMap<int, double> out;
    const QMap<int, QString> q = questions(paper);
    for (auto it = q.cbegin(); it != q.cend(); ++it) {
        const auto m = pointsRe().match(it.value());
        if (!m.hasMatch()) continue;
        bool ok = false;
        const double v = (m.captured(1).isEmpty() ? m.captured(2) : m.captured(1)).toDouble(&ok);
        if (ok) out[it.key()] = v;
    }
    return out;
}

inline QMap<int, QString> keyAnswers(const QString& key) {
    QMap<int, QString> out;
    if (!key.contains(QStringLiteral("答案")) && !key.contains(QStringLiteral("answer"), Qt::CaseInsensitive)) return out;
    QString body = answerKeyOf(key);
    if (body.isEmpty()) body = key;
    if (body.startsWith(kKeyHeader)) body = body.mid(kKeyHeader.size());
    if (body.startsWith(kKeyHeaderEn)) body = body.mid(kKeyHeaderEn.size());
    static const QRegularExpression answerLine(QStringLiteral("答[:：]"));
    static const QRegularExpression shortNote(QStringLiteral("[(（][^()（）]{0,6}[)）]"));
    const QMap<int, QString> blocks = numbered(body);
    for (auto it = blocks.cbegin(); it != blocks.cend(); ++it) {
        QString block = it.value();
        int cut = block.indexOf(QStringLiteral("解析"));
        if (cut >= 0) block = block.left(cut);
        cut = block.indexOf(QStringLiteral("Explanation"));
        if (cut >= 0) block = block.left(cut);
        QStringList lines;
        for (const QString& l : block.split('\n')) if (!l.trimmed().isEmpty()) lines << l.trimmed();
        QString line = lines.isEmpty() ? QString() : lines.first();
        for (const QString& l : lines) {
            const auto m = answerLine.match(l);
            if (m.hasMatch()) { line = l.mid(m.capturedEnd()); break; }
        }
        QString bare = QString(line).replace(pointsRe(), QString()).trimmed();
        QString shorter = QString(bare).replace(shortNote, QString()).trimmed();
        const QString value = shorter.isEmpty() ? bare : shorter;
        if (!value.isEmpty()) out[it.key()] = value;
    }
    return out;
}

inline QString normalize(const QString& text) {
    static const QString punct = QStringLiteral(".,;:!?()[]{}'\"。，、；：（）【】「」");
    QString out;
    for (QChar c : text) {
        ushort u = c.unicode();
        if (u >= 0xFF01 && u <= 0xFF5E) c = QChar(u - 0xFEE0);
        if (c.isSpace() || punct.contains(c)) continue;
        out += c.toLower();
    }
    out.replace(QChar(0x00D7), 'x').replace(QChar(0x00F7), '/');
    if (out.startsWith(QStringLiteral("答"))) out = out.mid(1);
    if (out.startsWith(QStringLiteral("answer"))) out = out.mid(6);
    return out;
}

// 1 right, 0 wrong, -1 only a person can judge.
inline int matches(const QString& keyAnswer, const QString& studentAnswer) {
    const QString k = normalize(keyAnswer), s = normalize(studentAnswer);
    if (k.isEmpty()) return -1;
    if (s.isEmpty()) return 0;
    static const QRegularExpression choice(QStringLiteral("^[a-d]$"));
    if (choice.match(k).hasMatch()) {
        for (int i = s.size() - 1; i >= 0; --i)
            if (s[i] >= 'a' && s[i] <= 'd') return s[i] == k[0] ? 1 : 0;
        return 0;
    }
    static const QRegularExpression number(QStringLiteral("-?\\d+(?:\\.\\d+)?(?:/\\d+)?"));
    auto lastNumber = [](const QString& t) {
        QString last;
        for (auto it = number.globalMatch(t); it.hasNext();) last = it.next().captured(0);
        return last;
    };
    const QString keyNum = lastNumber(k);
    if (!keyNum.isEmpty() && k.size() <= keyNum.size() + 4) return lastNumber(s) == keyNum ? 1 : 0;
    if (k.size() <= 12) return s.contains(k) ? 1 : 0;
    return -1;
}

struct RuleGrade {
    bool ok = false;
    double score = 0, total = 0;
    int unsure = 0;
    QStringList lines;
    QVector<Item> items;
};

// Question-by-question check against the key; ok=false when the key has no usable answers.
inline RuleGrade ruleGrade(const QString& key, const QString& paper, const QString& student, double fallbackTotal = 100.0) {
    RuleGrade r;
    const QMap<int, QString> answers = keyAnswers(key);
    if (answers.isEmpty()) return r;
    QMap<int, double> points = questionPoints(key);
    if (points.isEmpty()) points = questionPoints(paper);
    const QMap<int, QString> given = numbered(student);
    int unmarked = 0;
    double marked = 0;
    for (auto it = answers.cbegin(); it != answers.cend(); ++it) {
        if (points.contains(it.key())) marked += points[it.key()];
        else ++unmarked;
    }
    const double left = std::max(0.0, fallbackTotal - marked);
    const double each = unmarked > 0 ? (points.isEmpty() ? fallbackTotal : left) / unmarked : 0;
    for (auto it = answers.cbegin(); it != answers.cend(); ++it) {
        const int n = it.key();
        const double full = points.value(n, each);
        r.total += full;
        const QString mine = given.value(n);
        Item item;
        item.n = n;
        item.full = full;
        switch (matches(it.value(), mine)) {
        case 1:
            r.score += full;
            item.got = full;
            item.known = true;
            r.lines << QStringLiteral("%1. %2/%2 ✓").arg(n).arg(fmt(full));
            break;
        case 0:
            item.known = true;
            r.lines << QStringLiteral("%1. 0/%2 ✗ %3｜答案：%4").arg(n).arg(fmt(full))
                           .arg(mine.isEmpty() ? QStringLiteral("未作答") : QStringLiteral("作答：") + mine.left(30), it.value().left(30));
            break;
        default:
            ++r.unsure;
            r.lines << QStringLiteral("%1. ?/%2 需人工复核｜作答：%3｜答案：%4").arg(n).arg(fmt(full)).arg(mine.left(30), it.value().left(30));
        }
        r.items.push_back(item);
    }
    r.ok = true;
    return r;
}

// "N. a/b" lines from a model's grading reply ("?" = needs review).
inline QVector<Item> scoredLines(const QString& reply) {
    static const QRegularExpression re(QStringLiteral("(?m)^\\s*(\\d{1,3})\\s*[.、．:：]\\s*(?:得分\\s*[:：]?\\s*)?([\\d.]+|\\?)\\s*/\\s*([\\d.]+)"));
    QVector<Item> out;
    QSet<int> seen;
    for (auto it = re.globalMatch(reply); it.hasNext();) {
        const auto m = it.next();
        const int n = m.captured(1).toInt();
        bool ok = false;
        const double full = m.captured(3).toDouble(&ok);
        if (!ok || full <= 0 || seen.contains(n)) continue;
        seen.insert(n);
        Item item;
        item.n = n;
        item.full = full;
        bool known = false;
        const double got = m.captured(2).toDouble(&known);
        item.known = known;
        item.got = known ? std::clamp(got, 0.0, full) : 0;
        out.push_back(item);
    }
    return out;
}

// "总分：X/Y" (or "Total: X/Y"); false when absent or nonsense.
inline bool parseTotal(const QString& reply, double& score, double& total) {
    static const QRegularExpression re(QStringLiteral("总分[^\\d]{0,4}([\\d.]+)\\s*/\\s*([\\d.]+)|Total[^\\d]{0,4}([\\d.]+)\\s*/\\s*([\\d.]+)"),
                                       QRegularExpression::CaseInsensitiveOption);
    const auto m = re.match(reply);
    if (!m.hasMatch()) return false;
    score = (m.captured(1).isEmpty() ? m.captured(3) : m.captured(1)).toDouble();
    total = (m.captured(2).isEmpty() ? m.captured(4) : m.captured(2)).toDouble();
    return total > 0 && score >= 0 && score <= total;
}

// ---------- syllabus ----------

inline QString targetFor(const QString& stage) { return stage.contains(QStringLiteral("高")) ? QStringLiteral("高考") : QStringLiteral("中考"); }

inline QString canonicalSubject(const QString& subject) {
    static const QHash<QString, QString> alias = {
        {"math", "数学"}, {"chinese", "语文"}, {"english", "英语"}, {"physics", "物理"}, {"chemistry", "化学"},
        {"biology", "生物"}, {"history", "历史"}, {"geography", "地理"}, {"civics", "道德与法治"},
        {QStringLiteral("政治"), QStringLiteral("道德与法治")}, {QStringLiteral("思想政治"), QStringLiteral("道德与法治")}};
    const QString key = subject.trimmed().toLower();
    return alias.value(key, subject.trimmed());
}

// Common provincial full marks; regions differ, so the scaled score is a reference only.
inline int fullMark(const QString& target, const QString& subject) {
    const bool core = subject == QStringLiteral("语文") || subject == QStringLiteral("数学") || subject == QStringLiteral("英语");
    return target == QStringLiteral("高考") ? (core ? 150 : 100) : (core ? 120 : 100);
}

struct Module {
    QString name;
    QStringList keys;
};

inline QVector<Module> mods(std::initializer_list<std::pair<const char*, const char*>> rows) {
    QVector<Module> out;
    for (const auto& r : rows) out.push_back({QString::fromUtf8(r.first), QString::fromUtf8(r.second).split(' ', Qt::SkipEmptyParts)});
    return out;
}

inline const QHash<QString, QVector<Module>>& zhongkao() {
    static const QHash<QString, QVector<Module>> t = {
        {QStringLiteral("数学"), mods({{"数与式", "有理数 实数 绝对值 相反数 倒数 科学记数 整式 分式 根式 二次根式 因式分解 幂 平方根 立方根 约分 通分 化简 代数式"},
                                        {"方程与不等式", "方程 方程组 不等式 不等式组 解集 一元一次 一元二次 根的判别式 分式方程 应用题 列方程"},
                                        {"函数", "函数 一次函数 正比例 反比例 二次函数 抛物线 图象 坐标 自变量 顶点 对称轴 解析式 象限"},
                                        {"图形的性质", "三角形 四边形 平行四边形 矩形 菱形 正方形 梯形 圆 弧 弦 切线 角 平行 垂直 勾股 中位线 多边形 内角 外角"},
                                        {"图形的变化", "全等 相似 对称 轴对称 中心对称 平移 旋转 位似 三视图 投影 展开图 锐角三角函数 sin cos tan"},
                                        {"统计与概率", "统计 概率 平均数 中位数 众数 方差 频数 频率 抽样 样本 扇形图 条形图 折线图 树状图 列表法"}})},
        {QStringLiteral("语文"), mods({{"积累与运用", "字音 字形 拼音 词语 成语 病句 标点 修辞 语言运用 仿写 衔接 排序"},
                                        {"古诗文阅读", "文言 古诗 诗词 诗句 翻译 默写 实词 虚词 词义 句读 断句 作者 情感 意象"},
                                        {"现代文阅读", "阅读 文章 段落 文中 表达效果 作用 主旨 中心 人物形象 说明方法 论点 论据 记叙"},
                                        {"名著阅读", "名著 西游记 水浒 朝花夕拾 骆驼祥子 红星照耀中国 钢铁是怎样炼成的 海底两万里 儒林外史 简爱"},
                                        {"写作", "作文 写作 不少于 字数 题目自拟 文体 立意 选材"}})},
        {QStringLiteral("英语"), mods({{"词汇与语法", "单词 词汇 时态 语法 介词 代词 冠词 形容词 副词 比较级 被动 从句 情态 动词 单项选择"},
                                        {"完形填空", "完形 cloze"},
                                        {"阅读理解", "阅读理解 passage according to main idea paragraph article 短文"},
                                        {"书面表达", "书面表达 作文 写作 writing letter 不少于 words"},
                                        {"听力与口语", "听力 listen dialogue 对话 口语"}})},
        {QStringLiteral("物理"), mods({{"力学", "力 速度 路程 压强 浮力 密度 质量 重力 摩擦 杠杆 滑轮 机械 功 功率 机械效率 动能 势能 惯性 运动 牛顿"},
                                        {"电磁学", "电 电路 电流 电压 电阻 欧姆 串联 并联 电功 电功率 电能 磁 电磁 发电机 电动机 安全用电"},
                                        {"热学", "温度 热 内能 比热容 熔化 凝固 汽化 液化 升华 凝华 沸腾 热机 燃料"},
                                        {"光学", "光 反射 折射 平面镜 透镜 凸透镜 凹透镜 成像 焦距 色散"},
                                        {"声学", "声 声音 音调 响度 音色 噪声 超声 回声"}})},
        {QStringLiteral("化学"), mods({{"物质构成", "原子 分子 离子 元素 化学式 化合价 相对原子质量 周期表 微粒 纯净物 混合物"},
                                        {"化学反应", "化学方程式 反应 质量守恒 化合 分解 置换 复分解 氧化 还原 催化剂 配平"},
                                        {"溶液与酸碱盐", "溶液 溶解度 溶质 溶剂 饱和 酸 碱 盐 pH 中和 指示剂 沉淀"},
                                        {"身边的化学物质", "氧气 二氧化碳 水 空气 金属 铁 铜 碳 一氧化碳 合金 锈蚀"},
                                        {"实验探究", "实验 装置 仪器 气体 制取 收集 检验 除杂 鉴别 操作 现象"},
                                        {"化学与生活", "燃烧 灭火 能源 燃料 材料 营养 有机 塑料 环境 污染"}})},
        {QStringLiteral("生物"), mods({{"细胞与生物体", "细胞 细胞膜 细胞核 叶绿体 组织 器官 系统 显微镜 单细胞"},
                                        {"植物生命活动", "光合作用 呼吸作用 蒸腾 种子 萌发 根 茎 叶 开花 结果 植物"},
                                        {"人体生理", "消化 呼吸 循环 血液 心脏 神经 反射 激素 泌尿 免疫 营养"},
                                        {"遗传与进化", "遗传 基因 染色体 DNA 性状 变异 进化 显性 隐性 生殖"},
                                        {"生物与环境", "生态系统 食物链 食物网 生物圈 环境 生态 种群"}})},
        {QStringLiteral("历史"), mods({{"中国古代史", "秦 汉 唐 宋 元 明 清 朝 皇帝 科举 丝绸之路 春秋 战国 三国 隋"},
                                        {"中国近现代史", "鸦片战争 辛亥革命 五四 抗日 解放战争 新中国 改革开放 洋务 戊戌 长征 中华人民共和国"},
                                        {"世界史", "文艺复兴 工业革命 资产阶级革命 美国 英国 法国 世界大战 冷战 苏联 殖民"}})},
        {QStringLiteral("地理"), mods({{"地球与地图", "经纬 经线 纬线 地球 自转 公转 地图 比例尺 等高线 时区"},
                                        {"自然地理", "气候 气温 降水 地形 河流 季风 天气 板块 自然灾害"},
                                        {"人文地理", "人口 城市 农业 工业 交通 民族 聚落 资源 经济"},
                                        {"区域地理", "中国 亚洲 欧洲 非洲 美洲 省 区域 黄土高原 长江 黄河"}})},
        {QStringLiteral("道德与法治"), mods({{"道德与心理", "道德 品德 友谊 情绪 青春期 生命 责任 诚信 自尊"},
                                              {"法律与规则", "法律 宪法 权利 义务 违法 犯罪 规则 未成年人 保护"},
                                              {"国情与社会", "国情 社会 民主 政治 文化 生态文明 改革开放 一带一路 中国梦"}})},
    };
    return t;
}

inline const QHash<QString, QVector<Module>>& gaokao() {
    static const QHash<QString, QVector<Module>> t = {
        {QStringLiteral("数学"), mods({{"集合与常用逻辑", "集合 交集 并集 补集 子集 充分 必要 命题 量词 逻辑"},
                                        {"函数与导数", "函数 定义域 值域 单调 奇偶 周期 指数 对数 幂函数 导数 切线 极值 最值 零点"},
                                        {"三角函数与解三角形", "三角 正弦 余弦 正切 sin cos tan 诱导公式 解三角形 周期 相位"},
                                        {"数列", "数列 等差 等比 通项 前n项 递推 求和"},
                                        {"不等式", "不等式 基本不等式 均值 线性规划 恒成立"},
                                        {"平面向量与复数", "向量 数量积 复数 虚部 实部 共轭 模"},
                                        {"立体几何", "棱柱 棱锥 圆柱 圆锥 球 三视图 空间 二面角 线面 面面 平行 垂直 体积 表面积 空间向量"},
                                        {"解析几何", "直线 斜率 圆 椭圆 双曲线 抛物线 离心率 焦点 准线 弦长 渐近线"},
                                        {"计数原理与概率统计", "概率 排列 组合 二项式 分布列 期望 方差 正态 回归 独立性 抽样 频率分布 统计"}})},
        {QStringLiteral("语文"), mods({{"语言文字运用", "字音 字形 词语 成语 病句 标点 修辞 语言运用 衔接 补写 压缩"},
                                        {"文言文阅读", "文言 实词 虚词 翻译 断句 文化常识 句式"},
                                        {"古代诗歌阅读", "诗歌 古诗 诗词 意象 意境 鉴赏 表现手法 情感"},
                                        {"名篇名句默写", "默写 名句 补写出"},
                                        {"现代文阅读", "论述类 实用类 文学类 小说 散文 阅读 文本 作用 主旨 人物形象"},
                                        {"写作", "作文 写作 不少于 字数 立意 文体"}})},
        {QStringLiteral("英语"), mods({{"听力", "听力 listen dialogue conversation"},
                                        {"阅读理解", "阅读理解 passage according to main idea paragraph article best title"},
                                        {"七选五", "七选五 options sentence"},
                                        {"完形填空", "完形 cloze"},
                                        {"语法填空", "语法填空 时态 语法 从句 非谓语 介词 冠词 被动"},
                                        {"写作", "书面表达 读后续写 概要 作文 写作 writing letter words"}})},
        {QStringLiteral("物理"), mods({{"运动与力", "运动 速度 加速度 位移 自由落体 力 牛顿 摩擦 受力 平衡 抛体 圆周"},
                                        {"能量与动量", "功 功率 动能 势能 机械能 能量守恒 动量 冲量 碰撞"},
                                        {"万有引力与航天", "万有引力 卫星 天体 宇宙速度 轨道 开普勒"},
                                        {"电场与电路", "电场 电势 电容 电荷 库仑 电路 电流 电阻 电动势 欧姆"},
                                        {"磁场与电磁感应", "磁场 洛伦兹 安培力 电磁感应 楞次 交变电流 变压器 法拉第"},
                                        {"热光原近代", "热学 分子 气体 光 折射 干涉 衍射 光电效应 原子 核 衰变 波 振动"},
                                        {"实验", "实验 测量 误差 读数 打点计时器 器材"}})},
        {QStringLiteral("化学"), mods({{"物质结构与周期律", "原子结构 周期表 周期律 化学键 电子排布 杂化 晶体 分子结构"},
                                        {"化学反应原理", "反应速率 化学平衡 平衡常数 热化学 焓变 电化学 原电池 电解 盖斯"},
                                        {"电解质溶液", "电离 水解 pH 溶度积 离子浓度 弱电解质 缓冲"},
                                        {"元素化合物", "钠 铝 铁 铜 氯 硫 氮 硅 金属 非金属 氧化物 化合物"},
                                        {"有机化学", "有机 烃 醇 醛 酸 酯 官能团 同分异构 聚合 合成路线 苯"},
                                        {"化学实验", "实验 装置 仪器 分离 提纯 滴定 检验 操作 现象"},
                                        {"化学计算与计量", "物质的量 摩尔 阿伏加德罗 浓度 计算 守恒"}})},
        {QStringLiteral("生物"), mods({{"分子与细胞", "蛋白质 核酸 糖类 脂质 细胞 细胞膜 细胞器 酶 ATP 光合作用 呼吸作用 有丝分裂"},
                                        {"遗传与进化", "遗传 孟德尔 基因 染色体 DNA 复制 转录 翻译 变异 育种 进化 减数分裂"},
                                        {"稳态与调节", "内环境 稳态 神经调节 激素 体液调节 免疫 植物激素 生长素"},
                                        {"生物与环境", "种群 群落 生态系统 能量流动 物质循环 生态"},
                                        {"生物技术与工程", "发酵 基因工程 细胞工程 胚胎工程 PCR 克隆 微生物 培养基"}})},
        {QStringLiteral("历史"), mods({{"中国古代史", "秦 汉 唐 宋 元 明 清 朝 科举 郡县 中央集权 丝绸之路"},
                                        {"中国近现代史", "鸦片战争 辛亥革命 五四 新民主主义 抗日 新中国 改革开放 社会主义建设"},
                                        {"世界史", "古希腊 罗马 文艺复兴 宗教改革 启蒙 工业革命 资本主义 世界大战 冷战 全球化"},
                                        {"史料与史观", "史料 材料 观点 论证 史观 评价"}})},
        {QStringLiteral("地理"), mods({{"自然地理", "地球运动 大气 气候 水循环 洋流 地貌 地质 植被 土壤 自然灾害 昼夜 正午太阳高度"},
                                        {"人文地理", "人口 城市化 农业区位 工业区位 交通 服务业 文化 区位"},
                                        {"区域与可持续发展", "区域 资源 生态 环境 可持续 跨区域 调水 产业转移"},
                                        {"地理技能", "地图 等值线 比例尺 经纬网 遥感 GIS 读图"}})},
        {QStringLiteral("道德与法治"), mods({{"经济与社会", "经济 市场 企业 分配 财政 税收 宏观调控 新发展理念"},
                                              {"政治与法治", "人民代表大会 政党 人民民主 法治 宪法 政府 民族区域"},
                                              {"哲学与文化", "唯物论 辩证法 认识论 历史唯物主义 矛盾 实践 文化"},
                                              {"逻辑与思维", "逻辑 推理 概念 判断 思维"}})},
    };
    return t;
}

inline QVector<Module> modules(const QString& subject, const QString& target) {
    return (target == QStringLiteral("高考") ? gaokao() : zhongkao()).value(canonicalSubject(subject));
}

inline QStringList syllabus(const QString& subject, const QString& stage) {
    QStringList out;
    for (const Module& m : modules(subject, targetFor(stage))) out << m.name;
    return out;
}

inline QString topicOf(const QString& subject, const QString& stage, const QString& text) {
    const QString lower = text.toLower();
    QString best = kOther;
    int bestHits = 0;
    for (const Module& m : modules(subject, targetFor(stage))) {
        int hits = 0;
        for (const QString& k : m.keys) {
            const QString key = k.toLower();
            for (int from = lower.indexOf(key); from >= 0; from = lower.indexOf(key, from + key.size())) hits += key.size() >= 2 ? 2 : 1;
        }
        if (hits > bestHits) { bestHits = hits; best = m.name; }
    }
    return best;
}

inline void tagItems(QVector<Item>& items, const QString& subject, const QString& stage, const QString& paper, const QString& key, const QString& student) {
    const QMap<int, QString> q = questions(paper);
    const QString keyBody = answerKeyOf(key);
    const QMap<int, QString> k = questions(keyBody.isEmpty() ? key : keyBody);
    const QMap<int, QString> a = questions(student);
    for (Item& item : items) item.topic = topicOf(subject, stage, q.value(item.n) + " " + k.value(item.n) + " " + a.value(item.n));
}

// Student id and name from a file name like "2023015_张三" or "学号：… 姓名：…" on the paper.
inline QPair<QString, QString> identity(const QString& fileName, const QString& text) {
    static const QRegularExpression idFile(QStringLiteral("^([A-Za-z]?\\d{3,14})[\\s_\\-.·、]*(.*)$"));
    static const QRegularExpression idText(QStringLiteral("学\\s*号\\s*[:：]?\\s*([A-Za-z]?\\d{3,14})"));
    static const QRegularExpression nameText(QStringLiteral("姓\\s*名\\s*[:：]?\\s*([\\x{4e00}-\\x{9fa5}]{2,4})"));
    const QString base = fileName.trimmed();
    const QString nameOnPaper = nameText.match(text).captured(1);
    const auto f = idFile.match(base);
    if (f.hasMatch()) {
        QString name = f.captured(2).trimmed();
        if (name.isEmpty()) name = nameOnPaper;
        return {f.captured(1), name.isEmpty() ? f.captured(1) : name};
    }
    const QString id = idText.match(text).captured(1);
    const QString shown = base.isEmpty() ? nameOnPaper : base;
    const QString name = nameOnPaper.isEmpty() ? (shown.isEmpty() ? id : shown) : nameOnPaper;
    return {!id.isEmpty() ? id : (!nameOnPaper.isEmpty() ? nameOnPaper : shown), name};
}

// ---------- storage ----------

inline QJsonObject toJson(const Record& r) {
    QJsonArray items;
    for (const Item& i : r.items) {
        QJsonObject o{{"n", i.n}, {"topic", i.topic}, {"full", i.full}};
        o["got"] = i.known ? QJsonValue(i.got) : QJsonValue(QJsonValue::Null);
        items.push_back(o);
    }
    QJsonObject o{{"id", QString::number(r.id)}, {"studentId", r.studentId}, {"name", r.name}, {"subject", r.subject}, {"stage", r.stage},
                  {"time", static_cast<double>(r.time)}, {"total", r.total}, {"title", r.title}, {"source", r.source}, {"items", items}};
    o["score"] = r.scored ? QJsonValue(r.score) : QJsonValue(QJsonValue::Null);
    return o;
}

inline bool fromJson(const QJsonObject& o, Record& r) {
    r.studentId = o.value("studentId").toString().trimmed();
    if (r.studentId.isEmpty()) return false;
    const QJsonValue id = o.value("id");
    r.id = id.isString() ? id.toString().toLongLong() : static_cast<qint64>(id.toDouble());
    if (r.id == 0) r.id = QDateTime::currentMSecsSinceEpoch() * 1000;
    r.name = o.value("name").toString(r.studentId);
    r.subject = o.value("subject").toString();
    r.stage = o.value("stage").toString(QStringLiteral("初中"));
    r.time = static_cast<qint64>(o.value("time").toDouble(static_cast<double>(QDateTime::currentMSecsSinceEpoch())));
    r.scored = o.value("score").isDouble();
    r.score = o.value("score").toDouble();
    r.total = o.value("total").toDouble();
    r.title = o.value("title").toString();
    r.source = o.value("source").toString(QStringLiteral("import"));
    r.items.clear();
    for (const QJsonValue& v : o.value("items").toArray()) {
        const QJsonObject io = v.toObject();
        Item i;
        i.n = io.value("n").toInt();
        i.topic = io.value("topic").toString(kOther);
        i.full = io.value("full").toDouble();
        i.known = io.value("got").isDouble();
        i.got = io.value("got").toDouble();
        r.items.push_back(i);
    }
    return true;
}

inline QByteArray exportJson(const QVector<Record>& records) {
    QJsonArray rows;
    for (const Record& r : records) rows.push_back(toJson(r));
    return QJsonDocument(QJsonObject{{"format", kFormat}, {"records", rows}}).toJson(QJsonDocument::Indented);
}

inline QVector<Record> parseJson(const QByteArray& raw, bool* ok = nullptr) {
    QVector<Record> out;
    QByteArray data = raw;
    if (data.startsWith("\xEF\xBB\xBF")) data = data.mid(3);
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &err);
    if (ok) *ok = err.error == QJsonParseError::NoError && doc.isObject() && doc.object().contains("records");
    for (const QJsonValue& v : doc.object().value("records").toArray()) {
        Record r;
        if (fromJson(v.toObject(), r)) out.push_back(r);
    }
    return out;
}

inline QVector<Record> load(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return {};
    return parseJson(f.readAll());
}

inline bool save(const QString& path, const QVector<Record>& records) {
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly)) return false;
    f.write(exportJson(records));
    return f.commit();
}

inline qint64 newId() {
    static qint64 last = 0;
    qint64 id = QDateTime::currentMSecsSinceEpoch() * 1000;
    if (id <= last) id = last + 1;
    last = id;
    return id;
}

// ---------- analysis (QML-friendly maps) ----------

inline QVariantMap analyze(const QVector<Record>& all, const QString& subject = QString()) {
    QVector<Record> picked;
    for (const Record& r : all)
        if (subject.isEmpty() || canonicalSubject(r.subject) == canonicalSubject(subject)) picked.push_back(r);
    std::sort(picked.begin(), picked.end(), [](const Record& a, const Record& b) { return a.time < b.time; });

    QVariantList curve, records;
    QStringList subjects;
    struct Acc { double got = 0, full = 0; int count = 0, wrong = 0; };
    QMap<QPair<QString, QString>, Acc> acc;
    QList<QPair<QString, QString>> order;
    for (const Record& r : picked) {
        const QString subj = canonicalSubject(r.subject);
        if (!subjects.contains(subj)) subjects << subj;
        if (r.rate() >= 0) curve.push_back(QVariantMap{{"time", static_cast<double>(r.time)}, {"rate", r.rate()}, {"subject", subj},
                                                       {"day", QDateTime::fromMSecsSinceEpoch(r.time).toString(QStringLiteral("M/d"))}});
        QStringList lost;
        for (const Item& i : r.items) {
            if (!i.known) continue;
            const auto key = qMakePair(subj, i.topic);
            if (!acc.contains(key)) order << key;
            Acc& a = acc[key];
            a.got += i.got;
            a.full += i.full;
            ++a.count;
            if (i.got < i.full) { ++a.wrong; lost << QStringLiteral("%1题%2").arg(i.n).arg(i.topic); }
        }
        records.prepend(QVariantMap{{"id", QString::number(r.id)}, {"day", QDateTime::fromMSecsSinceEpoch(r.time).toString(QStringLiteral("yyyy-MM-dd"))},
                                    {"subject", subj}, {"title", r.title}, {"score", r.score}, {"total", r.total}, {"scored", r.scored},
                                    {"source", r.source}, {"count", r.items.size()}, {"lost", lost.join(QStringLiteral("、"))}});
    }
    QVariantList weak, mastered;
    QVector<QVariantMap> weakRows, masteredRows;
    QSet<QPair<QString, QString>> seen;
    for (const auto& key : order) {
        seen.insert(key);
        if (key.second == kOther) continue;
        const Acc& a = acc[key];
        const double rate = a.full > 0 ? a.got / a.full : 0;
        QVariantMap row{{"subject", key.first}, {"topic", key.second}, {"rate", rate}, {"count", a.count}, {"wrong", a.wrong}};
        if (rate < 0.6) weakRows << row;
        else if (rate >= 0.85) masteredRows << row;
    }
    std::sort(weakRows.begin(), weakRows.end(), [](const QVariantMap& a, const QVariantMap& b) { return a["rate"].toDouble() < b["rate"].toDouble(); });
    std::sort(masteredRows.begin(), masteredRows.end(), [](const QVariantMap& a, const QVariantMap& b) { return a["rate"].toDouble() > b["rate"].toDouble(); });
    for (const auto& r : weakRows) weak << r;
    for (const auto& r : masteredRows) mastered << r;

    QStringList untested;
    QVariantList abilities;
    for (const QString& subj : subjects) {
        QVector<double> rates;
        QString stage;
        for (const Record& r : picked) {
            if (canonicalSubject(r.subject) != subj) continue;
            stage = r.stage;
            if (r.rate() >= 0) rates << r.rate();
        }
        for (const QString& m : syllabus(subj, stage))
            if (!seen.contains(qMakePair(subj, m))) untested << (subject.isEmpty() ? subj + QStringLiteral("·") + m : m);
        if (rates.isEmpty()) continue;
        const QString target = targetFor(stage);
        const int from = std::max(0, static_cast<int>(rates.size()) - 5);
        double recent = 0;
        for (int i = from; i < rates.size(); ++i) recent += rates[i];
        recent /= (rates.size() - from);
        QString trend = QStringLiteral("数据不足");
        if (rates.size() >= 2) {
            const int half = static_cast<int>(rates.size()) / 2;
            double first = 0, last = 0;
            for (int i = 0; i < half; ++i) first += rates[i];
            for (int i = static_cast<int>(rates.size()) - half; i < rates.size(); ++i) last += rates[i];
            const double diff = last / half - first / half;
            trend = diff > 0.05 ? QStringLiteral("上升") : diff < -0.05 ? QStringLiteral("下降") : QStringLiteral("平稳");
        }
        double mean = 0;
        for (double v : rates) mean += v;
        mean /= rates.size();
        double var = 0;
        for (double v : rates) var += (v - mean) * (v - mean);
        const double spread = std::sqrt(var / rates.size()) * 100;
        const bool zk = target == QStringLiteral("中考");
        QString level, text;
        if (recent >= 0.85) { level = "A"; text = zk ? QStringLiteral("优秀：达到中考 A 等水平") : QStringLiteral("优秀：高考高分段水平"); }
        else if (recent >= 0.70) { level = "B"; text = zk ? QStringLiteral("良好：中考 B 等，冲 A 需补齐薄弱考点") : QStringLiteral("良好：高考中上水平，薄弱模块是提分空间"); }
        else if (recent >= 0.60) { level = "C"; text = zk ? QStringLiteral("合格：刚过中考合格线，基础题要稳住") : QStringLiteral("合格：高考及格水平，先抓基础分"); }
        else { level = "D"; text = zk ? QStringLiteral("待提高：低于中考合格线，需要系统补弱") : QStringLiteral("待提高：低于高考及格线，先补核心模块"); }
        const int full = fullMark(target, subj);
        abilities << QVariantMap{{"subject", subj}, {"target", target}, {"fullMark", full}, {"rate", recent}, {"scaled", std::round(recent * full * 10) / 10.0},
                                 {"level", level}, {"levelText", text}, {"trend", trend}, {"spread", std::round(spread * 10) / 10.0}, {"exams", static_cast<int>(rates.size())}};
    }
    return QVariantMap{{"count", picked.size()}, {"curve", curve}, {"subjects", subjects}, {"abilities", abilities}, {"weak", weak},
                       {"mastered", mastered}, {"untested", untested}, {"records", records}};
}

inline QString report(const QVariantMap& p, const QString& who) {
    if (p.value("count").toInt() == 0) return who + QStringLiteral("：还没有测评记录。");
    QString out = who + QStringLiteral("：共 %1 次测评。\n").arg(p.value("count").toInt());
    for (const QVariant& v : p.value("abilities").toList()) {
        const QVariantMap a = v.toMap();
        out += QStringLiteral("【%1】按%2口径（满分 %3）：近期得分率 %4，折算约 %5 分，%6 等 · %7；趋势%8，波动 %9 个百分点，共 %10 次。\n")
                   .arg(a["subject"].toString(), a["target"].toString()).arg(a["fullMark"].toInt()).arg(pct(a["rate"].toDouble()), fmt(a["scaled"].toDouble()),
                        a["level"].toString(), a["levelText"].toString(), a["trend"].toString(), fmt(a["spread"].toDouble())).arg(a["exams"].toInt());
    }
    QStringList weak;
    for (const QVariant& v : p.value("weak").toList()) {
        const QVariantMap w = v.toMap();
        if (weak.size() < 8) weak << QStringLiteral("%1·%2 %3（%4 题错 %5）").arg(w["subject"].toString(), w["topic"].toString(), pct(w["rate"].toDouble())).arg(w["count"].toInt()).arg(w["wrong"].toInt());
    }
    if (!weak.isEmpty()) out += QStringLiteral("薄弱考点：") + weak.join(QStringLiteral("；")) + "\n";
    const QStringList untested = p.value("untested").toStringList();
    if (!untested.isEmpty()) out += QStringLiteral("尚未测到的考纲模块：") + untested.mid(0, 12).join(QStringLiteral("、")) + "\n";
    QStringList good;
    for (const QVariant& v : p.value("mastered").toList()) if (good.size() < 8) good << v.toMap()["subject"].toString() + QStringLiteral("·") + v.toMap()["topic"].toString();
    if (!good.isEmpty()) out += QStringLiteral("已掌握：") + good.join(QStringLiteral("、")) + "\n";
    return out.trimmed();
}

// One row per student id: name, exams, last / average rate, weak-topic count.
inline QVariantList roster(const QVector<Record>& records) {
    QMap<QString, QVector<Record>> by;
    for (const Record& r : records) by[r.studentId].push_back(r);
    QVariantList out;
    for (auto it = by.cbegin(); it != by.cend(); ++it) {
        QVector<Record> rs = it.value();
        std::sort(rs.begin(), rs.end(), [](const Record& a, const Record& b) { return a.time < b.time; });
        double sum = 0, last = -1;
        int rated = 0;
        for (const Record& r : rs) if (r.rate() >= 0) { sum += r.rate(); last = r.rate(); ++rated; }
        out << QVariantMap{{"id", it.key()}, {"name", rs.last().name}, {"exams", rs.size()}, {"lastRate", last}, {"avgRate", rated ? sum / rated : -1.0},
                           {"weak", analyze(rs).value("weak").toList().size()},
                           {"day", QDateTime::fromMSecsSinceEpoch(rs.last().time).toString(QStringLiteral("M/d"))}};
    }
    return out;
}

}  // namespace learn
