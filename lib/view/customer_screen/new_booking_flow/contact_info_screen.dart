import 'package:flutter/material.dart';
import 'package:movigo/utilities/phone_number_formatter.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'new_confirm_screen.dart';
import 'package:movigo/helper/contacts_permission_helper.dart';

class ContactInfoScreen extends StatefulWidget {
  final String vehicleTypeId;
  final String subVehicleTypeId;
  final Map<String, dynamic> vehicleData;
  final Map<String, dynamic> pickupData;
  final Map<String, dynamic> dropData;
  final double rawDistanceKm;
  final int estimatedFare;
  final List<dynamic> subVehicleTypeList;
  final String bookingType;
  final String pickupDate;
  final String pickupSlot;
  final String dropContactName;
  final String dropContactPhone;
  final List<Map<String, dynamic>> extraStops;

  const ContactInfoScreen({
    super.key,
    required this.vehicleTypeId,
    required this.subVehicleTypeId,
    required this.vehicleData,
    required this.pickupData,
    required this.dropData,
    required this.rawDistanceKm,
    required this.estimatedFare,
    required this.subVehicleTypeList,
    required this.bookingType,
    required this.pickupDate,
    required this.pickupSlot,
    this.dropContactName  = '',
    this.dropContactPhone = '',
    this.extraStops = const [],
  });

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

// One step in the pickup → stop(s) → drop wizard: the fixed map, the
// address, and the contact form that belong to a single location.
class _LocationStep {
  final String title;
  final Color accentColor;
  final LatLng? latLng;
  final String address;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController? houseController;
  final TextEditingController? landmarkController;
  final TextEditingController? noteController;
  final String nameHint;
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  _LocationStep({
    required this.title,
    required this.accentColor,
    required this.latLng,
    required this.address,
    required this.nameController,
    required this.phoneController,
    this.houseController,
    this.landmarkController,
    this.noteController,
    required this.nameHint,
  });
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  final TextEditingController _pickupNameController = TextEditingController();
  final TextEditingController _pickupPhoneController = TextEditingController();
  final TextEditingController _pickupHouseController = TextEditingController();
  final TextEditingController _pickupLandmarkController = TextEditingController();
  final TextEditingController _pickupNoteController = TextEditingController();

  final TextEditingController _dropNameController = TextEditingController();
  final TextEditingController _dropPhoneController = TextEditingController();
  final TextEditingController _dropHouseController = TextEditingController();
  final TextEditingController _dropLandmarkController = TextEditingController();
  final TextEditingController _dropNoteController = TextEditingController();

  // Per-stop controllers (one pair per extra stop)
  late final List<TextEditingController> _stopNameControllers;
  late final List<TextEditingController> _stopPhoneControllers;

  late final List<_LocationStep> _steps;
  int _currentStepIndex = 0;

  // Localized texts
  static const _txtPickupHeader = ["Pickup Location (Sender)", "पिकअप स्थान (भेजने वाला)"];
  static const _txtDropHeader = ["Dropoff Location (Receiver)", "ड्रॉपऑफ़ स्थान (प्राप्तकर्ता)"];

  static const _txtNameLabel = ["Contact Name (Optional)", "संपर्क नाम (वैकल्पिक)"];
  static const _txtNameHintPickup = ["Enter sender name", "भेजने वाले का नाम दर्ज करें"];
  static const _txtNameHintDrop = ["Enter receiver name", "प्राप्तकर्ता का नाम दर्ज करें"];

  static const _txtPhoneLabel = ["Contact Mobile (Mandatory)", "संपर्क मोबाइल (अनिवार्य)"];
  static const _txtPhoneHint = ["Enter 10-digit mobile number", "10-अंकीय मोबाइल नंबर दर्ज करें"];

  static const _txtHouseLabel = ["House / Flat / Apartment No. (Optional)", "मकान / फ्लैट / अपार्टमेंट नंबर (वैकल्पिक)"];
  static const _txtHouseHint = ["Enter house/flat/building no.", "मकान/फ्लैट/भवन संख्या दर्ज करें"];

