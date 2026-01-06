import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../firestore_service.dart';
import 'staffs_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // Items management
  final List<ItemData> _items = [ItemData()];

  // Vendors management
  final List<VendorData> _vendors = [VendorData()];

  // Expenses management
  final List<ExpenseData> _expenses = [ExpenseData()];

  bool _isLoading = true;
  bool _isSaving = false;

  // Special pricing
  final Set<String> _specialPricingVendors = <String>{};
  final Map<String, Map<String, double>> _specialPrices =
      <String, Map<String, double>>{}; // vendor -> { itemCode: specialPrice }

  @override
  void initState() {
    super.initState();
    _loadExistingConfig();
  }

  Future<void> _loadExistingConfig() async {
    final config = await FirestoreService.getUserConfig();

    if (config != null && mounted) {
      setState(() {
        // Load business name
        if (config['business_name'] != null) {
          _businessNameController.text = config['business_name'] as String;
        }

        // Load address
        if (config['address'] != null) {
          _addressController.text = config['address'] as String;
        }

        // Load email
        if (config['email'] != null) {
          _emailController.text = config['email'] as String;
        }

        // Load phone
        if (config['phone'] != null) {
          _phoneController.text = config['phone'] as String;
        }

        // Load items
        final items = config['items'] as List<dynamic>?;
        if (items != null && items.isNotEmpty) {
          _items.clear();
          for (var item in items) {
            final itemData = ItemData();
            itemData.nameController.text = item['name'] ?? '';
            itemData.codeController.text = item['code'] ?? '';
            itemData.costController.text = item['price']?.toString() ?? '';
            _items.add(itemData);
          }
        }

        // Load vendors
        final vendors = config['vendors'] as List<dynamic>?;
        if (vendors != null && vendors.isNotEmpty) {
          _vendors.clear();
          for (var vendor in vendors) {
            final vendorData = VendorData();
            vendorData.nameController.text = vendor;
            _vendors.add(vendorData);
          }
        }

        // Load expenses
        final expenses = config['expenses'] as List<dynamic>?;
        if (expenses != null && expenses.isNotEmpty) {
          _expenses.clear();
          for (var expense in expenses) {
            final expenseData = ExpenseData();
            expenseData.nameController.text = expense;
            _expenses.add(expenseData);
          }
        }

        // Load special pricing vendors
        final spVendors =
            config['special_pricing_vendors'] as List<dynamic>? ??
            const <dynamic>[];
        _specialPricingVendors
          ..clear()
          ..addAll(spVendors.map((e) => e.toString()));

        // Load special prices map
        final spPrices =
            (config['special_prices'] as Map<String, dynamic>?) ?? {};
        _specialPrices.clear();
        spPrices.forEach((vendor, pricesMap) {
          if (pricesMap is Map<String, dynamic>) {
            final Map<String, double> parsed = {};
            pricesMap.forEach((code, value) {
              if (value is num) {
                parsed[code] = value.toDouble();
              } else if (value is String) {
                final v = double.tryParse(value);
                if (v != null) parsed[code] = v;
              }
            });
            _specialPrices[vendor] = parsed;
          }
        });

        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    for (var item in _items) {
      item.nameController.dispose();
      item.codeController.dispose();
      item.costController.dispose();
    }
    for (var vendor in _vendors) {
      vendor.nameController.dispose();
    }
    for (var expense in _expenses) {
      expense.nameController.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(() {
      _items.add(ItemData());
    });
  }

  void _removeItem(int index) {
    if (_items.length > 1) {
      setState(() {
        _items[index].nameController.dispose();
        _items[index].codeController.dispose();
        _items[index].costController.dispose();
        _items.removeAt(index);
      });
    }
  }

  void _addVendor() {
    setState(() {
      _vendors.add(VendorData());
    });
  }

  void _removeVendor(int index) {
    if (_vendors.length > 1) {
      setState(() {
        _vendors[index].nameController.dispose();
        _vendors.removeAt(index);
      });
    }
  }

  Map<String, double> _buildNormalPriceByCode() {
    final Map<String, double> byCode = {};
    for (final item in _items) {
      final code = item.codeController.text.trim();
      final price = double.tryParse(item.costController.text.trim()) ?? 0.0;
      if (code.isNotEmpty) byCode[code] = price;
    }
    return byCode;
  }

  Future<void> _showViewSpecialPrices(String vendorName) async {
    final Map<String, double> normalByCode = _buildNormalPriceByCode();
    final Map<String, double> vendorSpecial =
        _specialPrices[vendorName] ?? const <String, double>{};

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Special prices - $vendorName',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 420,
            child: vendorSpecial.isEmpty
                ? Text(
                    'No special prices set',
                    style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: vendorSpecial.entries.map((e) {
                        final code = e.key;
                        final sp = e.value;
                        final normal = normalByCode[code] ?? 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Item: $code',
                                  style: GoogleFonts.quicksand(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                'Normal: $normal  |  Special: $sp',
                                style: GoogleFonts.quicksand(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditSpecialPrices(String vendorName) async {
    final Map<String, double> normalByCode = _buildNormalPriceByCode();
    final Map<String, double> existing = Map<String, double>.from(
      _specialPrices[vendorName] ?? {},
    );

    final Map<String, TextEditingController> controllers = {};
    for (final code in normalByCode.keys) {
      final c = TextEditingController();
      final current = existing[code];
      if (current != null) {
        c.text = current.toString();
      }
      controllers[code] = c;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Edit special prices - $vendorName',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: normalByCode.keys.map((code) {
                  final normal = normalByCode[code] ?? 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$code  (Normal: $normal)',
                            style: GoogleFonts.quicksand(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: controllers[code],
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'Special price',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final Map<String, double> next = {};
                controllers.forEach((code, c) {
                  final txt = c.text.trim();
                  if (txt.isNotEmpty) {
                    final v = double.tryParse(txt);
                    if (v != null) {
                      next[code] = v;
                    }
                  }
                });

                final success =
                    await FirestoreService.upsertVendorSpecialPrices(
                      vendorName,
                      next,
                    );
                if (success && mounted) {
                  setState(() {
                    if (next.isEmpty) {
                      _specialPrices.remove(vendorName);
                      _specialPricingVendors.remove(vendorName);
                    } else {
                      _specialPrices[vendorName] = next;
                      _specialPricingVendors.add(vendorName);
                    }
                  });
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Special prices updated',
                        style: GoogleFonts.quicksand(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: const Color(0xFF4CAF50),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Failed to update special prices',
                        style: GoogleFonts.quicksand(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteSpecialPrices(String vendorName) async {
    final bool hasAny = (_specialPrices[vendorName] ?? {}).isNotEmpty;
    if (!hasAny) {
      // Nothing to delete, but still provide feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No special prices to delete for $vendorName',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w600),
          ),
        ),
      );
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete special prices?',
          style: GoogleFonts.quicksand(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will remove all special prices for "$vendorName".',
          style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    final ok = await FirestoreService.upsertVendorSpecialPrices(
      vendorName,
      const <String, double>{},
    );
    if (!mounted) return;

    if (ok) {
      setState(() {
        _specialPrices.remove(vendorName);
        _specialPricingVendors.remove(vendorName);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Special prices deleted',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to delete special prices',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _addExpense() {
    setState(() {
      _expenses.add(ExpenseData());
    });
  }

  void _removeExpense(int index) {
    if (_expenses.length > 1) {
      setState(() {
        _expenses[index].nameController.dispose();
        _expenses.removeAt(index);
      });
    }
  }

  bool _validateConfig() {
    // Check business name
    if (_businessNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter a business name',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    // Check at least one item with all fields filled and no duplicate codes
    bool hasValidItem = false;
    final List<String> itemCodes = [];

    for (var item in _items) {
      final code = item.codeController.text.trim();

      if (item.nameController.text.trim().isNotEmpty &&
          code.isNotEmpty &&
          item.costController.text.trim().isNotEmpty) {
        hasValidItem = true;

        // Check for duplicate codes (case-insensitive)
        final codeLower = code.toLowerCase();
        if (itemCodes.contains(codeLower)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Duplicate item code "$code" found. Each item must have a unique code.',
                style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
          return false;
        }
        itemCodes.add(codeLower);
      }
    }

    if (!hasValidItem) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please add at least one complete item (name, code, and cost)',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    // Check at least one vendor and no duplicates
    bool hasValidVendor = false;
    final List<String> vendorNames = [];

    for (var vendor in _vendors) {
      final name = vendor.nameController.text.trim();

      if (name.isNotEmpty) {
        hasValidVendor = true;

        // Check for duplicate vendor names (case-insensitive)
        final nameLower = name.toLowerCase();
        if (vendorNames.contains(nameLower)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Duplicate vendor "$name" found. Each vendor must have a unique name.',
                style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
          return false;
        }
        vendorNames.add(nameLower);
      }
    }

    if (!hasValidVendor) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please add at least one vendor',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    // Check at least one expense and no duplicates
    bool hasValidExpense = false;
    final List<String> expenseNames = [];

    for (var expense in _expenses) {
      final name = expense.nameController.text.trim();

      if (name.isNotEmpty) {
        hasValidExpense = true;

        // Check for duplicate expense names (case-insensitive)
        final nameLower = name.toLowerCase();
        if (expenseNames.contains(nameLower)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Duplicate expense "$name" found. Each expense must have a unique name.',
                style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
          return false;
        }
        expenseNames.add(nameLower);
      }
    }

    if (!hasValidExpense) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please add at least one expense',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    return true;
  }

  Future<void> _saveConfig() async {
    if (!_validateConfig()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Prepare items data (only include complete items)
      final items = <Map<String, dynamic>>[];
      for (var item in _items) {
        if (item.nameController.text.trim().isNotEmpty &&
            item.codeController.text.trim().isNotEmpty &&
            item.costController.text.trim().isNotEmpty) {
          items.add({
            'name': item.nameController.text.trim(),
            'code': item.codeController.text.trim(),
            'price': double.tryParse(item.costController.text.trim()) ?? 0.0,
          });
        }
      }

      // Prepare vendors data (only include non-empty vendors)
      final vendors = <String>[];
      for (var vendor in _vendors) {
        if (vendor.nameController.text.trim().isNotEmpty) {
          vendors.add(vendor.nameController.text.trim());
        }
      }

      // Prepare expenses data (only include non-empty expenses)
      final expenses = <String>[];
      for (var expense in _expenses) {
        if (expense.nameController.text.trim().isNotEmpty) {
          expenses.add(expense.nameController.text.trim());
        }
      }

      // Save to Firestore
      final success = await FirestoreService.saveUserConfig(
        businessName: _businessNameController.text.trim(),
        address: _addressController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        items: items,
        vendors: vendors,
        expenses: expenses,
      );

      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        if (success) {
          // Debug: Print config fields to help with testing
          await FirestoreService.debugPrintConfigFields();

          // Distribute vendors to staff documents
          final vendorDistributionSuccess =
              await FirestoreService.distributeVendorsToStaff(vendors);

          // Prepare items data (code mapped to name)
          final itemMaps = <Map<String, String>>[];
          for (var item in _items) {
            if (item.nameController.text.trim().isNotEmpty &&
                item.codeController.text.trim().isNotEmpty &&
                item.costController.text.trim().isNotEmpty) {
              itemMaps.add({
                item.codeController.text.trim(): item.nameController.text
                    .trim(),
              });
            }
          }

          // Distribute items to staff documents
          final itemDistributionSuccess =
              await FirestoreService.distributeItemsToStaff(itemMaps);

          if (vendorDistributionSuccess && itemDistributionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Configuration saved and data distributed to staff successfully!',
                  style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
                ),
                backgroundColor: const Color(0xFF4CAF50),
              ),
            );
          } else if (vendorDistributionSuccess && !itemDistributionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Configuration saved and vendors distributed, but failed to distribute items to staff.',
                  style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
                ),
                backgroundColor: Colors.orange,
              ),
            );
          } else if (!vendorDistributionSuccess && itemDistributionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Configuration saved and items distributed, but failed to distribute vendors to staff.',
                  style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
                ),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Configuration saved, but failed to distribute data to staff.',
                  style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }

          // Reload config to confirm
          await _loadExistingConfig();

          // Return true to indicate config was saved
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to save configuration. Please try again.',
                style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString()}',
              style: GoogleFonts.quicksand(fontWeight: FontWeight.w500),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.quicksand(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: size.height * 0.025),

                    // Business name section
                    Text(
                      'Business name:-',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _businessNameController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFE9E9E9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Address section
                    Text(
                      'Address:-',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _addressController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFE9E9E9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Email section
                    Text(
                      'Email:-',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFE9E9E9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Phone section
                    Text(
                      'Phone:-',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFE9E9E9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      style: GoogleFonts.quicksand(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Items section
                    Text(
                      'Items:-',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_items.length, (index) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index + 1}:-',
                            style: GoogleFonts.quicksand(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Name:-',
                                      style: GoogleFonts.quicksand(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: _items[index].nameController,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: const Color(0xFFE9E9E9),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                      ),
                                      style: GoogleFonts.quicksand(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Code:-',
                                      style: GoogleFonts.quicksand(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: _items[index].codeController,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: const Color(0xFFE9E9E9),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                      ),
                                      style: GoogleFonts.quicksand(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Cost:-',
                                      style: GoogleFonts.quicksand(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: _items[index].costController,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: const Color(0xFFE9E9E9),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                      ),
                                      style: GoogleFonts.quicksand(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_items.length > 1) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () => _removeItem(index),
                                  icon: const Icon(
                                    Icons.remove_circle,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _addItem,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE9E9E9),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Add more',
                          style: GoogleFonts.quicksand(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Vendors section
                    Text(
                      'Vendors:-',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_vendors.length, (index) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Name:-',
                                      style: GoogleFonts.quicksand(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller:
                                                _vendors[index].nameController,
                                            decoration: InputDecoration(
                                              filled: true,
                                              fillColor: const Color(
                                                0xFFE9E9E9,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: BorderSide.none,
                                              ),
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                            ),
                                            style: GoogleFonts.quicksand(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Builder(
                                          builder: (context) {
                                            final name = _vendors[index]
                                                .nameController
                                                .text
                                                .trim();
                                            final hasSpecial =
                                                name.isNotEmpty &&
                                                _specialPricingVendors.contains(
                                                  name,
                                                );
                                            return Row(
                                              children: [
                                                if (hasSpecial)
                                                  const Icon(
                                                    Icons.info_outline,
                                                    color: Colors.blueAccent,
                                                  ),
                                                const SizedBox(width: 4),
                                                PopupMenuButton<String>(
                                                  icon: const Icon(
                                                    Icons.more_vert,
                                                  ),
                                                  onSelected: (value) {
                                                    if (value == 'view') {
                                                      _showViewSpecialPrices(
                                                        name,
                                                      );
                                                    } else if (value ==
                                                        'edit') {
                                                      _showEditSpecialPrices(
                                                        name,
                                                      );
                                                    } else if (value ==
                                                        'delete') {
                                                      _confirmDeleteSpecialPrices(
                                                        name,
                                                      );
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    const PopupMenuItem(
                                                      value: 'view',
                                                      child: Text(
                                                        'View special prices',
                                                      ),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'edit',
                                                      child: Text(
                                                        'Edit special prices',
                                                      ),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text(
                                                        'Delete special prices',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (_vendors.length > 1) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () => _removeVendor(index),
                                  icon: const Icon(
                                    Icons.remove_circle,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _addVendor,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE9E9E9),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Add more',
                          style: GoogleFonts.quicksand(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Expenses section
                    Text(
                      'Expenses:-',
                      style: GoogleFonts.quicksand(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_expenses.length, (index) {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Name:-',
                                      style: GoogleFonts.quicksand(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller:
                                          _expenses[index].nameController,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: const Color(0xFFE9E9E9),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                      ),
                                      style: GoogleFonts.quicksand(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_expenses.length > 1) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () => _removeExpense(index),
                                  icon: const Icon(
                                    Icons.remove_circle,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _addExpense,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE9E9E9),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Add more',
                          style: GoogleFonts.quicksand(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Save Config button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveConfig,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE9E9E9),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.black,
                                  ),
                                ),
                              )
                            : const Icon(Icons.save, size: 20),
                        label: Text(
                          _isSaving ? 'Saving...' : 'Save Config',
                          style: GoogleFonts.quicksand(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Staff Management button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const StaffsScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6A5AE0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.people, size: 20),
                        label: Text(
                          'Manage Staff',
                          style: GoogleFonts.quicksand(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}

// Data classes for managing form data
class ItemData {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  final TextEditingController costController = TextEditingController();
}

class VendorData {
  final TextEditingController nameController = TextEditingController();
}

class ExpenseData {
  final TextEditingController nameController = TextEditingController();
}
