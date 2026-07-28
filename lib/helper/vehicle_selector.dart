import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

class VehicleSelector extends StatefulWidget {
  final Map<String, dynamic>? selectedVehicle;
  final Function(Map<String, dynamic>) onVehicleSelected;

  const VehicleSelector({
    super.key,
    this.selectedVehicle,
    required this.onVehicleSelected,
  });

  @override
  State<VehicleSelector> createState() => _VehicleSelectorState();
}

class _VehicleSelectorState extends State<VehicleSelector> {
  Map<String, dynamic>? _selectedVehicle;

  // Updated vehicle list with new names and pricing
  final List<Map<String, dynamic>> _vehicles = [
    {
      'id': 'scooter',
      'name': 'Scooter',
      'description': 'Up to 20kg',
      'icon': Icons.two_wheeler,
      'basePrice': 50, // Base price per km
      'capacity': '20kg',
    },
    {
      'id': 'two_wheeler',
      'name': '2 Wheeler',
      'description': 'Up to 20kg',
      'icon': Icons.motorcycle,
      'basePrice': 50, // Same as scooter
      'capacity': '20kg',
    },
    {
      'id': 'mini_3_wheeler',
      'name': 'Mini 3 Wheeler',
      'description': 'Up to 90kg',
      'icon': Icons.electric_rickshaw,
      'basePrice': 136,
      'capacity': '90kg',
    },
    {
      'id': 'e_loader',
      'name': 'E-loader',
      'description': 'Up to 300kg',
      'icon': Icons.electric_car,
      'basePrice': 160,
      'capacity': '300kg',
    },
    {
      'id': 'three_wheeler',
      'name': '3 Wheeler',
      'description': 'Up to 500kg',
      'icon': Icons.airport_shuttle,
      'basePrice': 230,
      'capacity': '500kg',
    },
    {
      'id': 'tata_ace',
      'name': 'Tata Ace',
      'description': 'Up to 800kg',
      'icon': Icons.local_shipping,
      'basePrice': 320,
      'capacity': '800kg',
    },
    {
      'id': 'pickup',
      'name': 'Pickup',
      'description': 'Up to 1500kg',
      'icon': Icons.fire_truck,
      'basePrice': 320,
      'capacity': '1500kg',
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedVehicle = widget.selectedVehicle;
  }

  void _selectVehicle(Map<String, dynamic> vehicle) {
    setState(() {
      _selectedVehicle = vehicle;
    });
    widget.onVehicleSelected(vehicle);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Vehicle Type',
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
            childAspectRatio: 1.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _vehicles.length,
          itemBuilder: (context, index) {
            final vehicle = _vehicles[index];
            final isSelected = _selectedVehicle?['id'] == vehicle['id'];
            
            return GestureDetector(
              onTap: () => _selectVehicle(vehicle),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? AppColor.themeColor.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColor.themeColor : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      vehicle['icon'],
                      size: 32,
                      color: isSelected ? AppColor.themeColor : Colors.grey.shade600,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      vehicle['name'],
                      style: TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? AppColor.themeColor : Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vehicle['description'],
                      style: TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected 
                          ? AppColor.themeColor.withOpacity(0.2)
                          : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '₹${vehicle['basePrice']}/km',
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? AppColor.themeColor : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        
        if (_selectedVehicle != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColor.themeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColor.themeColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  _selectedVehicle!['icon'],
                  color: AppColor.themeColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_selectedVehicle!['name']} - ${_selectedVehicle!['capacity']}',
                        style: const TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        'Base Rate: ₹${_selectedVehicle!['basePrice']}/km',
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
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
