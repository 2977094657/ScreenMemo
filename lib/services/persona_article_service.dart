import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/memory_models.dart';
import 'locale_service.dart';
import 'ai_chat_service.dart';
import 'memory_bridge_service.dart';
import 'ai_settings_service.dart';
import 'ai_providers_service.dart';
import 'screenshot_database.dart';

enum PersonaArticleStyle { narrative, timeline }

class PersonaArticleCache {
  const PersonaArticleCache({
    required this.style,
    required this.article,
    this.updatedAt,
    this.localeTag,
    this.aiProvider,
    this.aiModel,
  });

  final PersonaArticleStyle style;
  final String article;
  final DateTime? updatedAt;
  final String? localeTag;
  final String? aiProvider;
  final String? aiModel;
}

class PersonaArticleService {
  PersonaArticleService._internal();
  static final PersonaArticleService instance =
      PersonaArticleService._internal();

  final MemoryBridgeService _memory = MemoryBridgeService.instance;
  final AIChatService _chat = AIChatService.instance;
  final AISettingsService _settings = AISettingsService.instance;
  final AIProvidersService _providers = AIProvidersService.instance;
  final ScreenshotDatabase _db = ScreenshotDatabase.instance;

  Stream<AIStreamEvent> streamArticle({
    PersonaArticleStyle style = PersonaArticleStyle.narrative,
    Locale? localeOverride,
  }) async* {
    await _memory.ensureInitialized();
    final PersonaProfile profile = _memory.latestPersonaProfile;
    final String personaMarkdown = profile.toMarkdown();
    final String personaJson = profile.toPrettyJsonString(2);
    final String personaSummary = _memory.latestPersonaSummary;
    final Locale locale =
        localeOverride ??
        LocaleService.instance.locale ??
        WidgetsBinding.instance.platformDispatcher.locale;

    final String prompt = _buildPrompt(
      locale: locale,
      style: style,
      personaMarkdown: personaMarkdown,
      personaJson: personaJson,
      personaSummary: personaSummary,
    );

    final AIStreamingSession session =
        await _chat.sendMessageStreamedV2WithDisplayOverride(
      'persona_article_${style.name}',
      prompt,
      includeHistory: false,
      persistHistory: false,
      extraSystemMessages: <String>[
        'Respond strictly in Markdown paragraphs. Do not output JSON or wrap the entire article inside code fences.',
      ],
    );
    yield* session.stream;
  }

