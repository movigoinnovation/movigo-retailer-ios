# Customer App deployment notes

Applied fixes:
- switched API and socket base URLs to HTTPS
- disabled cleartext traffic
- added ProGuard rules file required by release build
- removed sensitive OTP/token debug logging
- replaced test Razorpay key placeholder
- fixed bookingId/driverId misuse in live tracking flow

Before release:
1. Replace `rzp_live_REPLACE_ME` with your real live Razorpay key.
2. Add your release keystore and release signing config.
3. Verify your production domain supports HTTPS and secure socket connections.
4. Run a full customer journey test in release mode: login -> create booking -> driver accept -> pickup OTP -> tracking -> delivery OTP -> payment/invoice.
