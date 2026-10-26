import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' show PaperSize;
import 'package:app/services/printer_service.dart';
import 'package:app/utils/theme.dart';

/// First-run setup screen.
///
/// Collects the essential shop configuration (shop name, address/phone,
/// receipt footer, and printer paper size) that is required before the POS
/// can be used. On first launch the [AppGate] checks
/// `PrinterService.isFirstRunCompleted()`; if false, this screen is shown
/// instead of the auth gate. Once the setup is saved, first-run is marked
/// complete and the user is routed to normal auth/login.
class FirstRunSetupScreen extends StatefulWidget {
  const FirstRunSetupScreen({super.key});

  @override
  State<FirstRunSetupScreen> createState() => _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends State<FirstRunSetupScreen> {
  final _printerService = PrinterService();
  final _shopNameController = TextEditingController();
  final _addressPhoneController = TextEditingController();
  final _footerController = TextEditingController();
  PaperSize _paperSize = PaperSize.mm58;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
    // Smart defaults on first boot
    _footerController.text = 'Thank you for your business!';
  }

  Future<void> _loadExisting() async {
    if (kIsWeb) {
      setState(() {});
      return;
    }
    _shopNameController.text = await _printerService.getShopName();
    _addressPhoneController.text = await _printerService.getAddressPhone();
    final footer = await _printerService.getFooterMessage();
    if (footer.isNotEmpty) _footerController.text = footer;
    _paperSize = await _printerService.getPaperSize();
    setState(() {});
  }

  Future<void> _saveSetup() async {
    final shopName = _shopNameController.text.trim();
    if (shopName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shop name is required.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _printerService.saveReceiptSettings(
        shopName: shopName,
        addressPhone: _addressPhoneController.text.trim(),
        footerMessage: _footerController.text.trim().isEmpty
            ? 'Thank you!'
            : _footerController.text.trim(),
      );
      await _printerService.setPaperSize(_paperSize);
      await _printerService.setFirstRunCompleted();

      if (!mounted) return;
      // Pop the entire setup route. The AppGate on the stack below will
      // re-check `isFirstRunCompleted()` (now true) and route to
      // auth/login normally.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _addressPhoneController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              color: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.store_mall_directory,
                      color: AppTheme.primaryColor,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Welcome to Shamamo POS',
                      textAlign: TextAlign.center,
style: TextStyle(color: AppTheme.textPrimary,
                        fontSize: screenHeight < 500 ? 22 : 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Let’s set up your shop. You can change these later in Settings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      'Shop Name',
                      _shopNameController,
                      'e.g. Shamamo Hardware',
                      Icons.store,
                      TextInputType.text,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      'Address & Phone',
                      _addressPhoneController,
                      '123 Main St, Nairobi • 0700123456',
                      Icons.edit,
                      TextInputType.multiline,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      'Receipt Footer Message',
                      _footerController,
                      'Thank you for your business!',
                      Icons.receipt_long,
                      TextInputType.text,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<PaperSize>(
                      initialValue: _paperSize,
                      dropdownColor: AppTheme.surfaceColor,
                      decoration: InputDecoration(
                        labelText: 'Printer Paper Size',
                        prefixIcon: const Icon(
                          Icons.print,
                          color: AppTheme.primaryColor,
                        ),
                        border: const OutlineInputBorder(),
                        labelStyle: const TextStyle(
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: PaperSize.mm58,
                          child: Text('58mm / 2 inch'),
                        ),
                        DropdownMenuItem(
                          value: PaperSize.mm80,
                          child: Text('80mm / 3 inch'),
                        ),
                      ],
                      onChanged: kIsWeb
                          ? null
                          : (PaperSize? v) {
                              if (v != null) setState(() => _paperSize = v);
                            },
                    ),
                    const SizedBox(height: 28),
                    _saving
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton.icon(
                            onPressed: _saveSetup,
                            icon: const Icon(Icons.check, color: AppTheme.textPrimary),
                            label: const Text(
                              'Complete Setup',
                              style: TextStyle(color: AppTheme.textPrimary,                                 fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint,
    IconData icon,
    TextInputType keyboardType, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.secondaryColor),
        prefixIcon: Icon(icon, color: AppTheme.primaryColor),
        border: const OutlineInputBorder(),
        labelStyle: const TextStyle(color: AppTheme.secondaryColor),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: AppTheme.secondaryColor.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.primaryColor),
        ),
      ),
    );
  }
}



