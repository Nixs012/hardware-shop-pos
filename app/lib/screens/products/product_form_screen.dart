import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/product.dart';
import '../../services/firestore_service.dart';
import '../../utils/theme.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? existingProduct;

  const ProductFormScreen({super.key, this.existingProduct});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  late final TextEditingController _nameController;
  late final TextEditingController _skuController;
  late final TextEditingController _categoryController;
  late final TextEditingController _costPriceController;
  late final TextEditingController _sellingPriceController;
  late final TextEditingController _quantityController;
  late final TextEditingController _lowStockController;
  late final TextEditingController _unitController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    _nameController = TextEditingController(text: p?.name ?? '');
    _skuController = TextEditingController(text: p?.sku ?? '');
    _categoryController = TextEditingController(text: p?.category ?? '');
    _costPriceController = TextEditingController(text: p?.costPrice.toString() ?? '');
    _sellingPriceController = TextEditingController(text: p?.sellingPrice.toString() ?? '');
    _quantityController = TextEditingController(text: p?.quantityOnHand.toString() ?? '0');
    _lowStockController = TextEditingController(text: p?.lowStockThreshold.toString() ?? '5');
    _unitController = TextEditingController(text: p?.unit ?? 'pcs');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _categoryController.dispose();
    _costPriceController.dispose();
    _sellingPriceController.dispose();
    _quantityController.dispose();
    _lowStockController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final product = Product(
        id: widget.existingProduct?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        sku: _skuController.text.trim(),
        category: _categoryController.text.trim(),
        costPrice: double.parse(_costPriceController.text.trim()),
        sellingPrice: double.parse(_sellingPriceController.text.trim()),
        quantityOnHand: double.parse(_quantityController.text.trim()),
        lowStockThreshold: double.parse(_lowStockController.text.trim()),
        unit: _unitController.text.trim(),
        costPriceEstimated: widget.existingProduct?.costPriceEstimated ?? false,
      );

      if (widget.existingProduct == null) {
        await _firestoreService.addProduct(product);
      } else {
        await _firestoreService.updateProduct(product);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving product: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingProduct == null ? 'Add Product' : 'Edit Product'),
        backgroundColor: AppTheme.backgroundColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildTextField('Name', _nameController, required: true),
              const SizedBox(height: 16),
              _buildTextField('SKU', _skuController, required: true),
              const SizedBox(height: 16),
              _buildTextField('Category', _categoryController, required: true),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      'Cost Price',
                      _costPriceController,
                      isNumeric: true,
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      'Selling Price',
                      _sellingPriceController,
                      isNumeric: true,
                      required: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      'Quantity on Hand',
                      _quantityController,
                      isNumeric: true,
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      'Unit (e.g. pcs, kg)',
                      _unitController,
                      required: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                'Low Stock Threshold',
                _lowStockController,
                isNumeric: true,
                required: true,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProduct,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Save Product', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label, 
    TextEditingController controller, {
    bool isNumeric = false,
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.secondaryColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.secondaryColor),
        ),
      ),
      style: const TextStyle(color: Colors.white),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'This field is required';
        }
        if (isNumeric && value != null && value.isNotEmpty) {
          if (double.tryParse(value) == null) {
            return 'Must be a valid number';
          }
        }
        return null;
      },
    );
  }
}