  static const _txtLandmarkLabel = ["Landmark (Optional)", "लैंडमार्क (वैकल्पिक)"];
  static const _txtLandmarkHint = ["E.g. Near City Temple", "जैसे: सिटी टेम्पल के पास"];

  static const _txtNoteLabel = ["Driver Note (Optional)", "ड्राइवर नोट (वैकल्पिक)"];
  static const _txtNoteHint = ["E.g. Ring doorbell / Call before arriving", "जैसे: डोरबेल बजाएं / पहुंचने से पहले कॉल करें"];

  static const _txtUseMyNumber = ["Use My Number", "मेरा नंबर उपयोग करें"];
  static const _txtSelectContact = ["Select Contact", "संपर्क से चुनें"];
  static const _txtNext = ["Next", "आगे"];
  static const _txtProceed = ["Proceed to Confirmation", "पुष्टि के लिए आगे बढ़ें"];

  static const _txtValPhoneEmpty = ["Please enter a mobile number", "कृपया एक मोबाइल नंबर दर्ज करें"];
  static const _txtValPhoneInvalid = ["Enter a valid 10-digit mobile number", "एक वैध 10-अंकीय मोबाइल नंबर दर्ज करें"];

  LatLng? _latLngFromMap(Map<String, dynamic> data) {
    final lat = data['lat'];
    final lng = data['lng'];
    if (lat == null || lng == null) return null;
    return LatLng((lat as num).toDouble(), (lng as num).toDouble());
  }

  @override
  void initState() {
    super.initState();
    final pickupContactName  = (widget.pickupData['contact_name']  ?? '').toString();
    final pickupContactPhone = (widget.pickupData['contact_phone'] ?? '').toString();
    if (pickupContactName.isNotEmpty)  _pickupNameController.text  = pickupContactName;
    if (pickupContactPhone.isNotEmpty) _pickupPhoneController.text = pickupContactPhone;
    if (widget.dropContactName.isNotEmpty)  _dropNameController.text  = widget.dropContactName;
    if (widget.dropContactPhone.isNotEmpty) _dropPhoneController.text = widget.dropContactPhone;

    _stopNameControllers  = widget.extraStops.map((s) => TextEditingController(text: s['contact_name']?.toString()  ?? '')).toList();
    _stopPhoneControllers = widget.extraStops.map((s) => TextEditingController(text: s['contact_phone']?.toString() ?? '')).toList();

    _steps = [
      _LocationStep(
        title: _txtPickupHeader[language],
        accentColor: AppColor.successCOlor,
        latLng: _latLngFromMap(widget.pickupData),
        address: (widget.pickupData['address'] ?? '').toString(),
        nameController: _pickupNameController,
        phoneController: _pickupPhoneController,
        houseController: _pickupHouseController,
        landmarkController: _pickupLandmarkController,
        noteController: _pickupNoteController,
        nameHint: _txtNameHintPickup[language],
      ),
      for (int i = 0; i < widget.extraStops.length; i++)
        _LocationStep(
          title: 'Stop ${i + 1} (Receiver)',
          accentColor: Colors.orange.shade700,
          latLng: _latLngFromMap(widget.extraStops[i]),
          address: (widget.extraStops[i]['address'] ?? '').toString(),
          nameController: _stopNameControllers[i],
          phoneController: _stopPhoneControllers[i],
          nameHint: _txtNameHintDrop[language],
        ),
      _LocationStep(
        title: widget.extraStops.isEmpty ? _txtDropHeader[language] : 'Final Drop (Receiver)',
        accentColor: AppColor.redColor,
        latLng: _latLngFromMap(widget.dropData),
        address: (widget.dropData['address'] ?? '').toString(),
        nameController: _dropNameController,
        phoneController: _dropPhoneController,
        houseController: _dropHouseController,
        landmarkController: _dropLandmarkController,
        noteController: _dropNoteController,
        nameHint: _txtNameHintDrop[language],
      ),
    ];
  }

