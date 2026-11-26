part of 'main.dart';

// ====================================================================
//  لوحة مدير المنصة: العملاء والباقات والاشتراكات
// ====================================================================

DateTime addMonths(DateTime d, int m) {
  final y = d.year + ((d.month - 1 + m) ~/ 12);
  final mo = (d.month - 1 + m) % 12 + 1;
  final dim = DateTime(y, mo + 1, 0).day;
  return DateTime(y, mo, min(d.day, dim), d.hour, d.minute);
}

String _rnd(int n, {String chars = 'abcdefghjkmnpqrstuvwxyz23456789'}) {
  final r = Random.secure();
  return String.fromCharCodes(List.generate(n, (_) => chars.codeUnitAt(r.nextInt(chars.length))));
}

String genPassword(String login) {
  for (var i = 0; i < 30; i++) {
    final p = _rnd(8, chars: 'abcdefghjkmnpqrstuvwxyz') + _rnd(3, chars: '23456789');
    if (passwordProblem(p, login) == null) return p;
  }
  return '${_rnd(8)}7${_rnd(2)}';
}

Color? parseHex(String t) {
  var h = t.trim().replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return (h.length == 8 && v != null) ? Color(v) : null;
}

const _presets = <(String, String, String)>[
  ('أخضر', '1B4D3E', 'D4AF37'),
  ('أزرق', '1E3A8A', 'F59E0B'),
  ('أحمر', '9B1C1C', 'F59E0B'),
  ('بنفسجي', '5B21B6', 'FBBF24'),
  ('برتقالي', 'C2410C', '0EA5E9'),
  ('أسود', '111827', 'D4AF37'),
  ('تركواز', '0F766E', 'F97316'),
];

String tenantState(Map<String, dynamic> t) {
  if ('${t['status']}' != 'active') return 'suspended';
  final now = DateTime.now().millisecondsSinceEpoch;
  final lock = (t['lockAt'] as num?)?.toInt() ?? 0;
  final exp = (t['expiresAt'] as num?)?.toInt() ?? 0;
  if (lock > 0 && now > lock) return 'locked';
  if (exp > 0 && now > exp) return 'grace';
  return 'ok';
}

