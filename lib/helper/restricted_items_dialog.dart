import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

class RestrictedItemsDialog extends StatelessWidget {
  const RestrictedItemsDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) => const RestrictedItemsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning,
                  color: Colors.red,
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Restricted Items',
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            const Text(
              'The following items are prohibited for transport:',
              style: TextStyle(
                fontFamily: AppFont.fontFamily,
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildRestrictedCategory(
                      'Hazardous Materials',
                      Icons.dangerous,
                      [
                        'Explosives, fireworks, ammunition',
                        'Flammable liquids (petrol, kerosene, alcohol)',
                        'Compressed gases, gas cylinders',
                        'Corrosive substances (acids, batteries)',
                        'Toxic chemicals, pesticides',
                        'Radioactive materials',
                      ],
                    ),
                    
                    _buildRestrictedCategory(
                      'Illegal Items',
                      Icons.gavel,
                      [
                        'Narcotics, drugs, cannabis',
                        'Stolen goods, counterfeit items',
                        'Weapons, knives, firearms',
                        'Pornographic material',
                        'Items violating intellectual property',
                      ],
                    ),
                    
                    _buildRestrictedCategory(
                      'Valuable Items',
                      Icons.diamond,
                      [
                        'Cash, coins, currency notes',
                        'Jewelry, gold, precious metals',
                        'Important documents (passports, etc.)',
                        'Blank checks, credit cards',
                        'Antiques, artwork, collectibles',
                      ],
                    ),
                    
                    _buildRestrictedCategory(
                      'Perishable & Living',
                      Icons.eco,
                      [
                        'Live animals, pets, birds',
                        'Plants, seeds, flowers',
                        'Perishable food without proper packaging',
                        'Human remains, ashes',
                        'Blood samples, biological materials',
                      ],
                    ),
                    
                    _buildRestrictedCategory(
                      'Fragile & Special',
                      Icons.warning_amber,
                      [
                        'Items over vehicle weight limit',
                        'Oversized items that don\'t fit',
                        'Wet or leaking packages',
                        'Items with strong odors',
                        'Temperature-sensitive medicines',
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange.shade700,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Transporting restricted items may result in booking cancellation, legal action, and account suspension.',
                      style: TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontSize: 12,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColor.themeColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'I Understand',
                  style: TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestrictedCategory(String title, IconData icon, List<String> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Colors.red.shade600,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: TextStyle(
                    fontFamily: AppFont.fontFamily,
                    fontSize: 12,
                    color: Colors.red.shade600,
                  ),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 12,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }
}

// Widget to show restricted items link
class RestrictedItemsLink extends StatelessWidget {
  const RestrictedItemsLink({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => RestrictedItemsDialog.show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning,
              color: Colors.red.shade600,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'View Restricted Items List',
                style: TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.red.shade700,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.red.shade600,
              size: 12,
            ),
          ],
        ),
      ),
    );
  }
}