  Future<PersonaArticleCache?> loadCachedArticle({
    PersonaArticleStyle style = PersonaArticleStyle.narrative,
  }) async {
    try {
      final Map<String, dynamic>? row =
          await _db.getPersonaArticle(style.name);
      if (row == null) return null;
      final int? updatedAt = row['updated_at'] as int?;
      return PersonaArticleCache(
        style: style,
        article: (row['article'] as String?) ?? '',
        updatedAt: updatedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(updatedAt)
            : null,
        localeTag: row['locale'] as String?,
        aiProvider: row['ai_provider'] as String?,
        aiModel: row['ai_model'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> persistArticle({
    required PersonaArticleStyle style,
    required String article,
    Locale? localeOverride,
  }) async {
    final String normalized = article.trim();
    if (normalized.isEmpty) return;
    final Locale locale =
        localeOverride ??
        LocaleService.instance.locale ??
        WidgetsBinding.instance.platformDispatcher.locale;

    String? providerName;
    String? model;
    try {
      final Map<String, dynamic>? ctx =
          await _db.getAIContext('chat');
      AIProvider? provider;
      if (ctx != null && ctx['provider_id'] is int) {
        provider =
            await _providers.getProvider(ctx['provider_id'] as int);
      } else {
        provider = await _providers.getDefaultProvider();
      }
      providerName = provider?.name;
      model = (ctx != null ? (ctx['model'] as String?) : null)?.trim();
      model ??= (provider?.extra['active_model'] as String?)?.trim();
      if ((model == null || model.isEmpty) && provider != null) {
        if (provider.defaultModel.isNotEmpty) {
          model = provider.defaultModel;
        } else if (provider.models.isNotEmpty) {
          model = provider.models.first;
        }
      }
    } catch (_) {}
    model ??= await _settings.getModel();

    await _db.upsertPersonaArticle(
      style: style.name,
      article: normalized,
      locale: _localeTag(locale),
      aiProvider: providerName,
      aiModel: model,
    );
  }

  Future<void> clearCachedArticle({PersonaArticleStyle? style}) async {
    await _db.clearPersonaArticles(style: style?.name);
  }

  String _buildPrompt({
    required Locale locale,
    required PersonaArticleStyle style,
    required String personaMarkdown,
    required String personaJson,
    required String personaSummary,
  }) {
    final String languageInstruction = _languageInstruction(locale);
    final String promptStyle = _styleInstruction(style, locale);
    final String template = _promptTemplate(locale);
    return template
        .replaceAll('{{LANG}}', languageInstruction)
        .replaceAll('{{STYLE}}', promptStyle)
        .replaceAll('{{SUMMARY}}', personaSummary)
        .replaceAll('{{MARKDOWN}}', personaMarkdown)
        .replaceAll('{{JSON}}', personaJson);
  }

  String _localeTag(Locale locale) {
    final List<String> segments = <String>[
      locale.languageCode.toLowerCase(),
    ];
    final String? script = locale.scriptCode;
    if (script != null && script.isNotEmpty) {
      segments.add(script);
    }
    final String? country = locale.countryCode;
    if (country != null && country.isNotEmpty) {
      segments.add(country.toUpperCase());
    }
    return segments.join('-');
  }

  String _languageInstruction(Locale locale) {
    final String code = locale.languageCode.toLowerCase();
    if (code.startsWith('zh')) {
      return '全文使用简体中文，保持自然、有温度的语气';
    }
    if (code.startsWith('ja')) {
      return '全文使用自然的日本語，语气亲切但专业';
    }
    if (code.startsWith('ko')) {
      return '全文使用自然的한국어，保持真诚、温暖的笔触';
    }
    return 'Write the entire article in natural ${locale.languageCode.toUpperCase()}';
  }

  String _styleInstruction(PersonaArticleStyle style, Locale locale) {
    final String code = locale.languageCode.toLowerCase();
    switch (style) {
      case PersonaArticleStyle.timeline:
        if (code.startsWith('ja')) {
          return '''
構成ガイド：時間軸スタイルで主要な出来事をつなぎ、必要に応じて柔軟に調整してください。
1. **日常のリズム**：長期的に繰り返す起点を一文で説明し、「〜の部屋で彼は…」といった場面描写は避ける。
2. **成長の節目**：動機・行動・結果を時間順にまとめ、必要に応じて使用したツールや作品名を示す。
3. **振り返りと次の一歩**：これらの行動がユーザーにとって何を意味するのか、今後の方向性とともにまとめる。
各セクションは2～3段落の散文で記述し、箇条書きは避け、描写と内面の流れを中心に構成してください。記事冒頭で場面描写を行わず、人物と主題を直接提示してください。''';
        }
        if (code.startsWith('ko')) {
          return '''
작성 가이드: 시간순 로그 스타일로 핵심 사건을 엮되, 필요에 따라 자유롭게 재구성하세요.
1. **일상의 리듬**: 장기적으로 반복되는 시작 지점을 한 문장으로 설명하고 “어느 장소에서 그는…” 같은 장면 묘사는 금지합니다.
2. **성장의 분기점**: 동기·행동·결과를 시간순으로 정리하고, 사용한 도구나 작품명을 자연스럽게 언급합니다.
3. **되돌아봄과 다음 단계**: 이러한 경험이 사용자에게 어떤 의미가 있는지, 앞으로의 계획과 함께 정리합니다.
각 파트는 2~3개의 문단으로 이루어진 산문 형태여야 하며, 나열식 표현을 지양하고 묘사와 내적 흐름에 집중하세요. 글의 첫 문장은 반드시 주제와 정체성을 직접적으로 밝혀야 합니다.''';
        }
        if (code.startsWith('zh')) {
          return '''
写作结构：以“时间轴日志”方式串联长期事件，可根据素材灵活增删：
1. **日常节奏**：用一句话概括他/她固定的起点或节律（如“他总是先整理 GitHub 通知”），禁止使用“在 XXX 里，他……”的场景化句式。
2. **成长节点**：按时间顺序描述关键事件，突出动机、行为与结果，必要时引用具体工具/作品/地点。
3. **反思与下一步**：总结这些事件对用户意味着什么，点明下一阶段的关注点或愿望。
每个部分以 2-3 段文字展开，避免罗列式语言，多用描写与内心独白。全文禁止以场景化开头，直接点出人物与主线。''';
        }
        return '''
Structure guide: use a "timeline log" tone to connect major moments, adapting as needed.
1. **Daily cadence** – begin with a single sentence that states the recurring starting point (e.g., “He always reviews GitHub notifications first”), never with a cinematic scene such as “In his dorm room…”.
2. **Growth milestones** – describe motivations, actions, and outcomes in chronological order, mentioning specific tools or works when relevant.
3. **Reflection and next steps** – explain what these events mean for the user and what they intend to do next.
Each section should be 2–3 narrative paragraphs; avoid bullet lists and lean on descriptive prose. Never open the article with a scene-setting sentence.''';
      case PersonaArticleStyle.narrative:
        if (code.startsWith('ja')) {
          return '''
構成ガイド：親しい友人にライフストーリーを語るような、温かくも客観的なナラティブでまとめてください。
1. **冒頭は直截に**：ユーザーの核心的な役割・動機を一文で示し、「〜の部屋で彼は…」といった場面描写は禁止。
2. **役割と課題**：ユーザーの肩書き、目標、直面する葛藤を、日々の習慣や嗜好と絡めて説明します。
3. **手段とリソース**：どのようなツールやコミュニティを使い、スキルを活かしているかを描写します。
4. **締めくくり**：内省的な一言、または今後へのメッセージで余韻を残します。
全体を通して穏やかで観察眼のある語り口を保ち、人と行動の結びつきを際立たせてください。記事冒頭で場面描写を行うことは禁じます。''';
        }
        if (code.startsWith('ko')) {
          return '''
작성 가이드: 친한 친구에게 삶의 이야기를 들려주듯, 따뜻하지만 객관적인 서술로 정리하세요.
1. **직접적인 도입** – 첫 문장에서 사용자의 핵심 역할·동기를 명확히 밝히고 “어느 장소에서 그는…” 같은 장면 묘사는 금지합니다.
2. **역할과 갈등** – 사용자의 정체성, 장기적 목표, 현재의 고민을 일상의 습관이나 취향과 함께 설명합니다.
3. **방법과 도구** – 어떤 도구·커뮤니티·역량을 활용해 문제를 해결하는지 자연스럽게 드러냅니다.
4. **여운을 남기는 결말** – 내면의 독백이나 미래에게 보내는 짧은 메시지로 마무리합니다.
전체적으로 차분하고 관찰력이 느껴지는 어조를 유지하며, 사람과 행동의 연결성을 강조하세요. 장면 묘사로 시작하는 문장은 절대로 사용하지 마세요.''';
        }
        if (code.startsWith('zh')) {
          return '''
写作结构：采用“少数派叙事”风格，像给朋友讲述一段生活史，可按素材调整：
1. **开篇直述**：直接交代该用户的核心身份与主要动机，用事实句开场，禁止出现“在 XXX 里，他……”之类的场景描写。
2. **角色与矛盾**：介绍用户的身份、长期目标与正在面对的矛盾，穿插典型习惯或喜好。
3. **方法与工具**：讲述他/她如何配置工具、技能与资源，适当引用产品、社区或作品名。
4. **尾声/寄语**：以内心独白或给未来自己的话收束全文。
保持温暖、富有观察力的语气，强调人与事之间的连接感。全文禁止使用场景化开篇。''';
        }
        return '''
Structure guide: follow a warm narrative voice, as if telling a trusted friend about the user’s life.
1. **Direct opening** – state who the user is and what drives them in the very first sentence; never begin with “In a dorm room…” or other cinematic scenes.
2. **Roles and tensions** – explain the user’s identity, long-term goals, and current frictions, weaving in signature habits or tastes.
3. **Methods and tools** – describe how they deploy tools, communities, or skills to move forward, naming products or platforms when relevant.
4. **Closing reflection** – end with an intimate observation or a short note to their future self.
Maintain a calm, observant tone that highlights the relationship between the user and their actions, and never use a scene-setting introduction.''';
    }
  }

  String _promptTemplate(Locale locale) {
    final String code = locale.languageCode.toLowerCase();
    if (code.startsWith('ja')) {
      return _promptTemplateJa;
    }
    if (code.startsWith('ko')) {
      return _promptTemplateKo;
    }
    if (code.startsWith('zh')) {
      return _promptTemplateZh;
    }
    return _promptTemplateEn;
  }

  static const String _promptTemplateZh = '''
# 角色
你是一位专业的用户研究员。你的任务是基于原始数据，撰写一份客观、清晰、描述性的用户画像报告。

# 任务
分析下方提供的[待处理的原始数据]，并严格模仿[示例]的风格、格式和语言，生成一份全新的用户画像报告。

# 核心指令与风格要求

1.  **客观视角**: 报告必须使用第三方视角（如“该用户”、“他”）。严禁使用第一人称（“我”）或观察者口吻（“我们发现”）。

2.  **文章化段落**: 在每个二级标题下，必须使用完整、连贯的散文段落进行叙述。**严禁使用分点或项目符号列表**。

3.  **结构清晰**: 报告需包含一个简短的**基本情况介绍**，然后使用二级标题（格式为 `### 标题`）来划分不同的主题，根据素材动态命名与排序。

4.  **语言平实直接**: 使用普通、直接、客观的语言进行描述。避免使用过多的比喻、华丽的辞藻或深度的心理分析。重点在于清晰地陈述用户的行为和兴趣。

5.  **信息整合**: 将原始数据中相关的、零散的信息点自然整合，标题与段落的数量和内容都应根据整体信息动态调整，禁止照搬示例结构。
6.  **重点突出**: 对人物身份、关键地点、工具名称等重要信息，使用 Markdown 加粗（`**关键词**`）突出。
7.  **信息完整**: 不要压缩内容，确保每个主题段落都写满 3-4 句，涵盖背景、动机、行为与影响。
8.  **时间中立**: 所有数据来自长时间累积的画像标签，禁止出现“今天/昨天/本周”之类的即时描述，只能在无法避免时以更抽象的长期表述呈现。
9.  **禁止场景化开篇**: 第一段必须直接说明用户身份与主线，严禁使用“在……里，他……”等场景描写作为开头。

请确保使用 {{LANG}}。{{STYLE}}

---

# 示例 (请严格模仿此格式、语言和结构)

### **技术爱好者与数字生活实践者**

**基本情况**

该用户是一名软件工程专业的在校大学生，对前沿技术充满热情，并将其应用于日常学习和生活中。同时，他在数字娱乐和社交方面也表现得十分活跃。

### **对技术的关注与应用**

他在技术领域的兴趣非常明确。除了课堂学习，他还主动了解像 Rust、TypeScript 这样的编程语言和 Vite 这类前端工具。他对人工智能技术有深入的关注，不仅追踪 Sora、Claude AI 等模型的发展，还会实际使用 AI 编程和设计工具来提高效率。他获取技术知识的渠道多样，包括专业论坛（如 LINUX DO）、GitHub 以及 B 站上的科技内容创作者。

### **多元化的娱乐偏好**

在学习和技术探索之外，他的娱乐生活也十分丰富。他会花时间观看从《南方公园》到《我们与恶的距离》这样类型跨度很大的影视剧。游戏是他重要的娱乐方式之一，他尤其喜欢《塞尔达传说》和《空洞骑士》这类设计出色的作品，并通过小黑盒平台获取游戏资讯和优惠。

### **有序的日常生活**

他注重对自己日常生活的管理，例如使用记账应用追踪开销，维持良好的财务习惯。在社交方面，他既与家人、伴侣和同学保持紧密联系，也积极参与线上技术社区的交流，把兴趣与社交结合在一起。

---

# 待处理的原始数据
- **当前画像摘要**：
{{SUMMARY}}

- **结构化画像（Markdown）**：
{{MARKDOWN}}

- **结构化画像（JSON）**：
{{JSON}}

# 开始执行
请严格遵循以上所有指令和示例，开始生成报告。
''';

  static const String _promptTemplateEn = '''
# Role
You are a professional user researcher. Your job is to turn raw data into an objective, descriptive persona report.

# Task
Analyze the [Raw Data] below and, by strictly mimicking the [Example], produce a brand-new persona report.

# Core Guidelines

1.  **Objective voice**: Always use third-person references such as “the user” or “he/she.” Do not write in first person or from an observer’s “we found” perspective.

2.  **Narrative paragraphs**: Under every secondary heading you must write cohesive prose. **Do not use bullet lists or numbered lists.**

3.  **Clear structure**: Provide a short **Basic Profile**, then split the rest of the article with `###` headings tailored to the material. Decide the order and names dynamically based on the data.

4.  **Plain language**: Favor direct, concrete sentences. Avoid elaborate metaphors or deep psychological speculation; simply describe behaviors and interests.

5.  **Contextual integration**: Blend all relevant facts from the raw data into natural paragraphs. Dynamically decide how many headings and paragraphs you need; never copy the sample structure verbatim.
6.  **Emphasize key terms**: Highlight essential identities, locations, tools, or metrics using Markdown bold (`**keyword**`).
7.  **Rich detail**: Do not keep the article short—each section should include at least 3–4 sentences covering context, motivations, behaviors, and outcomes.
8.  **Time-neutral narration**: The inputs are aggregated persona tags collected across many days. Avoid phrases like “today” or “yesterday”; only describe enduring traits or routines.
9.  **No scene-setting openings**: The first paragraph must immediately state who the user is and what drives them; do not begin with sentences like “In his dorm room, he…”.

Make sure the entire article is written in {{LANG}}. {{STYLE}}

---

# Example (imitate the same tone and structure)

### **Tech Enthusiast and Digital Life Practitioner**

**Basic Profile**

This user is a software engineering student who is passionate about emerging technology and applies it to daily study and life. He is equally active in digital entertainment and social spaces.

### **Focus on Technology and Application**

His interest in technology extends well beyond coursework. He experiments with programming languages such as Rust and TypeScript, and keeps Vite in his toolset. He closely follows AI models like Sora and Claude, and uses AI coding and design assistants to boost efficiency. His knowledge sources include Linux DO, GitHub, and tech-focused creators on Bilibili.

### **Diverse Entertainment Preferences**

Outside of study, he invests time in varied entertainment. His watch list ranges from comedic animation like “South Park” to serious dramas such as “The World Between Us.” Games are a key hobby; he favors well-crafted titles like “The Legend of Zelda” and “Hollow Knight,” and relies on XiaoHeiHe for news and deals.

### **Orderly Daily Life**

He manages day-to-day routines with intention, using budgeting apps to monitor expenses and maintain healthy finances. Socially, he stays close to family, partner, and classmates, while also engaging technical communities online so that social life and personal interests reinforce each other.

---

# Raw Data To Analyze
- **Persona summary**:
{{SUMMARY}}

- **Structured persona (Markdown)**:
{{MARKDOWN}}

- **Structured persona (JSON)**:
{{JSON}}

# Begin
Follow every instruction above and generate the report now.
''';

  static const String _promptTemplateJa = '''
# 役割
あなたは専門的なユーザーリサーチャーです。与えられた原始データをもとに、客観的でわかりやすいユーザーレポートを作成してください。

# タスク
以下の[解析対象の原始データ]を読み、[サンプル]と同じスタイル・構成・文体で新しいユーザーレポートを生成してください。

# ルールとスタイル

1.  **客観的な視点**: 「このユーザー」「彼／彼女」といった第三者の語りに徹し、一人称や観察者目線の「我々は〜と気づいた」は使用しない。

2.  **散文での記述**: すべてのセクションを段落で記述し、**箇条書きは禁止**。

3.  **明確な構造**: 冒頭で簡潔な**基本情報**を述べ、その後は `### 見出し` でテーマを分けます。見出し名や順序は素材に合わせて柔軟に決めます。

4.  **平易で直接的な文体**: 大げさな比喩や深すぎる心理分析を避け、行動と興味を淡々と描写する。

5.  **情報の統合**: 原始データの要素を自然に文章へ織り込み、必要な見出し・段落構成は内容に合わせて柔軟に調整する。サンプルをそのまま写さないこと。
6.  **強調表示**: ユーザーの肩書きや重要な場所・ツール名などは Markdown の太字（`**キーワード**`）で強調する。
7.  **十分な分量**: 各セクションは最低 3～4 文で構成し、背景・動機・行動・影響を丁寧に描写する。
8.  **時間表現の抑制**: ここで扱うデータは複数日にわたり蓄積された画像タグなので、「今日〜した」「昨日〜」のような表現は避け、継続的・長期的な特徴として記述する。
9.  **場面描写禁止の冒頭**: 最初の段落ではユーザーの正体と主題を即座に述べ、映画的な情景描写（例：「寮の部屋で彼は…」）で始めないこと。

全体を {{LANG}} で記述し、{{STYLE}}

---

# サンプル（構成と文体を参考にすること）

### **テクノロジーに没頭するデジタル実践者**

**基本情報**

このユーザーはソフトウェア工学を専攻する大学生であり、最先端技術への好奇心を日常の学びと生活に結びつけている。同時にデジタルエンタメやコミュニティ活動にも積極的だ。

### **技術への関心と活用**

授業の枠を超えて Rust や TypeScript のような言語、Vite のような前端ツールを試し、Sora や Claude のような AI モデルの動向も追い続けている。AI コーディング・デザインツールを使い効率を高め、情報源は LINUX DO、GitHub、Bilibili のテック系クリエイターなど多岐にわたる。

### **多彩なエンタメの嗜好**

学習時間外には幅広い映像作品を楽しみ、コメディアニメ『サウスパーク』から社会派ドラマ『私たちと悪との距離』までジャンルに偏りがない。ゲームも重要な趣味で、『ゼルダの伝説』や『Hollow Knight』のような巧みなタイトルを好み、小黒盒で最新情報やセールをチェックしている。

### **整った日常管理**

家計簿アプリを使って支出を可視化するなど、生活管理にも気を配る。家族やパートナー、友人とのつながりを大切にしつつ、オンラインの技術コミュニティにも積極的に参加し、興味と交流を自然に重ねている。

---

# 解析対象の原始データ
- **画像サマリー**：
{{SUMMARY}}

- **構造化画像（Markdown）**：
{{MARKDOWN}}

- **構造化画像（JSON）**：
{{JSON}}

# 開始
上記の指示とサンプルに従い、レポートを生成してください。
''';

  static const String _promptTemplateKo = '''
# 역할
당신은 전문 사용자 리서처입니다. 제공된 원시 데이터를 바탕으로 객관적이고 명료한 사용자 리포트를 작성하세요.

# 작업
아래 [분석 대상 원시 데이터]를 살펴보고, [예시]의 형식과 문체를 엄격히 모방해 새로운 리포트를 만드세요.

# 핵심 지침

1.  **객관적 시점**: “이 사용자는…”, “그는…”과 같은 3인칭을 사용하고 1인칭이나 “우리는 발견했다”와 같은 관찰자 어투는 금지합니다.

2.  **산문형 문단**: 모든 소제목 아래는 연결성 있는 산문으로 작성하며, **불릿이나 번호 목록을 사용하지 않습니다.**

3.  **명확한 구조**: 간단한 **기본 정보**로 시작한 뒤, 내용에 맞춘 `###` 소제목을 사용하며 제목 이름과 순서는 상황에 따라 조정합니다.

4.  **직접적이고 담백한 언어**: 과한 비유나 심리 분석을 피하고 행동과 관심사를 담담하게 기술합니다.

5.  **정보 통합**: 원시 데이터의 여러 단서를 자연스럽게 문단에 녹여내고, 필요한 소제목·문단 수는 내용에 맞춰 유연하게 조정합니다. 예시 구조를 그대로 복붙하지 마세요.
6.  **강조 표현**: 직함, 핵심 장소, 도구명 등 중요한 요소는 Markdown 굵게(`**키워드**`) 표기해 강조하세요.
7.  **충분한 분량**: 각 섹션은 최소 3~4문장으로 구성해 배경·동기·행동·결과를 꼼꼼히 설명하세요.
8.  **시간 중립적 서술**: 이 데이터는 여러 날 동안 축적된 사용자 태그이므로 “오늘 했다”, “어제 했다”와 같은 표현을 피하고, 장기적 패턴이나 반복 습관 중심으로 설명하세요.
9.  **장면 묘사 금지**: 첫 문단은 반드시 사용자 정체와 주제를 직접 언급해야 하며 “어느 장소에서 그는…”과 같은 장면 묘사로 시작하면 안 됩니다.

모든 문장은 {{LANG}} 로 작성하고, {{STYLE}}

---

# 예시 (구조와 톤을 참고)

### **기술 애호가이자 디지털 실천가**

**기본 정보**

이 사용자는 소프트웨어 공학을 전공하는 대학생으로, 최신 기술에 대한 호기심을 일상 학습과 삶에 적극 반영한다. 동시에 디지털 엔터테인먼트와 온라인 커뮤니티에도 활발히 참여한다.

### **기술에 대한 관심과 활용**

수업 외 시간에도 Rust, TypeScript 같은 언어와 Vite 같은 프론트엔드 도구를 실험하며, Sora·Claude 같은 AI 모델의 발전을 꾸준히 추적한다. AI 코딩·디자인 도구를 적극 사용해 효율을 높이고, LINUX DO, GitHub, 빌리빌리의 테크 창작자 등 다양한 채널에서 정보를 얻는다.

### **다채로운 여가 취향**

학업을 제외한 시간에는 폭넓은 영상 콘텐츠를 시청한다. 코미디 애니메이션 ‘사우스 파크’부터 사회파 드라마 ‘우리와 악의 거리’까지 장르 편식이 없다. 게임 역시 중요한 취미로, ‘젤다의 전설’과 ‘Hollow Knight’ 같은 완성도 높은 작품을 즐기며, 소흑박스를 통해 최신 소식과 할인 정보를 챙긴다.

### **체계적인 일상 관리**

가계부 앱으로 지출을 기록해 재정을 관리하고, 가족·파트너·동료와의 관계를 성실히 유지한다. 동시에 온라인 기술 커뮤니티에서 활발히 소통하며, 관심사와 사회적 연결망을 하나로 엮는다.

---

# 분석 대상 원시 데이터
- **요약 텍스트**:
{{SUMMARY}}

- **구조화된 프로필 (Markdown)**:
{{MARKDOWN}}

- **구조화된 프로필 (JSON)**:
{{JSON}}

# 시작
위의 모든 지침을 따르면서 리포트를 작성하세요.
''';
}