(String, Color) tenantStateLabel(String s) => switch (s) {
      'ok' => ('نشط', C.g2),
      'grace' => ('مهلة سماح', C.orange),
      'locked' => ('منتهٍ', C.red),
      _ => ('موقوف', C.muted),
    };

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int tab = 0;
  bool loading = true, failed = false;
  Map<String, dynamic> tenants = {}, plans = {}, info = {}, adminDocs = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final t = await cloud.adminGet('tenants');
    final p = await cloud.adminGet('plans');
    final i = await cloud.adminGet('platform/info');
    final ad = await cloud.adminGet('tenantsAdmin');
    if (!mounted) return;
    setState(() {
      loading = false;
      failed = t == null;
      if (t != null) tenants = t;
      if (p != null) plans = p;
      if (i != null) info = i;
      if (ad != null) adminDocs = ad;
    });
  }

  List<MapEntry<String, Map<String, dynamic>>> get list {
    final l = [for (final e in tenants.entries) if (e.value is Map) MapEntry(e.key, Map<String, dynamic>.from(e.value as Map))];
    l.sort((a, b) => ((a.value['expiresAt'] as num?) ?? 0).compareTo((b.value['expiresAt'] as num?) ?? 0));
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['العملاء', 'الباقات', 'المنصة'];
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: C.brandGradient)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('$kBrandName — الإدارة', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          Text(titles[tab], style: const TextStyle(fontSize: 10, color: C.gold, fontWeight: FontWeight.w700)),
        ]),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : failed
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Empty('تعذّر تحميل البيانات. تحقق من الاتصال وقواعد قاعدة البيانات.', icon: Icons.cloud_off_rounded),
                  FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                ]))
              : switch (tab) { 0 => _tenantsTab(), 1 => _plansTab(), _ => _platformTab() },
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              backgroundColor: C.gold,
              foregroundColor: C.dark,
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('عميل جديد', style: TextStyle(fontWeight: FontWeight.w900)),
              onPressed: () async {
                final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => NewTenantPage(plans: plans, info: info)));
                if (ok == true) _load();
              },
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: 'العملاء'),
          NavigationDestination(icon: Icon(Icons.workspace_premium_outlined), selectedIcon: Icon(Icons.workspace_premium_rounded), label: 'الباقات'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'المنصة'),
        ],
      ),
    );
  }

  Widget _tenantsTab() {
    final l = list;
    final now = DateTime.now();
    var active = 0, soon = 0, dead = 0;
    var revenue = 0.0;
    for (final e in l) {
      final st = tenantState(e.value);
      if (st == 'ok') {
        active++;
        final ex = (e.value['expiresAt'] as num?)?.toInt() ?? 0;
        if (ex > 0 && ex - now.millisecondsSinceEpoch < 7 * 86400000) soon++;
      } else {
        dead++;
      }
      for (final p in asMapList((adminDocs[e.key] as Map?)?['payments'])) {
        final at = DateTime.tryParse('${p['at']}');
        if (at != null && at.year == now.year && at.month == now.month) revenue += _d(p['amount']);
      }
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 100), children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.9,
          children: [
            StatTile('عملاء نشطون', '$active', Icons.verified_rounded, C.g2),
            StatTile('ينتهون خلال 7 أيام', '$soon', Icons.hourglass_bottom_rounded, C.orange),
            StatTile('منتهون/موقوفون', '$dead', Icons.block_rounded, C.red),
            StatTile('إيراد هذا الشهر', qtyText(revenue), Icons.payments_rounded, C.gold),
          ],
        ),
        const SizedBox(height: 14),
        if (l.isEmpty) const Empty('لا يوجد عملاء بعد. اضغط "عميل جديد".', icon: Icons.storefront_outlined),
        for (final e in l) _tenantCard(e.key, e.value),
      ]),
    );
  }

  Widget _tenantCard(String tid, Map<String, dynamic> t) {
    final st = tenantState(t);
    final (label, col) = tenantStateLabel(st);
    final ex = (t['expiresAt'] as num?)?.toInt();
    final left = ex == null ? null : ((ex - DateTime.now().millisecondsSinceEpoch) / 86400000).ceil();
    final brand = Map<String, dynamic>.from((t['brand'] as Map?) ?? {});
    return LuxCard(
      accent: col,
      onTap: () async {
        final ch = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => TenantPage(tid: tid, plans: plans, info: info)));
        if (ch == true) _load();
      },
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: parseHex('${brand['primary'] ?? '1B4D3E'}') ?? C.g, borderRadius: BorderRadius.circular(12)),
          child: Center(child: Container(width: 14, height: 14, decoration: BoxDecoration(color: parseHex('${brand['secondary'] ?? 'D4AF37'}') ?? C.gold, shape: BoxShape.circle))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t['name'] ?? tid}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            Text('${t['ownerName'] ?? ''} • ${t['plan']?['name'] ?? 'بدون باقة'}', style: const TextStyle(color: C.muted, fontSize: 11.5)),
            if (ex != null) Text('ينتهي ${dayKey(DateTime.fromMillisecondsSinceEpoch(ex))}${left == null ? '' : left >= 0 ? ' (بعد $left يوم)' : ' (منذ ${-left} يوم)'}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: (left ?? 99) <= 7 ? C.orange : C.muted)),
          ]),
        ),
        Badge2(label, col),
      ]),
    );
  }

  Widget _plansTab() {
    final l = [for (final e in plans.entries) if (e.value is Map) MapEntry(e.key, Map<String, dynamic>.from(e.value as Map))];
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 100), children: [
      PageHead('الباقات', trailing: FilledButton.icon(onPressed: () => _editPlan(null, null), icon: const Icon(Icons.add), label: const Text('باقة'))),
      if (l.isEmpty) ...[
        const Empty('لا توجد باقات بعد', icon: Icons.workspace_premium_outlined),
        LuxButton('إنشاء الباقات الافتراضية', Icons.auto_awesome_rounded, () async {
          final defs = {
            'basic': {'id': 'basic', 'name': 'الأساسية', 'price': 0, 'maxCaptains': 1, 'maxItems': 60, 'web': false, 'captainApp': false},
            'pro': {'id': 'pro', 'name': 'المتقدمة', 'price': 0, 'maxCaptains': 5, 'maxItems': 300, 'web': true, 'captainApp': true},
            'full': {'id': 'full', 'name': 'الكاملة', 'price': 0, 'maxCaptains': 0, 'maxItems': 0, 'web': true, 'captainApp': true},
          };
          final ok = await cloud.adminPut('plans', defs);
          if (mounted) toast(context, ok ? 'تم إنشاء الباقات، عدّل الأسعار من هنا' : 'تعذّر الإنشاء');
          _load();
        }),
      ],
      for (final e in l)
        LuxCard(
          accent: C.gold,
          onTap: () => _editPlan(e.key, e.value),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e.value['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                Text('السعر الشهري: ${qtyText(_d(e.value['price']))}', style: const TextStyle(color: C.g2, fontWeight: FontWeight.w800, fontSize: 12)),
                Text(
                    'كباتن: ${(e.value['maxCaptains'] ?? 0) == 0 ? 'غير محدود' : e.value['maxCaptains']} • أصناف: ${(e.value['maxItems'] ?? 0) == 0 ? 'غير محدود' : e.value['maxItems']}\n'
                    '${e.value['web'] == true ? '✓' : '✗'} قائمة إلكترونية   ${e.value['captainApp'] == true ? '✓' : '✗'} تطبيق الكابتن',
                    style: const TextStyle(color: C.muted, fontSize: 11.5, height: 1.6)),
              ]),
            ),
            const Icon(Icons.edit_outlined, size: 18, color: C.muted),
          ]),
        ),
      const SizedBox(height: 6),
      const Text('تعديل باقة لا يغيّر العملاء الحاليين؛ لتطبيقها على عميل غيّر باقته من صفحته.', style: TextStyle(color: C.muted, fontSize: 11.5)),
    ]);
  }

  void _editPlan(String? id, Map<String, dynamic>? p) async {
    await showSheet(context, (_) => _PlanSheet(id: id, plan: p));
    _load();
  }

  Widget _platformTab() {
    final phone = TextEditingController(text: '${info['phone'] ?? ''}');
    final nm = TextEditingController(text: '${info['name'] ?? ''}');
    final grace = TextEditingController(text: '${info['graceDays'] ?? 5}');
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 100), children: [
      const PageHead('بيانات الدعم'),
      LuxCard(
        child: Column(children: [
          const Text('تظهر لعملائك عند انتهاء الاشتراك وللتجديد.', style: TextStyle(color: C.muted, fontSize: 12)),
          const SizedBox(height: 8),
          inp('اسمك / اسم شركتك', nm),
          inp('رقم الدعم والتجديد (مع رمز الدولة)', phone, type: TextInputType.phone),
          inp('مهلة السماح بعد الانتهاء (أيام)', grace, type: TextInputType.number),
          LuxButton('حفظ', Icons.save_rounded, () async {
            final g = int.tryParse(grace.text.trim()) ?? 5;
            final ok = await cloud.adminPut('platform/info', {'name': nm.text.trim(), 'phone': phone.text.trim(), 'graceDays': g.clamp(0, 60)});
            if (mounted) toast(context, ok ? 'تم الحفظ' : 'تعذّر الحفظ');
            _load();
          }),
        ]),
      ),
      const PageHead('حسابي'),
      LuxCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(cloud.email ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: () => showSheet(context, (_) => const ChangePwSheet()), icon: const Icon(Icons.lock_reset_rounded), label: const Text('تغيير كلمة المرور')),
          TextButton.icon(
            onPressed: () async {
              if (await confirmDialog(context, 'تسجيل الخروج؟', yes: 'خروج')) await cloud.logout();
            },
            icon: const Icon(Icons.logout_rounded, color: C.red),
            label: const Text('تسجيل الخروج', style: TextStyle(color: C.red)),
          ),
        ]),
      ),
    ]);
  }
}

