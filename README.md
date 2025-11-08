#  Milestone Tracker

> **A simple, focused Flutter application to help you break large goals into actionable milestones and track your progress over time.**

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

---

##  Features

- **Goal Setting**: Define your primary long-term goal.  
- **Milestone Tracking**: Break down your goal into smaller, manageable milestones with specific tasks.  
- **Focus Timer**: Use the built-in timer for distraction-free work sessions.  
- **Progress Reports**: Weekly, monthly, and yearly insights on time spent & tasks completed.  
- **Task Suggestions**: AI-powered suggestions to make tasks more actionable.

---

##  Getting Started

### **Prerequisites**
- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- A [Firebase](https://firebase.google.com/) project
- A [Google Gemini API Key](https://ai.google.dev/)

---

### **Setup**

1️⃣ **Clone the repository:**
git clone https://github.com/your-username/trackit.git
cd trackit

text

2️⃣ **Install dependencies:**
flutter pub get

text

3️⃣ **Configure Firebase:**
   - Create a new Firebase project.
   - Run:
     ```
     flutterfire configure
     ```
   - Enable **Email/Password** and **Google Authentication** in the Firebase Console.  
   - Set up **Firestore Database**.

4️⃣ **Add API Key:**
   - Create a `.env` file in the project root.
   - Add:
     ```
     GEMINI_API_KEY=your_api_key_here
     ```

5️⃣ **Run the App:**
flutter run

text

---

##  Technology Stack

| Tool       | Purpose |
|------------|---------|
| **Flutter** | Cross-platform UI toolkit |
| **Dart** | Programming language |
| **Firebase** | Authentication & Firestore |
| **Google Gemini API** | AI task suggestions |

---

##  Contributing

💡 Got ideas to make this app even better? Contributions are welcome!  
Here’s how:
1. Fork this repository.
2. Create a new branch (`feature/new-feature`).
3. Commit your changes.
4. Push to your branch and create a PR.

---

##  License

This project is open source and available under the [MIT License](LICENSE).

---

> _Craft your goals. Track your milestones. Achieve more._
