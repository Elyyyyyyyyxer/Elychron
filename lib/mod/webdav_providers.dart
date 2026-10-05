/// ===== 预设的 WebDAV 服务商（W3）=====
///
/// 用户要求：「我想要尽可能简化用户操作流程」。
///
/// WebDAV 接入最劝退的两步是：**记地址** 和 **搞懂"要用应用密码"**。
/// 这张表把第一步消掉（点一下地址就填好），并给出第二步的**直达链接**与说明。
///
/// ⚠️ 表里的地址与"应用密码在哪"都是 2026-09-28 核对过的；
/// 各家页面结构会变，所以 [passwordHint] 写成"去哪找"的路径而不是死链接为主。
class WebDavProvider {
  /// 展示名
  final String name;

  /// 服务商根地址（用户不用记，点一下自动填）
  final String url;

  /// 用户名该填什么（多数是注册邮箱）。
  ///
  /// ⚠️ 这句话显示在**输入框下面的说明文字**里（不是占位符），所以：
  /// - 写成一整句能独立看懂的话；
  /// - **不要用 markdown 的星号加粗** —— 界面不渲染它，会原样冒出来。
  ///   （真机截图里就是这么发现占位符中冒出一对 ** 的）
  final String usernameHint;

  /// 应用密码怎么拿（给人看的一句话）。同样：不用 markdown 语法。
  final String passwordHint;

  /// 拿应用密码的入口（有就做成按钮直接跳；没有则留空）
  ///
  /// 2026-10-01 更正：坚果云**网页版已经不能生成应用密码了**（用户提醒），
  /// 只能在客户端里「第三方应用管理」生成 —— 所以坚果云那条指向的是下载页，
  /// 不是一个会让人白跑一趟的网页设置页。
  final String passwordPageUrl;

  /// 这个服务商的名字是不是邮箱（坚果云/InfiniCloud 都是邮箱登录）
  final bool usernameIsEmail;

  /// 用户名要不要**边打边转小写**。
  ///
  /// 2026-09-28 真账号实测：坚果云的用户名大写 → 401，小写 → 207。
  /// 用户从网页复制邮箱时首字母常常是大写，于是"密码明明对却怎么都连不上"。
  /// 与其事后解释，不如在输入框里直接转掉。
  /// 默认 false —— Nextcloud 那类自建服务的用户名是大小写敏感的，不能乱改。
  final bool lowercaseUsername;

  const WebDavProvider({
    required this.name,
    required this.url,
    required this.usernameHint,
    required this.passwordHint,
    this.passwordPageUrl = '',
    this.usernameIsEmail = true,
    this.lowercaseUsername = false,
  });

  /// 内置预设（顺序 = 界面上的顺序，把国内最顺的放最前）
  static const List<WebDavProvider> presets = <WebDavProvider>[
    WebDavProvider(
      name: '坚果云',
      url: 'https://dav.jianguoyun.com/dav/',
      usernameHint: '用户名就是坚果云的注册邮箱，必须全小写（大写会连不上）',
      passwordHint: '要装坚果云客户端（手机或电脑）才能拿：设置 → 安全选项 → '
          '第三方应用管理 → 添加应用密码。网页版已经不给生成了。',
      passwordPageUrl: 'https://www.jianguoyun.com/s/downloads',
      lowercaseUsername: true,
    ),
    WebDavProvider(
      name: 'InfiniCloud',
      url: 'https://客户端专用域名/',
      usernameHint: '用户名就是 InfiniCloud 的注册邮箱',
      passwordHint: '网页版 → 设置 → 应用密码（需要先开启 WebDAV/连接功能）',
    ),
    WebDavProvider(
      name: 'Koofr',
      url: 'https://app.koofr.net/dav/Koofr/',
      usernameHint: '用户名就是 Koofr 的注册邮箱',
      passwordHint: '网页版 → Preferences → App passwords',
    ),
    WebDavProvider(
      name: 'Nextcloud',
      url: 'https://你的域名/remote.php/dav/files/用户名/',
      usernameHint: '用户名是 Nextcloud 的登录名，它是大小写敏感的',
      passwordHint: '个人设置 → 安全 → 创建新的应用密码',
      usernameIsEmail: false,
    ),
    WebDavProvider(
      name: '群晖 / 威联通 NAS',
      url: 'http://你的内网地址:5005/',
      usernameHint: '填 NAS 上那个账号的名字',
      passwordHint: '套件中心装 WebDAV Server → 在 NAS 用户里给这个账号开 WebDAV 权限',
      usernameIsEmail: false,
    ),
    WebDavProvider(
      name: 'Alist / 自建',
      url: 'http://你的地址:5244/dav/',
      usernameHint: '填 Alist 后台里显示的账号',
      passwordHint: 'Alist 后台 → 设置 → 添加存储后，用「WebDAV 策略」里显示的用户名密码',
      usernameIsEmail: false,
    ),
  ];

  /// 认不认得这个地址是哪家（用户已经填过地址时，界面能显示"坚果云"而不是一串 URL）
  static WebDavProvider? match(String url) {
    final text = url.trim().toLowerCase();
    if (text.isEmpty) return null;
    for (final provider in presets) {
      final host = Uri.tryParse(provider.url)?.host ?? '';
      if (host.isNotEmpty && text.contains(host)) return provider;
    }
    return null;
  }
}