  @override
  void dispose() {
    _pickupNameController.dispose();
    _pickupPhoneController.dispose();
    _pickupHouseController.dispose();
    _pickupLandmarkController.dispose();
    _pickupNoteController.dispose();

    _dropNameController.dispose();
    _dropPhoneController.dispose();
    _dropHouseController.dispose();
    _dropLandmarkController.dispose();
    _dropNoteController.dispose();
    for (final c in _stopNameControllers)  c.dispose();
    for (final c in _stopPhoneControllers) c.dispose();
    super.dispose();
  }

  Future<void> _pickContact(
      TextEditingController nameCtrl, TextEditingController phoneCtrl) async {
    try {
      bool permission = await ContactsPermissionHelper.ensureContactsPermission(context);
      if (permission) {
        final contact = await FlutterContacts.openExternalPick();
        if (contact != null) {
          final fullContact = await FlutterContacts.getContact(contact.id, withProperties: true);
          if (fullContact != null) {
            String name = fullContact.displayName;
            String phone = '';
            if (fullContact.phones.isNotEmpty) {
              phone = fullContact.phones.first.number;
              // Clean phone number
              phone = phone.replaceAll(RegExp(r'\D'), '');
              if (phone.length > 10) {
                if (phone.startsWith('91')) {
                  phone = phone.substring(2);
                } else if (phone.startsWith('0')) {
                  phone = phone.substring(1);
                }
              }
              if (phone.length > 10) {
                phone = phone.substring(phone.length - 10);
              }
            }
            setState(() {
              nameCtrl.text = name;
              phoneCtrl.text = phone;
            });
          }
        }
      } else {
        if (mounted) {
          SnackBarToastMessage.showSnackBar(
            context,
            language == 1
                ? "संपर्क अनुमति अस्वीकार कर दी गई थी।"
                : "Contacts permission was denied. Please enable in settings.",
          );
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarToastMessage.showSnackBar(
          context,
          "Error picking contact: ${e.toString()}",
        );
      }
    }
  }

  void _useMyNumber(
      TextEditingController nameCtrl, TextEditingController phoneCtrl) {
    final user = Provider.of<UserController>(context, listen: false);
    String name = user.getUserName;
    String phone = user.getUserMobile;

    phone = phone.replaceAll(RegExp(r'\D'), '');
    if (phone.length > 10) {
      if (phone.startsWith('91')) {
        phone = phone.substring(2);
      } else if (phone.startsWith('0')) {
        phone = phone.substring(1);
      }
    }
    if (phone.length > 10) {
      phone = phone.substring(phone.length - 10);
    }

    setState(() {
      nameCtrl.text = name;
      phoneCtrl.text = phone;
    });
  }

  void _submitBooking() {
    // Build enriched extra stops with contacts collected from the form
    final stopsWithContacts = widget.extraStops.asMap().entries.map((e) {
      final i = e.key;
      final stop = Map<String, dynamic>.from(e.value);
      stop['contact_name']  = _stopNameControllers[i].text.trim();
      stop['contact_phone'] = _stopPhoneControllers[i].text.trim();
      return stop;
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewConfirmScreen(
          vehicleTypeId: widget.vehicleTypeId,
          subVehicleTypeId: widget.subVehicleTypeId,
          vehicleData: widget.vehicleData,
          pickupData: widget.pickupData,
          dropData: widget.dropData,
          rawDistanceKm: widget.rawDistanceKm,
          estimatedFare: widget.estimatedFare,
          subVehicleTypeList: widget.subVehicleTypeList,
          bookingType: widget.bookingType,
          pickupDate: widget.pickupDate,
          pickupSlot: widget.pickupSlot,
          pickupContactName: _pickupNameController.text.trim(),
          pickupContactPhone: _pickupPhoneController.text.trim(),
          pickupHouse: _pickupHouseController.text.trim(),
          pickupLandmark: _pickupLandmarkController.text.trim(),
          pickupNote: _pickupNoteController.text.trim(),
          dropContactName: _dropNameController.text.trim(),
          dropContactPhone: _dropPhoneController.text.trim(),
          dropHouse: _dropHouseController.text.trim(),
          dropLandmark: _dropLandmarkController.text.trim(),
          dropNote: _dropNoteController.text.trim(),
          extraStops: stopsWithContacts,
        ),
      ),
    );
  }

  void _onNextOrProceed() {
    final step = _steps[_currentStepIndex];
    if (!(step.formKey.currentState?.validate() ?? true)) return;

    if (_currentStepIndex == _steps.length - 1) {
      _submitBooking();
    } else {
      setState(() => _currentStepIndex++);
    }
  }

  void _onBack() {
    if (_currentStepIndex > 0) {
      setState(() => _currentStepIndex--);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = AppColor.themeColor;
    final size = MediaQuery.of(context).size;
    final step = _steps[_currentStepIndex];
    final isLastStep = _currentStepIndex == _steps.length - 1;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          step.title,
          style: const TextStyle(
            fontFamily: AppFont.fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: AppColor.blackColor,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColor.themeColor, size: 20),
          onPressed: _onBack,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: Row(
            children: [
              for (int i = 0; i < _steps.length; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i <= _currentStepIndex
                          ? themeColor
                          : const Color(0xffE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: ValueKey(_currentStepIndex),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Fixed, non-interactive map at max zoom (40% height) ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          height: size.height * 0.4,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xffE2E8F0)),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: step.latLng == null
                              ? Container(
                                  color: const Color(0xffF1F5F9),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.location_off_rounded,
                                      color: Colors.grey, size: 32),
                                )
                              : GoogleMap(
                                  initialCameraPosition: CameraPosition(
                                    target: step.latLng!,
                                    zoom: 19,
                                  ),
                                  markers: {
                                    Marker(
                                      markerId: const MarkerId('step_location'),
                                      position: step.latLng!,
                                    ),
                                  },
                                  // Fixed view only — the retailer already
                                  // chose this location on an earlier screen,
                                  // so every gesture is disabled here.
                                  // liteModeEnabled renders a single static
                                  // bitmap on Android (cheap even on low-end
                                  // devices); the gesture flags below lock it
                                  // down on iOS too, where lite mode isn't
                                  // supported.
                                  liteModeEnabled: true,
                                  zoomGesturesEnabled: false,
                                  scrollGesturesEnabled: false,
                                  rotateGesturesEnabled: false,
                                  tiltGesturesEnabled: false,
                                  zoomControlsEnabled: false,
                                  compassEnabled: false,
                                  myLocationEnabled: false,
                                  myLocationButtonEnabled: false,
                                  buildingsEnabled: false,
                                  indoorViewEnabled: false,
                                ),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Booking summary strip
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xffF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xffE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  height: 40,
                                  width: 40,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: themeColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    widget.vehicleData['wheelCount'] == 2
                                        ? Icons.two_wheeler_rounded
                                        : widget.vehicleData['wheelCount'] == 3
                                            ? Icons.electric_rickshaw_rounded
                                            : Icons.local_shipping_rounded,
                                    color: themeColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${widget.vehicleData['name'] ?? 'Vehicle'}  •  ${widget.rawDistanceKm.toStringAsFixed(1)} km  •  ₹${widget.estimatedFare}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: AppFont.fontFamily,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: AppColor.blackColor,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: widget.bookingType.toLowerCase() == 'now'
                                        ? AppColor.successCOlor.withOpacity(0.12)
                                        : Colors.orange.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    widget.bookingType,
                                    style: TextStyle(
                                      fontFamily: AppFont.fontFamily,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      color: widget.bookingType.toLowerCase() == 'now'
                                          ? AppColor.successCOlor
                                          : Colors.orange,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Address line for this step's fixed location
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on_rounded,
                                  color: step.accentColor, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  step.address.isEmpty
                                      ? '—'
                                      : step.address,
                                  style: const TextStyle(
                                    fontFamily: AppFont.fontFamily,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppColor.blackColor,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Form(
                            key: step.formKey,
                            child: _buildContactFormCard(step),
                          ),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Next / Proceed Button Panel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xffE2E8F0))),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _onNextOrProceed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isLastStep ? _txtProceed[language] : _txtNext[language],
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactFormCard(_LocationStep step) {
    final accentColor = step.accentColor;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick-action pill buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _useMyNumber(step.nameController, step.phoneController),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColor.themeColor.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColor.themeColor.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_rounded, size: 15, color: AppColor.themeColor),
                          const SizedBox(width: 6),
                          Text(
                            _txtUseMyNumber[language],
                            style: const TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColor.themeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickContact(step.nameController, step.phoneController),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: accentColor.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.contacts_rounded, size: 15, color: accentColor),
                          const SizedBox(width: 6),
                          Text(
                            _txtSelectContact[language],
                            style: TextStyle(
                              fontFamily: AppFont.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            _fieldLabel(_txtNameLabel[language]),
            const SizedBox(height: 6),
            TextFormField(
              controller: step.nameController,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                fontFamily: AppFont.fontFamily,
                fontSize: 13,
                color: AppColor.blackColor,
                fontWeight: FontWeight.w500,
              ),
              decoration: _fieldDecoration(hint: step.nameHint),
            ),
            const SizedBox(height: 12),

            _fieldLabel(_txtPhoneLabel[language]),
            const SizedBox(height: 6),
            TextFormField(
              controller: step.phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [PhoneNumberFormatter()],
              style: const TextStyle(
                fontFamily: AppFont.fontFamily,
                fontSize: 13,
                color: AppColor.blackColor,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
              buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return _txtValPhoneEmpty[language];
                }
                if (val.trim().length != 10 || double.tryParse(val) == null) {
                  return _txtValPhoneInvalid[language];
                }
                return null;
              },
              decoration: _fieldDecoration(
                hint: _txtPhoneHint[language],
                prefixIcon: Icons.phone_iphone_rounded,
                showErrorBorder: true,
              ),
            ),

            if (step.houseController != null) ...[
              const SizedBox(height: 12),
              _fieldLabel(_txtHouseLabel[language]),
              const SizedBox(height: 6),
              TextFormField(
                controller: step.houseController,
                keyboardType: TextInputType.text,
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 13,
                  color: AppColor.blackColor,
                  fontWeight: FontWeight.w500,
                ),
                decoration: _fieldDecoration(
                  hint: _txtHouseHint[language],
                  prefixIcon: Icons.home_work_rounded,
                ),
              ),
            ],

            if (step.landmarkController != null) ...[
              const SizedBox(height: 12),
              _fieldLabel(_txtLandmarkLabel[language]),
              const SizedBox(height: 6),
              TextFormField(
                controller: step.landmarkController,
                keyboardType: TextInputType.text,
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 13,
                  color: AppColor.blackColor,
                  fontWeight: FontWeight.w500,
                ),
                decoration: _fieldDecoration(
                  hint: _txtLandmarkHint[language],
                  prefixIcon: Icons.pin_drop_rounded,
                ),
              ),
            ],

            if (step.noteController != null) ...[
              const SizedBox(height: 12),
              _fieldLabel(_txtNoteLabel[language]),
              const SizedBox(height: 6),
              TextFormField(
                controller: step.noteController,
                keyboardType: TextInputType.text,
                maxLines: 2,
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 13,
                  color: AppColor.blackColor,
                  fontWeight: FontWeight.w500,
                ),
                decoration: _fieldDecoration(
                  hint: _txtNoteHint[language],
                  prefixIcon: Icons.note_alt_rounded,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontFamily: AppFont.fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 11,
          color: AppColor.fontColor,
        ),
      );

  InputDecoration _fieldDecoration({
    required String hint,
    IconData? prefixIcon,
    bool showErrorBorder = false,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: AppFont.fontFamily,
        fontSize: 12,
        color: AppColor.hintTextColor,
        letterSpacing: 0,
      ),
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, color: AppColor.hintTextColor, size: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      fillColor: const Color(0xffF8FAFC),
      filled: true,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xffE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColor.themeColor, width: 1.5),
      ),
      errorBorder: showErrorBorder
          ? OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColor.redColor),
            )
          : null,
      focusedErrorBorder: showErrorBorder
          ? OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColor.redColor, width: 1.5),
            )
          : null,
    );
  }
}
