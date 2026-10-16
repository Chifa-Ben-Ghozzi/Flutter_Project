import 'dart:async';
import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import 'package:flutter/foundation.dart';

// ===================== DEV SWITCHES =====================
/// false = no client-side checks (to test the UI freely)
/// true  = checks are active (empty fields, bad email, short password...)
const bool kValidate = true;

/// true  = skip the server completely and fake a login (needs Api.devLogin)
/// false = real calls to the backend
const bool kBypassBackend = false;
// ========================================================

const _indigo = Color(0xFF3F51B5);
const _deep = Color(0xFF1A237E);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final pwd = TextEditingController();
  final name = TextEditingController();
  final confirm = TextEditingController();
  final emailFocus = FocusNode();
  final pwdFocus = FocusNode();
  final confirmFocus = FocusNode();

  bool register = false, busy = false, showPwd = false, blink = false;
  final Set<String> bad = {}; // fields currently in error
  String? error; // message in the red banner
  String _lastError = '';
  Timer? _errTimer, _blinkTimer;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    pwdFocus.addListener(_rebuild);
    emailFocus.addListener(_rebuild);
    email.addListener(_rebuild);
    pwd.addListener(_rebuild); // live strength bar
    confirm.addListener(_rebuild); // live match hint
    confirmFocus.addListener(_rebuild);

    // the car blinks by itself every few seconds
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 3400), (_) {
      if (!mounted) return;
      setState(() => blink = true);
      Future.delayed(const Duration(milliseconds: 170), () {
        if (mounted) setState(() => blink = false);
      });
    });
  }

  @override
  void dispose() {
    _errTimer?.cancel();
    _blinkTimer?.cancel();
    email.dispose();
    pwd.dispose();
    name.dispose();
    confirm.dispose();
    emailFocus.dispose();
    pwdFocus.dispose();
    confirmFocus.dispose();
    super.dispose();
  }

  // ---------- Banner ----------
  void _showError(String m) {
    _errTimer?.cancel();
    setState(() {
      error = m;
      _lastError = m;
    });
    _errTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => error = null);
    });
  }

  // ---------- Validation (client side) ----------
  bool _validate() {
    bad.clear();
    final e = email.text.trim();
    String? msg;

    if (register && name.text.trim().isEmpty) {
      bad.add('name');
      msg ??= context.tr('err_name');
    }
    if (e.isEmpty) {
      bad.add('email');
      msg ??= context.tr('err_email_empty');
    } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
      bad.add('email');
      msg ??= context.tr('err_email_format');
    } else if (register &&
        !RegExp(r'(^|\.)(edu|ac)(\.|$)|univ', caseSensitive: false).hasMatch(e.split('@')[1])) {
      bad.add('email');
      msg ??= context.tr('err_email_uni');
    }
    if (pwd.text.isEmpty) {
      bad.add('pwd');
      msg ??= context.tr('err_pwd_empty');
    } else if (register && pwd.text.length < 6) {
      bad.add('pwd');
      msg ??= context.tr('err_pwd_short');
    }
    if (register && confirm.text != pwd.text) {
      bad.add('confirm');
      msg ??= context.tr('err_pwd_match');
    }

    if (msg != null) {
      setState(() {});
      _showError(msg);
      return false;
    }
    return true;
  }

  // ---------- Submit ----------
  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    final l10n = L10nScope.read(context); // read before the awaits
    if (kValidate && !_validate()) return;

    setState(() => busy = true);
    try {
      if (kBypassBackend) {
        await Future.delayed(const Duration(milliseconds: 800));
        await Api.devLogin();
      } else if (register) {
        await Api.register(email.text.trim(), pwd.text, name.text.trim());
      } else {
        await Api.login(email.text.trim(), pwd.text);
      }
    } on ApiException catch (e) {
      // message coming from the server (wrong password, email already used...)
      bad.addAll(e.message.toLowerCase().contains('mot de passe') ? {'pwd', 'email'} : {'email'});
      _showError(l10n.trServer(e.message));
    // } catch (_) {
    //   _showError(l10n.tr('err_server'));
    // } commented ech
    }catch (e) {
      debugPrint('AUTH ERROR: $e');
      _showError(kDebugMode
          ? '${l10n.tr('err_server')}\n${Api.base}\n$e'
          : l10n.tr('err_server'));
    }
    if (mounted) setState(() => busy = false);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final eyesClosed = ((pwdFocus.hasFocus || confirmFocus.hasFocus) && !showPwd) || blink;
    final look = emailFocus.hasFocus ? ((email.text.length / 22).clamp(0.0, 1.0) * 2 - 1) * 0.8 : 0.0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_indigo, _deep],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(offset: Offset(0, (1 - v) * 30), child: child),
                      ),
                      child: Column(children: [
                        _mascot(eyesClosed, look),
                        const SizedBox(height: 12),
                        const Text('Campus Carpool',
                            style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 20),
                        _card(),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // language switcher, top right
          const Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(padding: EdgeInsets.all(12), child: LangSwitcher()),
            ),
          ),
          _banner(),
        ],
      ),
    );
  }

  Widget _mascot(bool closed, double look) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: closed ? 1.0 : 0.0),
      // quick for a natural blink, slower when the password field takes focus
      duration: Duration(milliseconds: blink && !pwdFocus.hasFocus && !confirmFocus.hasFocus ? 90 : 280),
      curve: Curves.easeOut,
      builder: (context, c, _) => TweenAnimationBuilder<double>(
        tween: Tween(end: look),
        duration: const Duration(milliseconds: 200),
        builder: (context, l, _) => SizedBox(
          width: 130,
          height: 110,
          child: CustomPaint(painter: _CarPainter(closed: c, look: l)),
        ),
      ),
    );
  }

  Widget _card() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            register ? context.tr('create_account') : context.tr('welcome_back'),
            key: ValueKey('$register${context.l10n.lang}'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 18),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: register
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _field(ctrl: name, k: 'name', label: context.tr('full_name'), icon: Icons.person_outline),
                )
              : const SizedBox(width: double.infinity),
        ),
        _field(
          ctrl: email,
          k: 'email',
          label: context.tr('uni_email'),
          icon: Icons.mail_outline,
          focus: emailFocus,
          type: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        _field(
          ctrl: pwd,
          k: 'pwd',
          label: context.tr('password'),
          icon: Icons.lock_outline,
          focus: pwdFocus,
          obscure: !showPwd,
          onSubmit: submit,
          suffix: IconButton(
            icon: Icon(showPwd ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => showPwd = !showPwd),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: register
              ? Column(children: [
                  if (pwd.text.isNotEmpty) _strengthBar(),
                  const SizedBox(height: 12),
                  _field(
                    ctrl: confirm,
                    k: 'confirm',
                    label: context.tr('confirm_password'),
                    icon: Icons.lock_reset,
                    focus: confirmFocus,
                    obscure: !showPwd,
                    onSubmit: submit,
                  ),
                  _matchHint(),
                ])
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _indigo,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: busy ? null : submit,
            child: busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(register ? context.tr('signup') : context.tr('login'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => setState(() {
            register = !register;
            bad.clear();
            confirm.clear();
          }),
          child: Text(register ? context.tr('have_account') : context.tr('no_account')),
        ),
      ]),
    );
  }

  // ---------- Password strength ----------
  /// 1 = weak, 2 = medium, 3 = strong
  int _strength() {
    final p = pwd.text;
    if (p.length < 6) return 1;
    var score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'\d').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    return score <= 1 ? 1 : (score == 2 ? 2 : 3);
  }

  Widget _strengthBar() {
    final lvl = _strength();
    final color = [Colors.red.shade600, Colors.orange.shade700, Colors.green.shade600][lvl - 1];
    final label = [context.tr('pwd_weak'), context.tr('pwd_medium'), context.tr('pwd_strong')][lvl - 1];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 6,
              decoration: BoxDecoration(
                color: i < lvl ? color : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < 2) const SizedBox(width: 6),
        ],
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }

  Widget _matchHint() {
    if (confirm.text.isEmpty) return const SizedBox.shrink();
    final ok = confirm.text == pwd.text;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.cancel, size: 16, color: ok ? Colors.green : Colors.red),
        const SizedBox(width: 6),
        Text(
          ok ? context.tr('pwd_match_ok') : context.tr('err_pwd_match'),
          style: TextStyle(fontSize: 12, color: ok ? Colors.green.shade700 : Colors.red),
        ),
      ]),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String k,
    required String label,
    required IconData icon,
    FocusNode? focus,
    bool obscure = false,
    TextInputType? type,
    Widget? suffix,
    VoidCallback? onSubmit,
  }) {
    final err = bad.contains(k);
    OutlineInputBorder b(Color c, [double w = 1.5]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextField(
      controller: ctrl,
      focusNode: focus,
      obscureText: obscure,
      keyboardType: type,
      onChanged: (_) {
        if (bad.contains(k)) setState(() => bad.remove(k));
      },
      onSubmitted: (_) => onSubmit?.call(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: err ? Colors.red : null),
        suffixIcon: suffix,
        filled: true,
        fillColor: err ? Colors.red.shade50 : Colors.grey.shade100,
        border: b(Colors.transparent),
        enabledBorder: b(err ? Colors.red : Colors.transparent),
        focusedBorder: b(err ? Colors.red : _indigo, 2),
      ),
    );
  }

  Widget _banner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: AnimatedSlide(
          offset: error == null ? const Offset(0, -1.6) : Offset.zero,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: error == null ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                color: Colors.red.shade600,
                elevation: 8,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error ?? _lastError,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => error = null),
                      child: const Icon(Icons.close, color: Colors.white70, size: 20),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A cartoon car seen from the front. The windshield is its face:
/// [closed] 0 = eyes open, 1 = eyes shut (headlights dim too).
/// [look] -1..1 moves the pupils left/right.
class _CarPainter extends CustomPainter {
  final double closed, look;
  _CarPainter({required this.closed, required this.look});

  static const _glass = Color(0xFF1F2A7A);
  static const _ink = Color(0xFF1A237E);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;

    // ground shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w / 2, h * 0.975), width: w * 0.85, height: h * 0.08),
      Paint()..color = Colors.black.withOpacity(0.22),
    );

    // wheels (behind the body)
    final wheel = Paint()..color = const Color(0xFF0D1445);
    for (final x in [0.17, 0.83]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w * x, h * 0.86), width: w * 0.17, height: h * 0.2),
          const Radius.circular(6),
        ),
        wheel,
      );
    }

    // cabin
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(w * 0.17, h * 0.03, w * 0.83, h * 0.55),
        topLeft: Radius.circular(h * 0.22),
        topRight: Radius.circular(h * 0.22),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      ),
      Paint()..color = Colors.white,
    );

    // body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(w * 0.04, h * 0.45, w * 0.96, h * 0.89),
        Radius.circular(h * 0.15),
      ),
      Paint()..color = const Color(0xFFF4F5FF),
    );

    // side mirrors
    final mirror = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(w * 0.12, h * 0.47), w * 0.04, mirror);
    canvas.drawCircle(Offset(w * 0.88, h * 0.47), w * 0.04, mirror);

    // windshield
    final glassRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(w * 0.23, h * 0.11, w * 0.77, h * 0.45),
      Radius.circular(h * 0.13),
    );
    canvas.drawRRect(glassRect, Paint()..color = _glass);

    // eyes
    final eyeR = h * 0.1;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (final x in [0.385, 0.615]) {
      final e = Offset(w * x, h * 0.285);

      canvas.drawCircle(e, eyeR, Paint()..color = Colors.white);
      final pupil = e + Offset(look * eyeR * 0.45, eyeR * 0.12);
      canvas.drawCircle(pupil, eyeR * 0.5, Paint()..color = _ink);
      canvas.drawCircle(pupil + Offset(-eyeR * 0.17, -eyeR * 0.17), eyeR * 0.15, Paint()..color = Colors.white);

      // eyelid, same colour as the glass, slides down
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: e, radius: eyeR + 0.5)));
      canvas.drawRect(
        Rect.fromLTRB(e.dx - eyeR - 1, e.dy - eyeR - 1, e.dx + eyeR + 1, e.dy - eyeR + 2 * eyeR * closed),
        Paint()..color = _glass,
      );
      canvas.restore();

      // closed-eye curve (a happy ^ ^ line)
      if (closed > 0.2) {
        final y = e.dy - eyeR + 2 * eyeR * closed;
        final path = Path()
          ..moveTo(e.dx - eyeR * 0.9, y.clamp(e.dy - eyeR, e.dy + eyeR * 0.1))
          ..quadraticBezierTo(e.dx, y + eyeR * 0.5 * closed, e.dx + eyeR * 0.9,
              y.clamp(e.dy - eyeR, e.dy + eyeR * 0.1));
        canvas.drawPath(path, stroke..color = Colors.white.withOpacity(closed.clamp(0.0, 1.0)));
      }
    }

    // headlights: bright when awake, dim when eyes are closed
    final awake = 1 - closed;
    final lightColor = Color.lerp(const Color(0xFFB9BCD6), const Color(0xFFFFE082), awake)!;
    final lights = [Offset(w * 0.16, h * 0.63), Offset(w * 0.84, h * 0.63)];
    for (final p in lights) {
      if (awake > 0.05) {
        canvas.drawCircle(
          p,
          h * 0.11,
          Paint()
            ..color = const Color(0xFFFFE082).withOpacity(0.55 * awake)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
      }
      canvas.drawCircle(p, h * 0.07, Paint()..color = lightColor);
    }

    // grille + smile
    final mouth = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final my = h * 0.64;
    final depth = h * (0.09 + 0.05 * closed); // bigger smile when eyes are shut
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.40, my)
        ..quadraticBezierTo(w * 0.5, my + depth * 1.6, w * 0.60, my),
      mouth,
    );

    // license plate
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(w * 0.5, h * 0.8), width: w * 0.2, height: h * 0.08),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFD7DBF5),
    );
  }

  @override
  bool shouldRepaint(_CarPainter o) => o.closed != closed || o.look != look;
}