class _PlanSheet extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? plan;
  const _PlanSheet({this.id, this.plan});
  @override
  State<_PlanSheet> createState() => _PlanSheetState();
}

class _PlanSheetState extends State<_PlanSheet> {
  late final name = TextEditingController(text: '${widget.plan?['name'] ?? ''}');
  late final price = TextEditingController(text: widget.plan == null ? '' : qtyText(_d(widget.plan!['price'])).replaceAll(',', ''));
  late final caps = TextEditingController(text: '${widget.plan?['maxCaptains'] ?? 1}');
  late final items = TextEditingController(text: '${widget.plan?['maxItems'] ?? 100}');
  late bool web = widget.plan?['web'] == true;
  late bool capApp = widget.plan?['captainApp'] == true;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.plan == null ? 'باقة جديدة' : 'تعديل الباقة', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: C.g)),
      const SizedBox(height: 12),
      inp('اسم الباقة', name),
      inp('السعر الشهري', price, type: numType),
      Row(children: [
        Expanded(child: inp('أقصى كباتن (0 = بلا حد)', caps, type: TextInputType.number)),
        const SizedBox(width: 10),
        Expanded(child: inp('أقصى أصناف (0 = بلا حد)', items, type: TextInputType.number)),
      ]),
      SwitchListTile(contentPadding: EdgeInsets.zero, activeColor: C.g2, title: const Text('القائمة الإلكترونية للعملاء'), value: web, onChanged: (v) => setState(() => web = v)),
      SwitchListTile(contentPadding: EdgeInsets.zero, activeColor: C.g2, title: const Text('تطبيق الكابتن'), value: capApp, onChanged: (v) => setState(() => capApp = v)),
      const SizedBox(height: 6),
      LuxButton('حفظ', Icons.save_rounded, () async {
        if (name.text.trim().isEmpty) return toast(context, 'اكتب اسم الباقة');
        final id = widget.id ?? 'p${_rnd(5)}';
        final ok = await cloud.adminPut('plans/$id', {
          'id': id,
          'name': name.text.trim(),
          'price': num2(price.text),
          'maxCaptains': int.tryParse(caps.text.trim()) ?? 0,
          'maxItems': int.tryParse(items.text.trim()) ?? 0,
          'web': web,
          'captainApp': capApp,
        });
        if (!context.mounted) return;
        Navigator.pop(context);
        toast(context, ok ? 'تم حفظ الباقة' : 'تعذّر الحفظ');
      }),
      if (widget.id != null) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () async {
            if (!await confirmDialog(context, 'حذف هذه الباقة؟ (العملاء الحاليون تبقى باقتهم)', yes: 'حذف')) return;
            await cloud.adminDelete('plans/${widget.id}');
            if (context.mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.delete_outline_rounded, color: C.red),
          label: const Text('حذف الباقة', style: TextStyle(color: C.red)),
        ),
      ],
      const SizedBox(height: 8),
    ]);
  }
}

