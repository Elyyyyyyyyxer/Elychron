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

  /// 用户名该填什么（多数是注册邮箱）
  final String usernameHint;

  /// 应用密码怎么拿（给人看的一句话）
  final String passwordHint;

  /// 生成应用密码的页面（有就做成按钮直接跳；没有则留空）
  final String passwordPageUrl;

  /// 这个服务商的名字是不是邮箱（坚果云/InfiniCloud 都是邮箱登录）
  final bool usernameIsEmail;

  const WebDavProvider({
    required this.name,
    required this.url,
    required this.usernameHint,
    required this.passwordHint,
    this.passwordPageUrl = '',
    this.usernameIsEmail = true,
  });

  /// 内置预设（顺序 = 界面上的顺序，把国内最顺的放最前）
  static const List<WebDavProvider> presets = <WebDavProvider>[
    WebDavProvider(
      name: '坚果云',
      url: 'https://dav.jianguoyun.com/dav/',
      usernameHint: '坚果云的注册邮箱（**必须全小写**，大写会连不上）',
      passwordHint: '网页版 → 右上角账户信息 → 安全选项 → 添加应用密码',
      passwordPageUrl: 'https://www.jianguoyun.com/dash/security',
    ),
    WebDavProvider(
      name: 'InfiniCloud',
      url: 'https://客户端专用域名/',
      usernameHint: 'InfiniCloud 的注册邮箱',
      passwordHint: '网页版 → 设置 → 应用密码（需要先开启 WebDAV/连接功能）',
    ),
    WebDavProvider(
      name: 'Koofr',
      url: 'https://app.koofr.net/dav/Koofr/',
      usernameHint: 'Koofr 的注册邮箱',
      passwordHint: '网页版 → Preferences → App passwords',
    ),
    WebDavProvider(
      name: 'Nextcloud',
      url: 'https://你的域名/remote.php/dav/files/用户名/',
      usernameHint: 'Nextcloud 的用户名（**大小写敏感**）',
      passwordHint: '个人设置 → 安全 → 创建新的应用密码',
      usernameIsEmail: false,
    ),
    WebDavProvider(
      name: '群晖 / 威联通 NAS',
      url: 'http://你的内网地址:5005/',
      usernameHint: 'NAS 的账号',
      passwordHint: '套件中心装 WebDAV Server → 在 NAS 用户里给这个账号开 WebDAV 权限',
      usernameIsEmail: false,
    ),
    WebDavProvider(
      name: 'Alist / 自建',
      url: 'http://你的地址:5244/dav/',
      usernameHint: 'Alist 的账号',
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
