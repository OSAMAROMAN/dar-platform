part of 'main.dart';

// ====================================================================
//  المنصة: تسجيل الدخول الموحّد + بوابة الاشتراك + تغيير كلمة المرور
// ====================================================================

class PlatformLogin extends StatefulWidget {
  const PlatformLogin({super.key});
  @override
  State<PlatformLogin> createState() => _PlatformLoginState();
}

class _PlatformLoginState extends State<PlatformLogin> {
  final id = TextEditingController();
  final pw = TextEditingController();
  bool hide = true, busy = false;
  int taps = 0, fails = 0;
  DateTime? lockUntil;

  Future<void> _go() async {
    final lu = lockUntil;
    if (lu != null && DateTime.now().isBefore(lu)) {
      return toast(context, 'محاولات كثيرة. انتظر ${lu.difference(DateTime.now()).inSeconds + 1} ثانية');
    }
    if (id.text.trim().isEmpty || pw.text.isEmpty) return toast(context, 'أدخل اسم الدخول وكلمة المرور');
    setState(() => busy = true);
    final e = await cloud.login(id.text, pw.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (e != null) {
      fails++;
      if (fails >= 5) lockUntil = DateTime.now().add(Duration(seconds: 30 * (fails - 4)));
      toast(context, e);
    }
  }

  Future<void> _forgot() async {
    final c = TextEditingController(text: id.text.contains('@') ? id.text.trim() : '');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('استرجاع كلمة المرور'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('أدخل البريد الإلكتروني المسجّل لحسابك فيصلك رابط لتعيين كلمة مرور جديدة.\nإن كان دخولك باسم مستخدم بدون بريد فتواصل مع مزوّد الخدمة ليعيد تعيينه.',
              style: TextStyle(fontSize: 12, color: C.muted, height: 1.6)),
          const SizedBox(height: 10),
          TextField(controller: c, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    if (!c.text.contains('@') || c.text.trim().endsWith('@dar.app')) return toast(context, 'هذا الحساب بلا بريد استرجاع، تواصل مع مزوّد الخدمة');
    final e = await cloud.sendReset(c.text);
    if (mounted) toast(context, e ?? 'تم إرسال رابط الاسترجاع إلى بريدك ✓');
  }

  Future<void> _bootstrap() async {
    final em = TextEditingController();
    final p = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('إنشاء مدير المنصة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('يعمل مرة واحدة فقط لأول مدير. استخدم بريداً حقيقياً وكلمة مرور قوية.', style: TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 10),
          TextField(controller: em, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد')),
          const SizedBox(height: 10),
          TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور (8 فأكثر)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final e = await cloud.bootstrapSuper(em.text, p.text);
    if (mounted && e != null) toast(context, e);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: C.brandGradient),
        child: Stack(children: [
          Positioned(top: -80, left: -60, child: Container(width: 240, height: 240, decoration: BoxDecoration(shape: BoxShape.circle, color: C.gold.withOpacity(.08)))),
          Positioned(bottom: -90, right: -70, child: Container(width: 280, height: 280, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(.05)))),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 430),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 60, offset: Offset(0, 24))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    onTap: () {
                      if (kAdminBuild && ++taps >= 7) {
                        taps = 0;
                        _bootstrap();
                      }
                    },
                    child: const Avatar(null, size: 96, fallback: Icons.home_rounded),
                  ),
                  const SizedBox(height: 14),
                  Text(kBrandName, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: C.g)),
                  Text(kAdminBuild ? 'لوحة إدارة المنصة' : 'سجّل الدخول بحسابك', style: const TextStyle(color: C.muted, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 22),
                  TextField(
                    controller: id,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'اسم الدخول أو البريد', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pw,
                    obscureText: hide,
                    onSubmitted: (_) => _go(),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => hide = !hide)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  LuxButton(busy ? 'جاري الدخول...' : 'تسجيل الدخول', Icons.login_rounded, busy ? null : _go),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _forgot, child: const Text('نسيت كلمة المرور؟')),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------------- بوابة الاشتراك ----------------

class TenantGate extends StatefulWidget {
  final Widget child;
  const TenantGate({super.key, required this.child});
  @override
  State<TenantGate> createState() => _TenantGateState();
}

class _TenantGateState extends State<TenantGate> {
  Timer? timer;
  bool tried = false, loading = false;

  @override
  void initState() {
    super.initState();
    _check();
    timer = Timer.periodic(const Duration(minutes: 20), (_) => _check());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (loading) return;
    setState(() => loading = true);
    await cloud.loadTenant();
    if (!mounted) return;
    context.read<AppStore>().applyTenant(cloud.tenant);
    setState(() {
      loading = false;
      tried = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        final st = cloud.lockState;
        if (st == 'unverified' && !tried) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (st == 'unverified' || st == 'locked' || st == 'suspended' || st == 'offline') {
          return LockedScreen(state: st, busy: loading, onRetry: _check);
        }
        final left = cloud.daysLeft;
        String? banner;
        var urgent = false;
        if (st == 'grace') {
          banner = 'انتهى اشتراكك. ستتوقف الخدمة قريباً، جدّد الآن للاستمرار.';
          urgent = true;
        } else if (left != null && left <= 7) {
          banner = 'ينتهي اشتراكك بعد ${left <= 0 ? 'أقل من يوم' : '$left يوم'}. تواصل مع ${cloud.support['phone'] ?? 'مزوّد الخدمة'} للتجديد.';
        }
        if (banner == null) return widget.child;
        return Column(children: [
          Material(
            color: urgent ? C.red : C.orange,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(banner, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ),
          ),
          Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child)),
        ]);
      },
    );
  }
}

class LockedScreen extends StatelessWidget {
  final String state;
  final bool busy;
  final VoidCallback onRetry;
  const LockedScreen({super.key, required this.state, required this.busy, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final sup = cloud.support;
    final phone = '${sup['phone'] ?? ''}';
    final (icon, title, body) = switch (state) {
      'locked' => (Icons.lock_clock_rounded, 'انتهى الاشتراك', 'انتهت مدة اشتراكك ومهلة السماح. جدّد اشتراكك لاستعادة الوصول، وبياناتك محفوظة وستعود كما هي.'),
      'suspended' => (Icons.pause_circle_rounded, 'تم تعليق الحساب', 'تم تعليق حسابك مؤقتاً. تواصل مع مزوّد الخدمة لمعرفة السبب وإعادة التفعيل.'),
      'offline' => (Icons.wifi_off_rounded, 'يلزم الاتصال بالإنترنت', 'مرّت أيام بدون التحقق من اشتراكك. اتصل بالإنترنت ثم اضغط إعادة المحاولة.'),
      _ => (Icons.cloud_off_rounded, 'تعذّر التحقق من الاشتراك', 'تأكد من اتصالك بالإنترنت ثم أعد المحاولة.'),
    };
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: C.brandGradient),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 430),
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 64, color: C.orange),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: C.g)),
                const SizedBox(height: 8),
                Text(body, textAlign: TextAlign.center, style: const TextStyle(color: C.muted, height: 1.7, fontSize: 13)),
                if (cloud.expiresAt != null && (state == 'locked')) Padding(padding: const EdgeInsets.only(top: 8), child: Text('انتهى في: ${dayKey(cloud.expiresAt!)}', style: const TextStyle(fontWeight: FontWeight.w800))),
                const SizedBox(height: 18),
                LuxButton(busy ? 'جاري التحقق...' : 'إعادة المحاولة', Icons.refresh_rounded, busy ? null : onRetry),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => callPhone(context, phone), icon: const Icon(Icons.call_rounded), label: const Text('اتصال'))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => sendWa(context, phone, 'مرحباً، أرغب بتجديد اشتراكي في $kBrandName (${cloud.tenant?['name'] ?? ''})'),
                        icon: const Icon(Icons.chat_rounded, color: C.wa),
                        label: const Text('واتساب'),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 8),
                TextButton(onPressed: () => cloud.logout(), child: const Text('تسجيل الخروج', style: TextStyle(color: C.red))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- تغيير كلمة المرور ----------------

class ChangePwSheet extends StatefulWidget {
  const ChangePwSheet({super.key});
  @override
  State<ChangePwSheet> createState() => _ChangePwSheetState();
}

class _ChangePwSheetState extends State<ChangePwSheet> {
  final old = TextEditingController();
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  bool busy = false;
  String? err;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('تغيير كلمة المرور', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: C.g)),
      const SizedBox(height: 6),
      const Text('8 أحرف على الأقل، تحتوي حروفاً وأرقاماً، ولا تتضمن اسم دخولك.', style: TextStyle(color: C.muted, fontSize: 12)),
      const SizedBox(height: 12),
      inp('كلمة المرور الحالية', old, obscure: true),
      inp('كلمة المرور الجديدة', p1, obscure: true),
      inp('تأكيد كلمة المرور الجديدة', p2, obscure: true),
      if (err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(err!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w800, fontSize: 12))),
      LuxButton(busy ? 'جاري الحفظ...' : 'حفظ', Icons.save_rounded, busy
          ? null
          : () async {
              if (p1.text != p2.text) return setState(() => err = 'كلمتا المرور غير متطابقتين');
              setState(() {
                busy = true;
                err = null;
              });
              final e = await cloud.changePassword(old.text, p1.text);
              if (!mounted) return;
              if (e != null) {
                setState(() {
                  busy = false;
                  err = e;
                });
                return;
              }
              Navigator.pop(context);
              toast(context, 'تم تغيير كلمة المرور ✓');
            }),
      const SizedBox(height: 8),
    ]);
  }
}