// ---------------- عميل جديد ----------------

class NewTenantPage extends StatefulWidget {
  final Map<String, dynamic> plans, info;
  const NewTenantPage({super.key, required this.plans, required this.info});
  @override
  State<NewTenantPage> createState() => _NewTenantPageState();
}

class _NewTenantPageState extends State<NewTenantPage> {
  final form = GlobalKey<FormState>();
  final biz = TextEditingController();
  final owner = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final login = TextEditingController(text: 'shop${_rnd(4)}');
  final pw = TextEditingController();
  final c1 = TextEditingController(text: '1B4D3E');
  final c2 = TextEditingController(text: 'D4AF37');
  final notes = TextEditingController();
  String? planId;
  int months = 1;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    pw.text = genPassword(login.text);
    if (widget.plans.isNotEmpty) planId = widget.plans.keys.first;
  }

  Future<void> _create() async {
    if (!form.currentState!.validate()) return;
    if (planId == null) return toast(context, 'أنشئ باقة أولاً من تبويب الباقات');
    final id = email.text.trim().isNotEmpty ? email.text.trim().toLowerCase() : login.text.trim().toLowerCase();
    if (!id.contains('@') && !RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch(id)) return toast(context, 'اسم الدخول: حروف إنجليزية صغيرة وأرقام فقط (3 أحرف فأكثر)');
    final pe = passwordProblem(pw.text, id);
    if (pe != null) return toast(context, pe);
    if (parseHex(c1.text) == null || parseHex(c2.text) == null) return toast(context, 'لون غير صالح (مثال: 1B4D3E)');
    setState(() => busy = true);
    final (err, uid) = await cloud.createAccount(id, pw.text);
    if (err != null || uid == null) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, err ?? 'تعذّر إنشاء الحساب');
      }
      return;
    }
    final tid = 'd${_rnd(6)}';
    final plan = Map<String, dynamic>.from(widget.plans[planId] as Map);
    final grace = (widget.info['graceDays'] as num?)?.toInt() ?? 5;
    final exp = addMonths(DateTime.now(), months);
    final tenant = {
      'name': biz.text.trim(),
      'ownerName': owner.text.trim(),
      'phone': phone.text.trim(),
      'status': 'active',
      'createdAt': DateTime.now().toIso8601String(),
      'expiresAt': exp.millisecondsSinceEpoch,
      'lockAt': exp.add(Duration(days: grace)).millisecondsSinceEpoch,
      'graceDays': grace,
      'plan': plan,
      'brand': {'primary': c1.text.trim().replaceAll('#', '').toUpperCase(), 'secondary': c2.text.trim().replaceAll('#', '').toUpperCase()},
      'support': {'phone': '${widget.info['phone'] ?? ''}', 'name': '${widget.info['name'] ?? ''}'},
    };
    final a = await cloud.adminPut('tenants/$tid', tenant);
    final b = await cloud.adminPut('users/$uid', {'role': 'owner', 'tid': tid, 'name': owner.text.trim(), 'login': id, 'mustChange': true});
    final c = await cloud.adminPut('tenantsAdmin/$tid', {'notes': notes.text.trim(), 'ownerUid': uid, 'login': id});
    if (!mounted) return;
    setState(() => busy = false);
    if (!a || !b || !c) return toast(context, 'تم إنشاء الحساب لكن تعذّر حفظ البيانات. تحقق من القواعد وأعد المحاولة');
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CredentialsPage(tenantName: biz.text.trim(), ownerPhone: phone.text.trim(), login: id, password: pw.text, tid: tid, brand: '${c1.text.trim().toUpperCase()} / ${c2.text.trim().toUpperCase()}')));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p1 = parseHex(c1.text) ?? C.g, p2 = parseHex(c2.text) ?? C.gold;
    return Scaffold(
      appBar: AppBar(title: const Text('عميل جديد'), flexibleSpace: Container(decoration: const BoxDecoration(gradient: C.brandGradient))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Form(
            key: form,
            child: ListView(padding: const EdgeInsets.all(14), children: [
              const PageHead('بيانات المشروع'),
              LuxCard(child: Column(children: [
                inp('اسم المشروع (يظهر على التطبيق)', biz, required: true),
                inp('اسم المالك', owner, required: true),
                inp('هاتف المالك (مع رمز الدولة)', phone, type: TextInputType.phone, required: true),
                inp('ملاحظات داخلية (اختياري)', notes, lines: 2),
              ])),
              const PageHead('حساب المالك'),
              LuxCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                inp('بريد المالك (اختياري — للاسترجاع بنفسه)', email, type: TextInputType.emailAddress, onChanged: (_) => setState(() {})),
                if (email.text.trim().isEmpty) inp('اسم الدخول (إنجليزي)', login, onChanged: (v) => setState(() {})),
                Row(children: [
                  Expanded(child: inp('كلمة المرور المؤقتة', pw)),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(onPressed: () => setState(() => pw.text = genPassword(login.text)), icon: const Icon(Icons.casino_rounded), tooltip: 'توليد'),
                ]),
                const Text('يُجبر المالك على تغيير كلمة المرور عند أول دخول.', style: TextStyle(color: C.muted, fontSize: 11.5)),
              ])),
              const PageHead('الاشتراك'),
              LuxCard(child: Column(children: [
                DropdownButtonFormField<String>(
                  value: planId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الباقة'),
                  items: [for (final e in widget.plans.entries) if (e.value is Map) DropdownMenuItem(value: e.key, child: Text('${(e.value as Map)['name']}'))],
                  onChanged: (v) => setState(() => planId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: months,
                  decoration: const InputDecoration(labelText: 'مدة الاشتراك'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('شهر')),
                    DropdownMenuItem(value: 2, child: Text('شهران')),
                    DropdownMenuItem(value: 3, child: Text('3 أشهر')),
                    DropdownMenuItem(value: 6, child: Text('6 أشهر')),
                    DropdownMenuItem(value: 12, child: Text('سنة')),
                  ],
                  onChanged: (v) => setState(() => months = v!),
                ),
              ])),
              const PageHead('الهوية (ألوان التطبيق)'),
              LuxCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final p in _presets)
                    ActionChip(
                      avatar: CircleAvatar(backgroundColor: parseHex(p.$2)),
                      label: Text(p.$1),
                      onPressed: () => setState(() {
                        c1.text = p.$2;
                        c2.text = p.$3;
                      }),
                    ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: inp('اللون الأساسي (HEX)', c1, onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(child: inp('اللون الثانوي (HEX)', c2, onChanged: (_) => setState(() {}))),
                ]),
                Container(
                  height: 54,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [p1, p1.withOpacity(.85)]), borderRadius: BorderRadius.circular(16), border: Border.all(color: p2, width: 2)),
                  alignment: Alignment.center,
                  child: Text(biz.text.isEmpty ? 'معاينة الهوية' : biz.text, style: TextStyle(color: p2, fontWeight: FontWeight.w900, fontSize: 17)),
                ),
              ])),
              const SizedBox(height: 6),
              LuxButton(busy ? 'جاري الإنشاء...' : 'إنشاء العميل', Icons.check_circle_rounded, busy ? null : _create, colors: const [Color(0xFFB68B24), C.gold], fg: C.dark),
              const SizedBox(height: 40),
            ]),
          ),
        ),
      ),
    );
  }
}

