Movigo final patch status

I applied code-level fixes for:
- Customer/retailer new vehicle UI routing and pricing modifiers
- Customer booking REST polling fallback for accepted driver status
- Driver Pusher user id fallback and REST booking fallback
- Safer API JSON parsing and 200/201 handling
- user_id/_id fallback and safe lat/lng parsing
- Driver post-profile navigation fix
- Driver wallet filename import fix
- Backend vehicle category fields, booking fields, pricing utility, category-matched driver filtering, accept validation
- Backend driver documents, vehicle photo, bank details, delete account, bank/helper update/delete/add routes

Verification completed:
- Node.js syntax check passed for all modified backend files.
- Static package-import path check passed for customer and driver lib/ folders.

Limits:
- Flutter SDK was not available in this environment, so flutter analyze / flutter build could not be run.
- Admin upload contains a built/minified web app, not editable React source. Backend admin APIs are updated, but a clean admin dropdown UI requires the original admin source project.
- Live runtime testing requires your MongoDB, Pusher/FCM, Razorpay, Google Maps keys, and deployed backend.
