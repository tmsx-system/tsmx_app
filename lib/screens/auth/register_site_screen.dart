import 'package:flutter/material.dart';

import '../../services/mobile_site_registry_service.dart';
import '../../theme/app_colors.dart';

class RegisteredSiteResult {
  final String siteName;
  final String siteCode;
  final String siteUrl;

  const RegisteredSiteResult({
    required this.siteName,
    required this.siteCode,
    required this.siteUrl,
  });
}

class RegisterSiteScreen extends StatefulWidget {
  const RegisterSiteScreen({super.key});

  @override
  State<RegisterSiteScreen> createState() => _RegisterSiteScreenState();
}

class _RegisterSiteScreenState extends State<RegisterSiteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _registryService = MobileSiteRegistryService();
  final _siteNameCtrl = TextEditingController();
  final _siteCodeCtrl = TextEditingController();
  final _siteUrlCtrl = TextEditingController();
  final _contactNameCtrl = TextEditingController();
  final _phoneNumberCtrl = TextEditingController();
  String _frappeVersion = '16';
  String _erpnextVersion = '16';
  bool _isSaving = false;

  @override
  void dispose() {
    _siteNameCtrl.dispose();
    _siteCodeCtrl.dispose();
    _siteUrlCtrl.dispose();
    _contactNameCtrl.dispose();
    _phoneNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await _registryService.registerSite(
        siteName: _siteNameCtrl.text,
        siteCode: _siteCodeCtrl.text,
        siteUrl: _siteUrlCtrl.text,
        frappeVersion: _frappeVersion,
        erpnextVersion: _erpnextVersion,
        contactName: _contactNameCtrl.text,
        phoneNumber: _phoneNumberCtrl.text,
        enabled: false,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        RegisteredSiteResult(
          siteName: _siteNameCtrl.text.trim(),
          siteCode: _siteCodeCtrl.text.trim().toUpperCase(),
          siteUrl: _normalizedUrl(_siteUrlCtrl.text),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Register gagal: ${_cleanError(error)}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primary),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      labelStyle: const TextStyle(color: AppColors.slate, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shadowColor: AppColors.primary.withValues(alpha: 0.24),
      elevation: 8,
      padding: const EdgeInsets.symmetric(vertical: 17),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
  }

  String _normalizedUrl(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label wajib diisi';
    return null;
  }

  String? _validateUrl(String? value) {
    final message = _required(value, 'Site URL');
    if (message != null) return message;
    final normalized = _normalizedUrl(value!);
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return 'Site URL tidak valid';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
        ),
        title: const Text(
          'Register Site',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RegisterHero(),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryDark.withValues(alpha: 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _FormSectionTitle(
                            title: 'Informasi ERPNext',
                            subtitle:
                                'Masukkan data site yang akan direview developer TMSX Hub.',
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _siteNameCtrl,
                            decoration: _inputDecoration(
                              label: 'Site Name',
                              icon: Icons.business_rounded,
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (value) => _required(value, 'Site Name'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _siteCodeCtrl,
                            decoration: _inputDecoration(
                              label: 'Site Code',
                              icon: Icons.qr_code_2_rounded,
                            ),
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            validator: (value) => _required(value, 'Site Code'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _siteUrlCtrl,
                            decoration: _inputDecoration(
                              label: 'Site URL',
                              icon: Icons.link_rounded,
                            ),
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            validator: _validateUrl,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _VersionSelectField(
                                  label: 'Frappe Version',
                                  icon: Icons.layers_rounded,
                                  value: _frappeVersion,
                                  onChanged: _isSaving
                                      ? null
                                      : (value) => setState(
                                          () => _frappeVersion = value ?? '16',
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _VersionSelectField(
                                  label: 'ERPNext Version',
                                  icon: Icons.account_tree_rounded,
                                  value: _erpnextVersion,
                                  onChanged: _isSaving
                                      ? null
                                      : (value) => setState(
                                          () => _erpnextVersion = value ?? '16',
                                        ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _contactNameCtrl,
                            decoration: _inputDecoration(
                              label: 'Contact Name',
                              icon: Icons.person_outline_rounded,
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (value) =>
                                _required(value, 'Contact Name'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneNumberCtrl,
                            decoration: _inputDecoration(
                              label: 'Phone Number',
                              icon: Icons.phone_outlined,
                            ),
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) {
                              if (!_isSaving) _submit();
                            },
                          ),
                          const SizedBox(height: 14),
                          const _AdminApprovalNotice(),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isSaving ? null : _submit,
                            style: _primaryButtonStyle(),
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: Text(
                              _isSaving ? 'Mendaftarkan...' : 'Register Site',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RegisterHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.cloud_done_rounded,
              color: AppColors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mobile Site Registry',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _FormSectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.dns_rounded,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminApprovalNotice extends StatelessWidget {
  const _AdminApprovalNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.admin_panel_settings_outlined,
            color: Color(0xFF2563EB),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Site belum langsung aktif. Developer TMSX Hub akan review dan mengaktifkan dari registry.',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionSelectField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final ValueChanged<String?>? onChanged;

  const _VersionSelectField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      items: const [
        DropdownMenuItem(value: '15', child: Text('15')),
        DropdownMenuItem(value: '16', child: Text('16')),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        labelStyle: const TextStyle(color: AppColors.slate, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppColors.border.withValues(alpha: 0.8),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      style: const TextStyle(
        color: AppColors.navy,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      dropdownColor: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      validator: (value) =>
          value == null || value.isEmpty ? '$label wajib dipilih' : null,
    );
  }
}
