import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../core/constants.dart';

/// Settings screen — all configurable inference and sync parameters.
///
/// Persists values via SharedPreferences so they survive app restarts.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Inference
  double _confidenceThreshold = TariqMapConstants.defaultConfidenceThreshold;
  int    _liveFps             = TariqMapConstants.defaultLiveFps;

  // Sync
  bool _wifiOnly        = true;
  int  _retentionDays   = 90;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _confidenceThreshold = prefs.getDouble('confidence_threshold') ??
            TariqMapConstants.defaultConfidenceThreshold;
        _liveFps    = prefs.getInt('live_fps')    ?? TariqMapConstants.defaultLiveFps;
        _wifiOnly   = prefs.getBool('wifi_only')  ?? true;
        _retentionDays = prefs.getInt('retention_days') ?? 90;
        _loading    = false;
      });
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('confidence_threshold', _confidenceThreshold);
    await prefs.setInt('live_fps', _liveFps);
    await prefs.setBool('wifi_only', _wifiOnly);
    await prefs.setInt('retention_days', _retentionDays);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved'), duration: Duration(seconds: 1)),
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
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.tealLight),
            onPressed: _loading ? null : _save,
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Inference ───────────────────────────────────────────────
                _Section(
                  title: 'Detection',
                  icon: Icons.psychology_outlined,
                  children: [
                    _LabeledRow(
                      label: 'Confidence threshold',
                      detail: '${(_confidenceThreshold * 100).toStringAsFixed(0)}%',
                      child: Slider(
                        value: _confidenceThreshold,
                        min: 0.10,
                        max: 0.80,
                        divisions: 14,
                        activeColor: AppColors.teal,
                        onChanged: (v) => setState(() => _confidenceThreshold = v),
                        semanticFormatterCallback: (v) =>
                            '${(v * 100).toStringAsFixed(0)}%',
                      ),
                    ),
                    const _Divider(),
                    _LabeledRow(
                      label: 'Live inference FPS',
                      detail: '$_liveFps fps',
                      child: Slider(
                        value: _liveFps.toDouble(),
                        min: 1,
                        max: 15,
                        divisions: 14,
                        activeColor: AppColors.teal,
                        onChanged: (v) => setState(() => _liveFps = v.round()),
                        semanticFormatterCallback: (v) => '${v.round()} fps',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Higher FPS increases battery usage. '
                        'Recommended: 3–8 fps for real-time. '
                        'Mock inference is always fast.',
                        style: const TextStyle(color: Colors.black45, fontSize: 11),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Sync ────────────────────────────────────────────────────
                _Section(
                  title: 'Synchronisation',
                  icon: Icons.cloud_sync_outlined,
                  children: [
                    SwitchListTile.adaptive(
                      title: const Text('Wi-Fi only sync',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                      subtitle: const Text('Prevent mobile data usage for uploads',
                          style: TextStyle(color: Colors.black45, fontSize: 12)),
                      value: _wifiOnly,
                      activeTrackColor: AppColors.teal,
                      onChanged: (v) => setState(() => _wifiOnly = v),
                    ),
                    const _Divider(),
                    _LabeledRow(
                      label: 'Data retention',
                      detail: _retentionDays == 0 ? 'Forever' : '$_retentionDays days',
                      child: Slider(
                        value: _retentionDays.toDouble(),
                        min: 0,
                        max: 365,
                        divisions: 13,
                        activeColor: AppColors.teal,
                        onChanged: (v) => setState(() => _retentionDays = v.round()),
                        semanticFormatterCallback: (v) =>
                            v == 0 ? 'Forever' : '${v.round()} days',
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Synced observations are never deleted locally '
                        'until the server confirms integrity.',
                        style: TextStyle(color: Colors.black45, fontSize: 11),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // ── About ───────────────────────────────────────────────────
                _Section(
                  title: 'About',
                  icon: Icons.info_outline,
                  children: [
                    _InfoRow(label: 'Model bundle', value: TariqMapConstants.modelBundleVersion),
                    const _Divider(),
                    _InfoRow(label: 'Canonical classes', value: TariqMapConstants.allCodes.join(', ')),
                    const _Divider(),
                    _InfoRow(label: 'D90 limitation', value: 'Visual rutting only — no depth measurement'),
                  ],
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout helpers
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});
  final String        title;
  final IconData      icon;
  final List<Widget>  children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.teal),
          const SizedBox(width: 6),
          Text(title.toUpperCase(),
              style: const TextStyle(color: AppColors.teal,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
        ]),
      ),
      Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
        color: Colors.white,
        child: Column(children: children),
      ),
    ],
  );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF0F0F0));
}

class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.detail, required this.child});
  final String label;
  final String detail;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(detail, style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        child,
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis),
      ),
    ]),
  );
}
