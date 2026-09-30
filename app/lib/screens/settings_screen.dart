import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _confidenceThreshold = TariqMapConstants.defaultConfidenceThreshold;
  int    _liveFps             = TariqMapConstants.defaultLiveFps;
  bool   _wifiOnly            = true;
  int    _retentionDays       = 90;
  bool   _loading             = true;
  bool   _saving              = false;
  late TextEditingController _apiUrlController;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _confidenceThreshold = prefs.getDouble('confidence_threshold')
            ?? TariqMapConstants.defaultConfidenceThreshold;
        _liveFps       = prefs.getInt('live_fps')       ?? TariqMapConstants.defaultLiveFps;
        _wifiOnly      = prefs.getBool('wifi_only')     ?? true;
        _retentionDays = prefs.getInt('retention_days') ?? 90;
        _apiUrlController.text = prefs.getString('api_base_url') ?? '';
        _loading       = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('confidence_threshold', _confidenceThreshold);
    await prefs.setInt('live_fps', _liveFps);
    await prefs.setBool('wifi_only', _wifiOnly);
    await prefs.setInt('retention_days', _retentionDays);
    await prefs.setString('api_base_url', _apiUrlController.text.trim());
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text('Settings saved'),
          ]),
          backgroundColor: AppColors.syncDone,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        elevation: 0,
        title: const Text('Settings',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _loading || _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.teal)))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [

                // ── Detection ────────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.psychology_rounded,
                  title: 'Detection',
                  children: [
                    _SliderRow(
                      label: 'Confidence threshold',
                      valueLabel: '${(_confidenceThreshold * 100).toStringAsFixed(0)}%',
                      description: 'Higher = fewer but more reliable detections.',
                      value: _confidenceThreshold,
                      min: 0.10,
                      max: 0.80,
                      divisions: 14,
                      onChanged: (v) => setState(() => _confidenceThreshold = v),
                    ),
                    const _SectionDivider(),
                    _SliderRow(
                      label: 'Live inference rate',
                      valueLabel: '$_liveFps fps',
                      description: '3–8 fps recommended. Higher = more battery drain.',
                      value: _liveFps.toDouble(),
                      min: 1,
                      max: 15,
                      divisions: 14,
                      onChanged: (v) => setState(() => _liveFps = v.round()),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Sync ─────────────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.cloud_sync_rounded,
                  title: 'Synchronisation',
                  children: [
                    _ToggleRow(
                      label: 'Wi-Fi only uploads',
                      description: 'Prevents mobile data usage for cloud sync.',
                      value: _wifiOnly,
                      onChanged: (v) => setState(() => _wifiOnly = v),
                    ),
                    const _SectionDivider(),
                    _TextFieldRow(
                      label: 'API Base URL',
                      description: 'Leave blank to use default. Example: http://192.168.1.15:8000/v1',
                      controller: _apiUrlController,
                      hint: 'http://192.168.1.15:8000/v1',
                    ),
                    const _SectionDivider(),
                    _SliderRow(
                      label: 'Local data retention',
                      valueLabel: _retentionDays == 0 ? 'Forever' : '$_retentionDays days',
                      description: 'Synced data older than this may be cleaned up.',
                      value: _retentionDays.toDouble(),
                      min: 0,
                      max: 365,
                      divisions: 13,
                      onChanged: (v) => setState(() => _retentionDays = v.round()),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── About ─────────────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.info_outline_rounded,
                  title: 'About',
                  children: [
                    _InfoRow(label: 'Model bundle',
                      value: TariqMapConstants.modelBundleVersion),
                    const _SectionDivider(),
                    _InfoRow(label: 'Detection classes',
                      value: TariqMapConstants.allCodes.join(' · ')),
                    const _SectionDivider(),
                    _InfoRow(label: 'Rutting limitation',
                      value: 'Visual only — no depth measurement'),
                  ],
                ),
              ],
            ),
    );
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData       icon;
  final String         title;
  final List<Widget>   children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Row(children: [
          Icon(icon, size: 14, color: AppColors.teal),
          const SizedBox(width: 6),
          Text(title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.teal,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            )),
        ]),
      ),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(children: children),
      ),
    ],
  );
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 16, endIndent: 16,
        color: AppColors.borderLight);
}

// ── Slider row ────────────────────────────────────────────────────────────────

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String   label;
  final String   valueLabel;
  final String   description;
  final double   value;
  final double   min;
  final double   max;
  final int      divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
            style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.teal.withAlpha(18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(valueLabel,
              style: const TextStyle(
                color: AppColors.teal,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              )),
          ),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.teal,
            inactiveTrackColor: AppColors.teal.withAlpha(30),
            thumbColor: AppColors.teal,
            overlayColor: AppColors.teal.withAlpha(30),
            trackHeight: 3,
          ),
          child: Slider(
            value: value,
            min: min, max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        Text(description,
          style: const TextStyle(color: Colors.black38, fontSize: 11)),
      ],
    ),
  );
}

// ── Toggle row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String   label;
  final String   description;
  final bool     value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(description,
              style: const TextStyle(color: Colors.black38, fontSize: 11)),
          ],
        ),
      ),
      Switch.adaptive(
        value: value,
        activeColor: AppColors.teal,
        onChanged: onChanged,
      ),
    ]),
  );
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Row(children: [
      Text(label,
        style: const TextStyle(color: Colors.black45, fontSize: 13)),
      const Spacer(),
      Flexible(
        child: Text(value,
          textAlign: TextAlign.end,
          style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13),
          overflow: TextOverflow.ellipsis),
      ),
    ]),
  );
}

// ── Text field row ────────────────────────────────────────────────────────────

class _TextFieldRow extends StatelessWidget {
  const _TextFieldRow({
    required this.label,
    required this.description,
    required this.controller,
    required this.hint,
  });

  final String label;
  final String description;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.black26, fontSize: 13),
            filled: true,
            fillColor: Colors.black.withAlpha(5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 6),
        Text(description,
          style: const TextStyle(color: Colors.black38, fontSize: 11)),
      ],
    ),
  );
}

