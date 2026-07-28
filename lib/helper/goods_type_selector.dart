import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

class GoodsTypeSelector extends StatefulWidget {
  final String? selectedGoodsType;
  final Function(String) onGoodsTypeSelected;

  const GoodsTypeSelector({
    super.key,
    this.selectedGoodsType,
    required this.onGoodsTypeSelected,
  });

  @override
  State<GoodsTypeSelector> createState() => _GoodsTypeSelectorState();
}

class _GoodsTypeSelectorState extends State<GoodsTypeSelector> {
  String? _selectedType;

  final List<Map<String, dynamic>> _goodsTypes = [
    {
      'id': 'electronics',
      'name': 'Electronics',
      'icon': Icons.devices,
      'description': 'Mobile, laptop, TV, appliances'
    },
    {
      'id': 'furniture',
      'name': 'Furniture',
      'icon': Icons.chair,
      'description': 'Chair, table, bed, sofa'
    },
    {
      'id': 'documents',
      'name': 'Documents',
      'icon': Icons.description,
      'description': 'Papers, certificates, files'
    },
    {
      'id': 'food',
      'name': 'Food & Groceries',
      'icon': Icons.local_grocery_store,
      'description': 'Groceries, cooked food, sweets'
    },
    {
      'id': 'clothing',
      'name': 'Clothing',
      'icon': Icons.checkroom,
      'description': 'Clothes, shoes, accessories'
    },
    {
      'id': 'books',
      'name': 'Books & Stationery',
      'icon': Icons.menu_book,
      'description': 'Books, notebooks, office supplies'
    },
    {
      'id': 'household',
      'name': 'Household Items',
      'icon': Icons.home,
      'description': 'Kitchen items, decorations, tools'
    },
    {
      'id': 'fragile',
      'name': 'Fragile Items',
      'icon': Icons.warning,
      'description': 'Glass, ceramics, delicate items'
    },
    {
      'id': 'medicines',
      'name': 'Medicines',
      'icon': Icons.medical_services,
      'description': 'Prescription drugs, medical supplies'
    },
    {
      'id': 'other',
      'name': 'Other',
      'icon': Icons.inventory,
      'description': 'General items, miscellaneous'
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedType = widget.selectedGoodsType;
  }

  void _selectGoodsType(String typeId) {
    setState(() {
      _selectedType = typeId;
    });
    widget.onGoodsTypeSelected(typeId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Goods Type',
          style: TextStyle(
            fontFamily: AppFont.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 3.5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _goodsTypes.length,
          itemBuilder: (context, index) {
            final goodsType = _goodsTypes[index];
            final isSelected = _selectedType == goodsType['id'];
            
            return GestureDetector(
              onTap: () => _selectGoodsType(goodsType['id']),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? AppColor.themeColor.withOpacity(0.1) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppColor.themeColor : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      goodsType['icon'],
                      color: isSelected ? AppColor.themeColor : Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        goodsType['name'],
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? AppColor.themeColor : Colors.grey.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        
        if (_selectedType != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue.shade600,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _goodsTypes.firstWhere((type) => type['id'] == _selectedType)['description'],
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 12,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
