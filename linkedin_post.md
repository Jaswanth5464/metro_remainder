# Draft LinkedIn Post for Metro Reminder App

Here is the updated draft for your LinkedIn post. It features your custom Hyderabad Metro example, route optimization, and your GitHub/contact details.

---

### Post Title: 🚇 Introducing Metro Wake-Up: A 100% Offline-First Flutter App Built for Hyderabad Metro Commuters! 📱✨

Have you ever fallen asleep on a metro train, got lost in your music, and missed your transfer station or final destination? 😴🎵

I built a solution specifically for **Hyderabad Metro** commuters: **Metro Wake-Up**! It is a smart, production-grade journey companion built with **Flutter** that works **100% offline** to wake you up exactly when you need to change trains or get down.

---

### 💡 How It Works (Real-World Example):
Imagine you are traveling from **Chikkadpally to Raidurg**:
1. **Smart Routing**: You choose your destination. The app automatically calculates the best paths and lets you choose between a route with the **least transfers** or **least stops**.
2. **Auto-Source Detection**: It detects your boarding station based on your location.
3. **Interchange Alarm**: As you approach **JBS Parade Ground** (where you must switch from the Green Line to the Blue Line), the app sounds a transfer alarm so you don't miss the interchange.
4. **Destination Alarm**: Once you get on the Blue Line train, the app tracks you offline and rings a loud alarm as you approach **Raidurg**, ensuring you exit safely.

---

### 🌟 Key Features Built-in:

*   🤖 **Intelligent Pathfinding Engine**: Calculates the absolute shortest or most convenient route (e.g., minimum interchanges/stops) completely on-device using a local SQLite database.
*   🛰️ **100% Offline GPS Tracking**: Tracks your location using internal GPS signals. It never uploads your private coordinates to an external server.
*   📐 **Vector Route-Snapping & Speed Estimation**: Snaps raw GPS points to the exact metro line segment using vector mathematics, filtering out noise with a custom smoothing engine.
*   🚇 **Tunnel Dead-Reckoning (Tunnel Mode)**: Subways lose GPS signal underground. I implemented a dead-reckoning algorithm that estimates travel progression based on speed and time, keeping notifications running even in deep tunnels!
*   🚨 **Multi-Stage Wake-Up Alarms**: Triggers gentle warnings (3 min out), escalates vibration/volume (90 sec out), and fires emergency alerts (arriving now) with custom audio and heavy haptic feedback.
*   🚗 **Last-Mile Ride Booking Integration**: Integrates deep links to Uber and Rapido at the final station for seamless last-mile connectivity.
*   🗺️ **Offline Map Fallback**: Interactive dark-themed maps that automatically fall back to high-resolution asset images when offline.

---

### 🛠️ Technical Stack:
*   **Framework**: Flutter (Dart)
*   **Local DB**: SQLite (DatabaseHelper)
*   **State Management**: ValueNotifier & StreamSubscriptions
*   **Background execution**: `flutter_background_service` (Foreground Service mode on Android to prevent system termination)
*   **Notifications & Audio**: `flutter_local_notifications` & `audioplayers`
*   **System Controls**: `wakelock_plus` to keep screens awake during critical disembark stages

---

💡 **Recruiters & Clients**: This project showcases full-stack mobile development expertise, complex background services, mathematics for spatial coordinates, local DB caching, and offline-first product architecture.

Check out the code here: https://github.com/Jaswanth5464/metro_remainder 💻
Contact me at: jaswanth5464@gmail.com 📧

#Flutter #Dart #HyderabadMetro #MobileDevelopment #OfflineFirst #SoftwareEngineering #OpenSource #AppDevelopment #FlutterDev
