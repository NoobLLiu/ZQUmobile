/// 个人信息编辑页。
///
/// 由「设置 → 编辑个人信息」进入，也用于首次启动的资料完善引导
/// （[ProfilePage.allowCancel] 为 false 时不允许返回）。
///
/// 学号与两套密码只存在本机，用于登录教务 / WebVPN 时代填，不上传。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/profile.dart';
import '../services/profile_repository.dart';

/// 个人信息表单页。保存成功后 pop 出填好的 [Profile]。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.initial, this.allowCancel = true});

  /// 传入时直接作为初值；为 null 则进页面后自行读取。
  final Profile? initial;

  /// 是否允许返回。false 用于首次启动的强制填写。
  final bool allowCancel;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _idCtrl = TextEditingController();
  final _jwglPwdCtrl = TextEditingController();
  final _vpnPwdCtrl = TextEditingController();

  String _term = kDefaultTerm;
  bool _hasCampus = false;

  bool _loading = true;
  bool _showJwglPwd = false;
  bool _showVpnPwd = false;

  /// 出错的字段：id / jwgl / vpn / null。
  String? _errorField;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_idCtrl, _jwglPwdCtrl, _vpnPwdCtrl]) {
      // 输入即清错，同时让学号的 x/12 计数跟着刷新
      c.addListener(() => setState(() => _error = null));
    }
    final initial = widget.initial;
    if (initial == null) {
      _load();
    } else {
      _bind(initial);
    }
  }

  Future<void> _load() async {
    final profile = await ProfileRepository.load();
    if (!mounted) return;
    _bind(profile);
  }

  void _bind(Profile profile) {
    _idCtrl.text = profile.studentId;
    _jwglPwdCtrl.text = profile.jwglPassword;
    _vpnPwdCtrl.text = profile.webvpnPassword;
    setState(() {
      _term = kTermOptions.contains(profile.term) ? profile.term : kDefaultTerm;
      _hasCampus = profile.hasCampusNetwork;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _jwglPwdCtrl.dispose();
    _vpnPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _idCtrl.text.trim();
    if (!isValidStudentId(id)) {
      setState(() {
        _errorField = 'id';
        _error = '学号需为 12 位数字';
      });
      return;
    }
    if (_jwglPwdCtrl.text.trim().isEmpty) {
      setState(() {
        _errorField = 'jwgl';
        _error = '请输入教务系统密码';
      });
      return;
    }
    if (_vpnPwdCtrl.text.trim().isEmpty) {
      setState(() {
        _errorField = 'vpn';
        _error = _hasCampus ? '请输入 WebVPN 密码（校外时需要用）' : '请输入 WebVPN 密码，校外登录需要';
      });
      return;
    }

    final profile = Profile(
      studentId: id,
      term: _term,
      hasCampusNetwork: _hasCampus,
      // 密码原样保存，不去空格：个别系统密码允许首尾空格
      jwglPassword: _jwglPwdCtrl.text,
      webvpnPassword: _vpnPwdCtrl.text,
    );
    await ProfileRepository.save(profile);
    if (!mounted) return;
    Navigator.of(context).pop(profile);
  }

  /// 一个带小眼睛的密码输入框。
  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String field,
    required bool visible,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        errorText: _errorField == field ? _error : null,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: visible ? '隐藏' : '显示',
          onPressed: onToggle,
          icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: widget.allowCancel,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.allowCancel ? '个人信息' : '完善个人信息'),
          automaticallyImplyLeading: widget.allowCancel,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    '账号与密码仅保存在本机，用于登录教务系统时自动代填，不会上传。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: _idCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: '学号',
                      hintText: '12 位数字',
                      counterText: '${_idCtrl.text.length}/12',
                      errorText: _errorField == 'id' ? _error : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),

                  _passwordField(
                    controller: _jwglPwdCtrl,
                    label: '教务系统密码',
                    field: 'jwgl',
                    visible: _showJwglPwd,
                    onToggle: () => setState(() => _showJwglPwd = !_showJwglPwd),
                  ),
                  const SizedBox(height: 16),

                  _passwordField(
                    controller: _vpnPwdCtrl,
                    label: 'WebVPN 密码',
                    field: 'vpn',
                    visible: _showVpnPwd,
                    onToggle: () => setState(() => _showVpnPwd = !_showVpnPwd),
                  ),
                  const SizedBox(height: 24),

                  Text('学期', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  RadioGroup<String>(
                    groupValue: _term,
                    onChanged: (v) => setState(() => _term = v ?? _term),
                    child: Column(
                      children: [
                        for (final t in kTermOptions)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: ShapeDecoration(
                              color: _term == t
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.08,
                                    )
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: _term == t
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outlineVariant,
                                  width: _term == t ? 1.5 : 1,
                                ),
                              ),
                            ),
                            child: Material(
                              // ListTile 的背景/水波纹画在最近的 Material 上，
                              // 需要自己的 Material，避免被外层带背景色的
                              // DecoratedBox 遮挡（否则触发调试断言）。
                              type: MaterialType.transparency,
                              child: RadioListTile<String>(
                                value: t,
                                dense: true,
                                title: Text(t),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text('校园网', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(value: true, label: Text('已购校园网')),
                      ButtonSegment<bool>(value: false, label: Text('未购校园网')),
                    ],
                    selected: {_hasCampus},
                    onSelectionChanged: (s) =>
                        setState(() => _hasCampus = s.first),
                  ),
                ],
              ),
        bottomNavigationBar: _loading
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('保存'),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
