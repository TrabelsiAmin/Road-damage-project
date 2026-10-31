import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/organization.dart';
import '../services/organization_service.dart';

class OrganizationSelectionScreen extends StatefulWidget {
  const OrganizationSelectionScreen({
    super.key,
    this.isFirstLaunch = false,
    this.service,
  });

  final bool isFirstLaunch;
  final OrganizationService? service;

  @override
  State<OrganizationSelectionScreen> createState() => _OrganizationSelectionScreenState();
}

class _OrganizationSelectionScreenState extends State<OrganizationSelectionScreen> {
  late final OrganizationService _orgService;
  List<Organization> _organizations = [];
  Organization? _selectedOrg;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _orgService = widget.service ?? OrganizationService();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final list = await _orgService.fetchOrganizations();
      final current = await _orgService.getSelectedOrganization();
      if (mounted) {
        setState(() {
          _organizations = list;
          _selectedOrg = current ?? (list.isNotEmpty ? list.first : null);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load authorities: $e';
          _organizations = Organization.canonicalList;
          _selectedOrg = Organization.canonicalList.first;
          _loading = false;
        });
      }
    }
  }

  Future<void> _confirm() async {
    if (_selectedOrg == null) return;
    setState(() => _saving = true);
    final ok = await _orgService.setSelectedOrganization(_selectedOrg!);
    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.of(context).pop(_selectedOrg);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid authority selection. Please try again.'),
          backgroundColor: AppColors.mockWarning,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isFirstLaunch,
      child: Scaffold(
        backgroundColor: AppColors.offWhite,
        appBar: AppBar(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: !widget.isFirstLaunch,
          elevation: 0,
          title: Text(
            widget.isFirstLaunch ? 'Welcome to TariqMap' : 'Select Authority',
            style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.teal),
                ),
              )
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Operational Authority',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.isFirstLaunch
                            ? 'Please choose the authority responsible for road maintenance in your inspection area. You can change this anytime in Settings.'
                            : 'Select the authority responsible for newly captured inspections.',
                        style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(30),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.withAlpha(90)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.wifi_off_rounded, color: Colors.amber, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _organizations.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final org = _organizations[index];
                            final isSelected = _selectedOrg?.id == org.id;

                            IconData iconData = Icons.location_city_rounded;
                            if (org.code.contains('MINISTRY')) {
                              iconData = Icons.account_balance_rounded;
                            } else if (org.code.contains('AUTOROUTES')) {
                              iconData = Icons.alt_route_rounded;
                            }

                            return InkWell(
                              onTap: () => setState(() => _selectedOrg = org),
                              borderRadius: BorderRadius.circular(14),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected ? AppColors.teal : AppColors.borderLight,
                                    width: isSelected ? 2.0 : 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSelected
                                          ? AppColors.teal.withAlpha(20)
                                          : Colors.black.withAlpha(6),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppColors.teal.withAlpha(25)
                                            : AppColors.offWhite,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        iconData,
                                        color: isSelected ? AppColors.teal : Colors.black54,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            org.name,
                                            style: TextStyle(
                                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                              fontSize: 15,
                                              color: isSelected ? AppColors.navy : Colors.black87,
                                            ),
                                          ),
                                          if (org.nameFr != null && org.nameFr != org.name) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              org.nameFr!,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black45,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(Icons.check_circle_rounded, color: AppColors.teal, size: 22)
                                    else
                                      const Icon(Icons.radio_button_unchecked_rounded, color: Colors.black26, size: 22),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.teal,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _selectedOrg == null || _saving ? null : _confirm,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  'Confirm Authority',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