class CredentialsPage extends StatelessWidget {
  final String tenantName, ownerPhone, login, password, tid, brand;
  const CredentialsPage({super.key, required this.tenantName, required this.ownerPhone, required this.login, required this.password, required this.tid, required this.brand});

  String get message => 'مرحباً 🌿\nتم تفعيل حسابك في $kBrandName لمشروع "$tenantName".\n'
      'اسم الدخول: $login\nكلمة المرور المؤقتة: $password\n'
      'سيطلب منك التطبيق تغيير كلمة المرور عند أول دخول.\nاحتفظ بها ولا تشاركها مع أحد.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تم إنشاء العميل ✓'), flexibleSpace: Container(decoration: const BoxDecoration(gradient: C.brandGradient))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(padding: const EdgeInsets.all(14), children: [
            LuxCard(
              accent: C.g2,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tenantName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 10),
                SelectableText('اسم الدخول: $login\nكلمة المرور المؤقتة: $password', style: const TextStyle(fontWeight: FontWeight.w800, height: 1.9, fontSize: 15)),
                const SizedBox(height: 8),
                const Text('هذه المرة الوحيدة التي تظهر فيها كلمة المرور. انسخها وأرسلها الآن.', style: TextStyle(color: C.red, fontSize: 12, fontWeight: FontWeight.w800)),
              ]),
            ),
            LuxButton('إرسال للمالك عبر واتساب', Icons.chat_rounded, () => sendWa(context, ownerPhone, message), colors: const [Color(0xFF128C4A), C.wa]),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => copyText(context, message, 'تم نسخ الرسالة'), icon: const Icon(Icons.copy_rounded), label: const Text('نسخ الرسالة')),
            const SizedBox(height: 16),
            LuxCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('بيانات بناء التطبيق', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                SelectableText('معرّف المشروع: $tid\nالاسم: $tenantName\nالألوان: $brand', style: const TextStyle(fontSize: 12.5, height: 1.8, color: C.muted)),
                const SizedBox(height: 6),
                const Text('استخدمها في خطوة بناء تطبيق هذا العميل.', style: TextStyle(fontSize: 11.5, color: C.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------- صفحة العميل (الإدارة) ----------------

class TenantPage extends StatefulWidget {
  final String tid;
  final Map<String, dynamic> plans, info;
  const TenantPage({super.key, required this.tid, required this.plans, required this.info});
  @override
  State<TenantPage> createState() => _TenantPageState();
}

class _TenantPageState extends State<TenantPage> {
  Map<String, dynamic>? t;
  Map<String, dynamic> a = {};
  bool changed = false, busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await cloud.adminGet('tenants/${widget.tid}');
    final ad = await cloud.adminGet('tenantsAdmin/${widget.tid}');
    if (mounted) {
      setState(() {
        t = r;
        a = ad ?? {};
      });
    }
  }

  Future<void> _patch(Map<String, dynamic> p, String ok, {Map<String, dynamic>? adm}) async {
    setState(() => busy = true);
    var r = await cloud.adminPatch('tenants/${widget.tid}', p);
    if (r && adm != null) r = await cloud.adminPatch('tenantsAdmin/${widget.tid}', adm);
    changed = changed || r;
    await _load();
    if (mounted) {
      setState(() => busy = false);
      toast(context, r ? ok : 'تعذّر الحفظ');
    }
  }

  Future<void> _extend() async {
    var months = 1;
    final amount = TextEditingController();
    final note = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('تمديد الاشتراك'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: months,
              decoration: const InputDecoration(labelText: 'المدة'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('شهر')),
                DropdownMenuItem(value: 2, child: Text('شهران')),
                DropdownMenuItem(value: 3, child: Text('3 أشهر')),
                DropdownMenuItem(value: 6, child: Text('6 أشهر')),
                DropdownMenuItem(value: 12, child: Text('سنة')),
              ],
              onChanged: (v) => set(() => months = v!),
            ),
            const SizedBox(height: 10),
            TextField(controller: amount, keyboardType: numType, decoration: const InputDecoration(labelText: 'المبلغ المستلم')),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة (رقم حوالة...)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تمديد')),
          ],
        ),
      ),
    );
    if (go != true || t == null) return;
    final now = DateTime.now();
    final cur = DateTime.fromMillisecondsSinceEpoch(((t!['expiresAt'] as num?)?.toInt()) ?? now.millisecondsSinceEpoch);
    final exp = addMonths(cur.isAfter(now) ? cur : now, months);
    final grace = (t!['graceDays'] as num?)?.toInt() ?? 5;
    final pid = 'pay${DateTime.now().millisecondsSinceEpoch}';
    await _patch({
      'status': 'active',
      'expiresAt': exp.millisecondsSinceEpoch,
      'lockAt': exp.add(Duration(days: grace)).millisecondsSinceEpoch,
    }, 'تم التمديد حتى ${dayKey(exp)}', adm: {
      'payments/$pid': {'amount': num2(amount.text), 'months': months, 'at': now.toIso8601String(), 'note': note.text.trim()},
    });
  }

  Future<void> _changePlan() async {
    String? sel;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('تغيير الباقة'),
          content: DropdownButtonFormField<String>(
            value: sel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'الباقة الجديدة'),
            items: [for (final e in widget.plans.entries) if (e.value is Map) DropdownMenuItem(value: e.key, child: Text('${(e.value as Map)['name']}'))],
            onChanged: (v) => set(() => sel = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: sel == null ? null : () => Navigator.pop(ctx, true), child: const Text('تطبيق')),
          ],
        ),
      ),
    );
    if (go == true && sel != null) await _patch({'plan': widget.plans[sel]}, 'تم تغيير الباقة');
  }

  Future<void> _edit() async {
    final tt = t!;
    final nm = TextEditingController(text: '${tt['name'] ?? ''}');
    final ow = TextEditingController(text: '${tt['ownerName'] ?? ''}');
    final ph = TextEditingController(text: '${tt['phone'] ?? ''}');
    final br = Map<String, dynamic>.from((tt['brand'] as Map?) ?? {});
    final c1 = TextEditingController(text: '${br['primary'] ?? ''}');
    final c2 = TextEditingController(text: '${br['secondary'] ?? ''}');
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('تعديل البيانات'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nm, decoration: const InputDecoration(labelText: 'اسم المشروع')),
            const SizedBox(height: 8),
            TextField(controller: ow, decoration: const InputDecoration(labelText: 'اسم المالك')),
            const SizedBox(height: 8),
            TextField(controller: ph, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'الهاتف')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: c1, decoration: const InputDecoration(labelText: 'اللون الأساسي'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: c2, decoration: const InputDecoration(labelText: 'اللون الثانوي'))),
            ]),
            const SizedBox(height: 6),
            const Text('الاسم والألوان تظهر داخل التطبيق بعد إعادة بنائه.', style: TextStyle(fontSize: 11, color: C.muted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (go != true) return;
    if (parseHex(c1.text) == null || parseHex(c2.text) == null) return toast(context, 'لون غير صالح');
    await _patch({
      'name': nm.text.trim(),
      'ownerName': ow.text.trim(),
      'phone': ph.text.trim(),
      'brand': {'primary': c1.text.trim().replaceAll('#', '').toUpperCase(), 'secondary': c2.text.trim().replaceAll('#', '').toUpperCase()},
    }, 'تم الحفظ');
  }

  Future<void> _resetLogin() async {
    final tt = t!;
    final oldLogin = '${a['login'] ?? ''}';
    if (oldLogin.contains('@')) {
      if (!await confirmDialog(context, 'سيُرسل رابط تعيين كلمة مرور إلى $oldLogin. متابعة؟', yes: 'إرسال')) return;
      final e = await cloud.sendReset(oldLogin);
      if (mounted) toast(context, e ?? 'تم إرسال الرابط إلى بريد المالك ✓');
      return;
    }
    if (!await confirmDialog(context, 'سيُنشأ اسم دخول وكلمة مرور جديدان للمالك، ويتوقف القديم. بيانات المشروع لا تتأثر. متابعة؟', yes: 'إعادة التعيين')) return;
    setState(() => busy = true);
    final nl = 'shop${_rnd(5)}';
    final pw = genPassword(nl);
    final (err, uid) = await cloud.createAccount(nl, pw);
    if (err != null || uid == null) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, err ?? 'تعذّر الإنشاء');
      }
      return;
    }
    final a2 = await cloud.adminPut('users/$uid', {'role': 'owner', 'tid': widget.tid, 'name': '${tt['ownerName'] ?? ''}', 'login': nl, 'mustChange': true});
    final oldUid = '${this.a['ownerUid'] ?? ''}';
    if (a2 && oldUid.isNotEmpty) await cloud.adminDelete('users/$oldUid');
    await cloud.adminPatch('tenantsAdmin/${widget.tid}', {'ownerUid': uid, 'login': nl});
    changed = true;
    await _load();
    if (!mounted) return;
    setState(() => busy = false);
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CredentialsPage(tenantName: '${tt['name'] ?? ''}', ownerPhone: '${tt['phone'] ?? ''}', login: nl, password: pw, tid: widget.tid, brand: '')));
  }

  Future<void> _delete() async {
    final tt = t!;
    final name = '${tt['name'] ?? ''}';
    final confirm = TextEditingController();
    final pw = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('حذف العميل نهائياً', style: TextStyle(color: C.red)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('سيُحذف "$name" مع كل بياناته في السحابة (طلبات، قوائم، نسخ احتياطية) ولا يمكن التراجع.\nنصيحة: استخدم "تعليق" بدل الحذف إن كنت تريد إيقافه مؤقتاً.',
                style: const TextStyle(fontSize: 12.5, height: 1.7)),
            const SizedBox(height: 10),
            TextField(controller: confirm, decoration: InputDecoration(labelText: 'اكتب اسم المشروع للتأكيد', hintText: name)),
            const SizedBox(height: 8),
            TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة مرورك أنت')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: C.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف نهائي')),
        ],
      ),
    );
    if (go != true) return;
    if (confirm.text.trim() != name) return toast(context, 'اسم المشروع غير مطابق');
    setState(() => busy = true);
    if (!await cloud.verifyPassword(pw.text)) {
      if (mounted) {
        setState(() => busy = false);
        toast(context, 'كلمة مرورك غير صحيحة');
      }
      return;
    }
    final ids = await cloud.tenantUserIds(widget.tid) ?? [];
    for (final u in ids) {
      await cloud.adminDelete('users/$u');
    }
    await cloud.adminDelete('t/${widget.tid}');
    await cloud.adminDelete('tenantsAdmin/${widget.tid}');
    final ok = await cloud.adminDelete('tenants/${widget.tid}');
    if (!mounted) return;
    setState(() => busy = false);
    toast(context, ok ? 'تم حذف العميل' : 'تعذّر الحذف');
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final tt = t;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('${tt?['name'] ?? 'العميل'}'), flexibleSpace: Container(decoration: const BoxDecoration(gradient: C.brandGradient))),
        body: tt == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: ListView(padding: const EdgeInsets.all(14), children: [
                    _head(tt),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _act(Icons.event_repeat_rounded, 'تمديد الاشتراك', C.g2, _extend),
                      _act(Icons.workspace_premium_rounded, 'تغيير الباقة', C.gold, _changePlan),
                      _act(tt['status'] == 'active' ? Icons.pause_circle_rounded : Icons.play_circle_rounded, tt['status'] == 'active' ? 'تعليق' : 'تفعيل', C.orange,
                          () => _patch({'status': tt['status'] == 'active' ? 'suspended' : 'active'}, tt['status'] == 'active' ? 'تم التعليق' : 'تم التفعيل')),
                      _act(Icons.edit_rounded, 'تعديل البيانات', C.blue, _edit),
                      _act(Icons.lock_reset_rounded, 'إعادة تعيين الدخول', C.purple, _resetLogin),
                      _act(Icons.chat_rounded, 'تذكير بالتجديد', C.wa, () {
                        final left = ((tt['expiresAt'] as num?) == null) ? null : (((tt['expiresAt'] as num).toInt() - DateTime.now().millisecondsSinceEpoch) / 86400000).ceil();
                        sendWa(context, '${tt['phone'] ?? ''}',
                            'مرحباً ${tt['ownerName'] ?? ''} 🌿\n${left == null ? '' : left >= 0 ? 'ينتهي اشتراكك في $kBrandName بعد $left يوم.' : 'انتهى اشتراكك في $kBrandName.'}\nللتجديد تواصل معنا. شكراً لثقتك.');
                      }),
                    ]),
                    const SizedBox(height: 16),
                    const PageHead('الدفعات'),
                    ..._payments(tt),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _delete,
                      icon: const Icon(Icons.delete_forever_rounded, color: C.red),
                      label: const Text('حذف العميل نهائياً', style: TextStyle(color: C.red)),
                    ),
                    const SizedBox(height: 30),
                  ]),
                ),
              ),
      ),
    );
  }

  Widget _act(IconData i, String t, Color c, VoidCallback f) => OutlinedButton.icon(
        onPressed: busy ? null : f,
        icon: Icon(i, color: c, size: 18),
        label: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w800)),
      );

  Widget _head(Map<String, dynamic> tt) {
    final st = tenantState(tt);
    final (label, col) = tenantStateLabel(st);
    final ex = (tt['expiresAt'] as num?)?.toInt();
    final br = Map<String, dynamic>.from((tt['brand'] as Map?) ?? {});
    return LuxCard(
      accent: col,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${tt['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
          Badge2(label, col),
        ]),
        const SizedBox(height: 8),
        Text('المالك: ${tt['ownerName'] ?? ''} • ${tt['phone'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
        Text('الدخول: ${a['login'] ?? ''}', style: const TextStyle(fontSize: 12.5, color: C.muted)),
        Text('الباقة: ${tt['plan']?['name'] ?? '—'}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        if (ex != null) Text('ينتهي: ${dayKey(DateTime.fromMillisecondsSinceEpoch(ex))}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: col)),
        const SizedBox(height: 6),
        Row(children: [
          Container(width: 22, height: 22, decoration: BoxDecoration(color: parseHex('${br['primary'] ?? ''}') ?? C.g, borderRadius: BorderRadius.circular(6))),
          const SizedBox(width: 4),
          Container(width: 22, height: 22, decoration: BoxDecoration(color: parseHex('${br['secondary'] ?? ''}') ?? C.gold, borderRadius: BorderRadius.circular(6))),
          const SizedBox(width: 8),
          Expanded(child: SelectableText('معرّف: ${widget.tid}   ${br['primary'] ?? ''}/${br['secondary'] ?? ''}', style: const TextStyle(fontSize: 11, color: C.muted))),
        ]),
        if ('${a['notes'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('ملاحظات: ${a['notes']}', style: const TextStyle(fontSize: 11.5, color: C.muted))),
      ]),
    );
  }

  List<Widget> _payments(Map<String, dynamic> tt) {
    final l = asMapList(a['payments'])..sort((x, y) => '${y['at']}'.compareTo('${x['at']}'));
    if (l.isEmpty) return [const Empty('لا توجد دفعات مسجّلة', icon: Icons.receipt_long_outlined)];
    return [
      for (final p in l)
        LuxCard(
          accent: C.g2,
          child: Row(children: [
            const Icon(Icons.check_circle, color: C.g2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['months']} شهر', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${DateTime.tryParse('${p['at']}') == null ? '' : dateText(DateTime.parse('${p['at']}'))}${'${p['note'] ?? ''}'.isEmpty ? '' : ' • ${p['note']}'}', style: const TextStyle(color: C.muted, fontSize: 11)),
              ]),
            ),
            Text(qtyText(_d(p['amount'])), style: const TextStyle(fontWeight: FontWeight.w900, color: C.g2)),
          ]),
        ),
    ];
  }
}
