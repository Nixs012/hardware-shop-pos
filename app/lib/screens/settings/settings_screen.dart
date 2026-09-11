import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../../models/failed_sale.dart';
import '../../models/staff.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/printer_service.dart';
import '../../utils/theme.dart';

class SettingsScreen extends StatefulWidget {
  final Staff currentStaff;

  const SettingsScreen({super.key, required this.currentStaff});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _firestoreService = FirestoreService();
  final _printerService = PrinterService();
  final _shopNameController = TextEditingController();
  final _addressPhoneController = TextEditingController();
  final _footerController = TextEditingController();
  late Future<List<FailedSaleRecord>> _failedSalesFuture;
  PaperSize _paperSize = PaperSize.mm58;
  bool _printerConnected = false;
  bool _scanning = false;

  bool get _isAdmin => widget.currentStaff.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _failedSalesFuture = _loadFailedSales();
    _loadPrinterSettings();
  }

  Future<void> _loadPrinterSettings() async {
    if (kIsWeb) return;
    _shopNameController.text = await _printerService.getShopName();
    _addressPhoneController.text = await _printerService.getAddressPhone();
    _footerController.text = await _printerService.getFooterMessage();
    _paperSize = await _printerService.getPaperSize();
    _printerConnected = await _printerService.autoReconnect();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _addressPhoneController.dispose();
    _footerController.dispose();
    _printerService.dispose();
    super.dispose();
  }

  Future<void> _scanPrinters() async {
    setState(() => _scanning = true);
    try {
      final printers = await _printerService.scanBluetoothPrinters();
      if (!mounted) return;
      if (printers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Bluetooth printers found.')),
        );
        return;
      }
      final selected = await showDialog<BluetoothPrinterDevice>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Select Bluetooth Printer'),
          children: printers
              .map(
                (printer) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, printer),
                  child: Text('${printer.name}\n${printer.address}'),
                ),
              )
              .toList(),
        ),
      );
      if (selected == null) return;
      await _printerService.connectToPrinter(selected);
      if (mounted) {
        setState(() => _printerConnected = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printer connected and saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Printer scan/connect failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _savePrinterSettings() async {
    await _printerService.setPaperSize(_paperSize);
    await _printerService.saveReceiptSettings(
      shopName: _shopNameController.text.trim(),
      addressPhone: _addressPhoneController.text.trim(),
      footerMessage: _footerController.text.trim().isEmpty
          ? 'Thank you!'
          : _footerController.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Printer settings saved.')));
    }
  }

  Future<List<FailedSaleRecord>> _loadFailedSales() {
    return _isAdmin ? _firestoreService.getFailedSales() : Future.value([]);
  }

  void _refreshFailedSales() {
    setState(() {
      _failedSalesFuture = _loadFailedSales();
    });
  }

  Future<void> _retry(FailedSaleRecord record) async {
    try {
      await _firestoreService.retryFailedSale(record);
      if (!mounted) return;
      _refreshFailedSales();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale sync retry completed.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _refreshFailedSales();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Retry failed and remains in Needs Review: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _refreshFailedSales(),
      child: FutureBuilder<List<FailedSaleRecord>>(
        future: _failedSalesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final failedSales = snapshot.data ?? [];

          final failedSalesWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Needs Review',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sales that failed to sync are stored on this device until an Admin retries them.',
                style: TextStyle(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 16),
              if (failedSales.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No failed sales need review.')),
                )
              else
                ...failedSales.map(_buildFailedSale),
            ],
          );

          final logoutButton = Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () async {
                await AuthService().logout();
              },
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text(
                'Log Out',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );

          final accountSection = _buildAccountSection();

          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;

              if (isWide) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isAdmin) ...[
                        Expanded(
                          flex: 6,
                          child: _buildStaffSection(),
                        ),
                        const SizedBox(width: 24),
                      ],
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            accountSection,
                            if (_isAdmin) ...[
                              const SizedBox(height: 24),
                              _buildPrinterSection(),
                              const SizedBox(height: 24),
                              failedSalesWidget,
                              const Divider(height: 36, color: Colors.white24),
                            ] else
                              const SizedBox(height: 24),
                            logoutButton,
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  accountSection,
                  if (_isAdmin) ...[
                    const SizedBox(height: 24),
                    _buildStaffSection(),
                    const SizedBox(height: 24),
                    _buildPrinterSection(),
                    const SizedBox(height: 24),
                    failedSalesWidget,
                    const Divider(height: 48, color: Colors.white24),
                  ] else
                    const SizedBox(height: 24),
                  logoutButton,
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAccountSection() {
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.security, color: AppTheme.primaryColor),
                SizedBox(width: 10),
                Text(
                  'Account & Security',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Logged in as: ${widget.currentStaff.name} (${widget.currentStaff.role.toUpperCase()})',
              style: const TextStyle(
                color: AppTheme.secondaryColor,
                fontSize: 13,
              ),
            ),
            Text(
              widget.currentStaff.email,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    AppTheme.secondaryColor.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.3),
                ),
              ),
              onPressed: _showChangePasswordDialog,
              icon: const Icon(Icons.lock_reset, size: 18),
              label: const Text('Change Password'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    bool isLoading = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                ),
              ),
              title: const Row(
                children: [
                  Icon(Icons.lock_outline, color: AppTheme.primaryColor),
                  SizedBox(width: 10),
                  Text(
                    'Change Password',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    TextField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrent,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureCurrent
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppTheme.secondaryColor,
                          ),
                          onPressed: () => setDialogState(
                            () => obscureCurrent = !obscureCurrent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: newPasswordController,
                      obscureText: obscureNew,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        helperText: 'Minimum 6 characters',
                        helperStyle:
                            const TextStyle(color: AppTheme.secondaryColor),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureNew
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppTheme.secondaryColor,
                          ),
                          onPressed: () => setDialogState(
                            () => obscureNew = !obscureNew,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirm,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppTheme.secondaryColor,
                          ),
                          onPressed: () => setDialogState(
                            () => obscureConfirm = !obscureConfirm,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!isLoading)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: AppTheme.secondaryColor),
                    ),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          final currentPwd = currentPasswordController.text;
                          final newPwd = newPasswordController.text;
                          final confirmPwd = confirmPasswordController.text;

                          if (currentPwd.isEmpty ||
                              newPwd.isEmpty ||
                              confirmPwd.isEmpty) {
                            setDialogState(() {
                              errorMessage =
                                  'Please fill in all password fields.';
                            });
                            return;
                          }

                          if (newPwd.length < 6) {
                            setDialogState(() {
                              errorMessage =
                                  'New password must be at least 6 characters.';
                            });
                            return;
                          }

                          if (newPwd != confirmPwd) {
                            setDialogState(() {
                              errorMessage = 'New passwords do not match.';
                            });
                            return;
                          }

                          if (newPwd == currentPwd) {
                            setDialogState(() {
                              errorMessage =
                                  'New password must be different from current password.';
                            });
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                            errorMessage = null;
                          });

                          try {
                            await AuthService().changePassword(
                              currentPassword: currentPwd,
                              newPassword: newPwd,
                            );

                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Password changed successfully.',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            final errString = e.toString().toLowerCase();
                            String friendlyMsg = 'Failed to change password.';

                            if (errString.contains('wrong-password') ||
                                errString.contains('invalid-credential') ||
                                errString.contains('invalid-password')) {
                              friendlyMsg = 'Current password is incorrect.';
                            } else if (errString.contains('weak-password')) {
                              friendlyMsg =
                                  'New password is too weak. Please choose a stronger one.';
                            } else if (errString
                                .contains('requires-recent-login')) {
                              friendlyMsg =
                                  'Session expired. Please log out and log in again.';
                            } else {
                              friendlyMsg = e
                                  .toString()
                                  .replaceAll('Exception: ', '');
                            }

                            setDialogState(() {
                              isLoading = false;
                              errorMessage = friendlyMsg;
                            });
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Update Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStaffSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Staff Management',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showAddStaffDialog,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Staff'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<Staff>>(
              stream: _firestoreService.getStaffStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final staffList = snapshot.data ?? [];
                if (staffList.isEmpty) {
                  return const Text('No staff members found.');
                }

                // Auto-correct any legacy role typos or casing (e.g., 'CAHIER' -> 'cashier')
                for (final s in staffList) {
                  final cleanRole = s.role.trim().toLowerCase();
                  if (cleanRole != 'admin' && cleanRole != 'cashier') {
                    _firestoreService.updateStaff(
                      Staff(
                        id: s.id,
                        name: s.name,
                        role: 'cashier',
                        email: s.email,
                        active: s.active,
                        pin: s.pin,
                        authUid: s.authUid,
                      ),
                    );
                  }
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: staffList.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white24),
                  itemBuilder: (context, index) {
                    final staff = staffList[index];
                    final isSelf = staff.id == widget.currentStaff.id;
                    final displayRole =
                        staff.role.trim().toLowerCase() == 'admin'
                            ? 'ADMIN'
                            : 'CASHIER';
                    return ListTile(
                      title: Text(staff.name),
                      subtitle: Text(
                        '${staff.email}\nRole: $displayRole',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!staff.active)
                            const Chip(
                              label: Text(
                                'Deactivated',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                ),
                              ),
                              backgroundColor: Colors.red,
                              padding: EdgeInsets.zero,
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => _showEditStaffDialog(staff),
                          ),
                          IconButton(
                            icon: Icon(
                              staff.active ? Icons.block : Icons.check_circle,
                              color: isSelf
                                  ? Colors.grey
                                  : (staff.active ? Colors.red : Colors.green),
                            ),
                            onPressed: isSelf
                                ? null
                                : () => _toggleStaffStatus(staff),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleStaffStatus(Staff staff) async {
    final newStatus = !staff.active;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(newStatus ? 'Reactivate Staff?' : 'Deactivate Staff?'),
        content: Text(
          newStatus
              ? 'Are you sure you want to reactivate ${staff.name}?'
              : 'Are you sure you want to deactivate ${staff.name}? They will no longer be able to log in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: newStatus ? Colors.green : Colors.red,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(newStatus ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final updatedStaff = Staff(
        id: staff.id,
        name: staff.name,
        role: staff.role,
        email: staff.email,
        active: newStatus,
        pin: staff.pin,
        authUid: staff.authUid,
      );
      try {
        await _firestoreService.updateStaff(updatedStaff);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Staff status updated successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update status: $e')),
          );
        }
      }
    }
  }

  void _showAddStaffDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'cashier';
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Staff Member'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Temporary Password',
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(
                          value: 'cashier',
                          child: Text('Cashier'),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('Admin'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedRole = val);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                if (!isLoading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (nameController.text.trim().isEmpty ||
                              emailController.text.trim().isEmpty ||
                              passwordController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please fill all fields.'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => isLoading = true);
                          try {
                            await AuthService().createStaffAccount(
                              emailController.text,
                              passwordController.text,
                              Staff(
                                id: '',
                                name: nameController.text.trim(),
                                role: selectedRole.toLowerCase(),
                                email: emailController.text.trim(),
                              ),
                            );
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Staff member created.'),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          } finally {
                            if (context.mounted) {
                              setDialogState(() => isLoading = false);
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditStaffDialog(Staff staff) {
    final nameController = TextEditingController(text: staff.name);
    final normalizedRole =
        staff.role.trim().toLowerCase() == 'admin' ? 'admin' : 'cashier';
    String selectedRole = normalizedRole;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Staff Member'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: TextEditingController(text: staff.email),
                      decoration: const InputDecoration(labelText: 'Email'),
                      enabled: false,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(
                          value: 'cashier',
                          child: Text('Cashier'),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('Admin'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedRole = val);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                if (!isLoading)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a name.'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => isLoading = true);
                          try {
                            final updatedStaff = Staff(
                              id: staff.id,
                              name: nameController.text.trim(),
                              role: selectedRole.toLowerCase(),
                              email: staff.email,
                              active: staff.active,
                              pin: staff.pin,
                              authUid: staff.authUid,
                            );
                            await _firestoreService.updateStaff(updatedStaff);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Staff member updated.'),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          } finally {
                            if (context.mounted) {
                              setDialogState(() => isLoading = false);
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPrinterSection() {
    if (kIsWeb) {
      return Card(
        color: Colors.white.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: AppTheme.secondaryColor.withValues(alpha: 0.2),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.print_disabled,
                color: AppTheme.secondaryColor,
                size: 28,
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receipt Printing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Bluetooth thermal receipt printing is only available on the Android POS app. This web portal is configured for store management, staff administration, and reports.',
                      style: TextStyle(
                        color: AppTheme.secondaryColor,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Printer',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_printerConnected ? 'Connected' : 'Not connected'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _scanning ? null : _scanPrinters,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(
                _scanning ? 'Scanning...' : 'Scan Bluetooth Printers',
              ),
            ),
            TextField(
              controller: _shopNameController,
              decoration: const InputDecoration(labelText: 'Shop name'),
            ),
            TextField(
              controller: _addressPhoneController,
              decoration: const InputDecoration(labelText: 'Address / phone'),
            ),
            TextField(
              controller: _footerController,
              decoration: const InputDecoration(labelText: 'Footer message'),
            ),
            DropdownButton<PaperSize>(
              value: _paperSize,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: PaperSize.mm58,
                  child: Text('Paper width: 58mm'),
                ),
                DropdownMenuItem(
                  value: PaperSize.mm80,
                  child: Text('Paper width: 80mm'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _paperSize = value ?? PaperSize.mm58),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _savePrinterSettings,
                icon: const Icon(Icons.save),
                label: const Text('Save printer settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedSale(FailedSaleRecord record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'KSh ${record.sale.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.sync, color: AppTheme.primaryColor),
                  tooltip: 'Retry sync',
                  onPressed: () => _retry(record),
                ),
              ],
            ),
            Text(
              'Sale: ${record.sale.id}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Failed: ${record.failedAt.toLocal()}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Error: ${record.errorMessage}',
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
            Text(
              '${record.sale.lineItems.length} line item(s), paid via ${record.sale.paymentMethod}',
              style: TextStyle(
                color: AppTheme.secondaryColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
